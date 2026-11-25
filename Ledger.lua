-- Smoking Gnomes Inc.: the company ledger of gnome kills.
--
-- Every gnome kill becomes a small signed record that is shared and relayed like the
-- other records. Each client keeps a running tally per victim, so hovering an Alliance
-- gnome shows how often the company has smoked them ("Smoked by the company: 3x").
--
-- Record: id | killer | t | victim | victimRealm | zone
-- Records are kept 30 days for relaying; the per-victim tallies are kept for good.

local _, ns = ...
local SG = ns.SG

local Ledger = {}
ns.Ledger = Ledger

local KEEP = 30 * 86400          -- how long individual kill records are stored
local RELAY_DEFAULT = 7 * 86400  -- how far back to relay to someone whose last login is unknown
local RELAY_SLACK = 3600         -- relay a little before their last login, to cover gaps

local FIELDS = { "id", "killer", "t", "victim", "vrealm", "zone" }

-- Running-joke labels by how often the company has smoked the same gnome.
local REGULARS = {
	{ 25, "Lifetime subscriber" },
	{ 10, "Loyal patient" },
	{ 3, "Repeat customer" },
}

local function normRealm(r)
	return (tostring(r or ""):gsub("[%s%-']", ""):lower())
end

local function myRealm()
	local ok, r = pcall(GetNormalizedRealmName)
	return ok and SG.str(r) or ""
end

-- One key per victim: the lower-case full name ("legs dogman"), without any realm.
function Ledger.Key(name, realm)
	local full = SG.fullName(name)
	return full and full:lower() or nil
end

local function encode(k)
	local out = {}
	for i, f in ipairs(FIELDS) do
		out[i] = tostring(k[f] or ""):gsub("|", "")
	end
	return table.concat(out, "|")
end

local function decode(raw, sig)
	if type(raw) ~= "string" or sig ~= SG.sign("K", raw) then
		return nil
	end
	local p = { strsplit("|", raw) }
	if #p ~= #FIELDS then
		return nil
	end
	local k = { raw = raw, sig = sig }
	for i, f in ipairs(FIELDS) do
		k[f] = p[i]
	end
	k.t = tonumber(k.t)
	if not k.t or k.t > SG.now() + 600 or k.victim == "" or k.killer == "" then
		return nil
	end
	-- id = time.killerHash.sequence (sequence separates several kills in the same second)
	local prefix = k.t .. "." .. SG.sign("id", k.killer):sub(1, 6) .. "."
	if k.id:sub(1, #prefix) ~= prefix or not tonumber(k.id:sub(#prefix + 1)) then
		return nil
	end
	return k
end

local function tally(k)
	local key = Ledger.Key(k.victim, k.vrealm)
	local v = SG.db.victims[key]
	if not v then
		v = { name = k.victim, n = 0, by = {} }
		SG.db.victims[key] = v
	end
	v.n = v.n + 1
	v.by[k.killer] = (v.by[k.killer] or 0) + 1
	if k.t > (v.last or 0) then
		v.last, v.lastBy = k.t, k.killer
	end
	return v
end

-- Store a record once; returns true if it was new.
local function add(k)
	local kills = SG.db.kills
	if kills[k.id] or SG.db.counted[k.id] then
		return false
	end
	if SG.now() - k.t > KEEP then
		return false -- too old to tell whether it was already counted
	end
	kills[k.id] = k
	SG.db.counted[k.id] = k.t
	tally(k)
	return true
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Called for each of my own gnome kills (not assists, not tests).
function Ledger.Record(victim, realm, zone)
	if not victim then
		return
	end
	local t = SG.now()
	local k = { killer = SG.myName, t = t, victim = victim, vrealm = realm or "", zone = zone or "" }
	local prefix = t .. "." .. SG.sign("id", SG.myName):sub(1, 6) .. "."
	local seq = 1
	while SG.db.kills[prefix .. seq] do
		seq = seq + 1
	end
	k.id = prefix .. seq
	k.raw = encode(k)
	k.sig = SG.sign("K", k.raw)
	if add(k) then
		ns.Sync.Enqueue("kill", k.id, false, true)
	end
end

function Ledger.Receive(raw, sig)
	local k = decode(raw, sig)
	if not k then
		return
	end
	ns.Sync.MarkHeard("kill", k.id, 1)
	if add(k) then
		ns.UI.Refresh()
	end
end

function Ledger.Message(id)
	local k = SG.db.kills[id]
	return k and ("K|%d|%s|%s"):format(SG.VERSION, k.raw, k.sig)
end

-- Kill records made after `since` (a server time), oldest first.
function Ledger.RelayList(since)
	since = since and (since - RELAY_SLACK) or (SG.now() - RELAY_DEFAULT)
	local list = {}
	for id, k in pairs(SG.db.kills) do
		if k.t >= since then
			list[#list + 1] = k
		end
	end
	table.sort(list, function(a, b)
		return a.t < b.t
	end)
	local out = {}
	for i, k in ipairs(list) do
		out[i] = { "kill", k.id }
	end
	return out
end

-- The tally for a victim, or nil.
function Ledger.Victim(name, realm)
	local key = Ledger.Key(name, realm)
	return key and SG.db.victims[key]
end

function Ledger.Label(n)
	for _, r in ipairs(REGULARS) do
		if n >= r[1] then
			return r[2]
		end
	end
	return nil
end

-- The company member who has smoked this victim the most.
function Ledger.TopKiller(v)
	local best, bestN = nil, 0
	for name, n in pairs(v.by or {}) do
		if n > bestN or (n == bestN and best and name < best) then
			best, bestN = name, n
		end
	end
	return best, bestN
end

function Ledger.Load()
	SG.db.kills = SG.db.kills or {}
	SG.db.victims = SG.db.victims or {}
	SG.db.counted = SG.db.counted or {} -- id -> time, so a record is never counted twice
	-- Tallies saved before 0.14 are keyed by first name ("little"); re-key them by full name.
	for key, v in pairs(SG.db.victims) do
		local want = v.name and Ledger.Key(v.name)
		if want and want ~= key then
			local existing = SG.db.victims[want]
			if existing then
				existing.n = existing.n + v.n
				for killer, n in pairs(v.by or {}) do
					existing.by[killer] = (existing.by[killer] or 0) + n
				end
			else
				SG.db.victims[want] = v
			end
			SG.db.victims[key] = nil
		end
	end
	local now = SG.now()
	for id, stored in pairs(SG.db.kills) do
		local k = decode(stored.raw, stored.sig)
		if not k or k.id ~= id or now - k.t > KEEP then
			SG.db.kills[id] = nil
		else
			SG.db.kills[id] = k
		end
	end
	for id, t in pairs(SG.db.counted) do
		if now - t > KEEP + 86400 then
			SG.db.counted[id] = nil
		end
	end
end
