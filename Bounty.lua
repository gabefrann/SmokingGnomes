-- Smoking Gnomes Inc.: Recall Notices (bounties).
--
-- An officer posts a Recall Notice on a named player. Whoever lands the killing blow
-- (you or your pet, open world) while the notice is open claims it automatically.
-- The earliest claim wins. Rewards are paid by the officer by hand.
--
-- Records (both signed, both relayed like player numbers):
--   bounty: id | poster | target | reward | created | expires | status | u
--   claim:  id | claimer | t | victimGUID | victim | zone

local _, ns = ...
local SG = ns.SG

local Bounty = {}
ns.Bounty = Bounty

local OFFICER_RANK = 1          -- guild rank index 0 (guild master) and 1 may post
local DURATION = 7 * 86400      -- notices stay open for a week
-- Closed reports on the Spies tab: see Bounty.List (withdrawn: hidden; expired: a day;
-- eliminated: until the weekly reset).
local KEEP = 30 * 86400         -- then they are deleted
local RELAY_CLOSED = 14 * 86400 -- closed notices are relayed this long after closing
local NEWS_WINDOW = 30 * 60     -- only notices/claims this fresh get a popup
local MAX_MSG = 250
local CLAIM_BASE = 4000000000   -- claim version = CLAIM_BASE - time, so earlier claims win

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function trim(s)
	return (tostring(s or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normRealm(r)
	return (tostring(r or ""):gsub("[%s%-']", ""):lower())
end

local function makeId(created, poster)
	return created .. "." .. SG.sign("id", poster):sub(1, 6)
end

function SG.IsOfficer(name)
	local rank = SG.roster and SG.roster[name]
	if rank == nil and SG.roster then
		-- The roster may list names differently (first name only, or with a realm).
		for rosterName, r in pairs(SG.roster) do
			if SG.sameName(rosterName, name) then
				rank = r
				break
			end
		end
	end
	if rank == nil then
		return nil -- unknown (roster not loaded, or not in the guild)
	end
	return rank <= OFFICER_RANK
end

local BFIELDS = { "id", "poster", "target", "reward", "created", "expires", "status", "u" }
local BNUM = { created = true, expires = true, u = true }
local CFIELDS = { "id", "claimer", "t", "guid", "victim", "zone" }
local CNUM = { t = true }

local function encode(rec, fields)
	local out = {}
	for i, k in ipairs(fields) do
		out[i] = tostring(rec[k] or ""):gsub("|", "")
	end
	return table.concat(out, "|")
end

local function decode(raw, sig, fields, nums, kind)
	if type(raw) ~= "string" or sig ~= SG.sign(kind, raw) then
		return nil
	end
	local parts = { strsplit("|", raw) }
	if #parts ~= #fields then
		return nil
	end
	local rec = { raw = raw, sig = sig }
	for i, k in ipairs(fields) do
		if nums[k] then
			local n = tonumber(parts[i])
			if not n or n < 0 or n ~= math.floor(n) then
				return nil
			end
			rec[k] = n
		else
			rec[k] = parts[i]
		end
	end
	return rec
end

local function decodeBounty(raw, sig)
	local b = decode(raw, sig, BFIELDS, BNUM, "B")
	if not b or b.target == "" or b.poster == "" then
		return nil
	end
	if b.id ~= makeId(b.created, b.poster) or (b.status ~= "open" and b.status ~= "cancelled") then
		return nil
	end
	if b.expires <= b.created or b.u < b.created or b.created > SG.now() + 600 then
		return nil
	end
	return b
end

local function decodeClaim(raw, sig)
	local c = decode(raw, sig, CFIELDS, CNUM, "C")
	if not c or c.claimer == "" or c.t > SG.now() + 600 then
		return nil
	end
	return c
end

local function seal(rec, fields, kind)
	rec.raw = encode(rec, fields)
	rec.sig = SG.sign(kind, rec.raw)
end

local function bountyMessage(b)
	return ("B|%d|%s|%s"):format(SG.VERSION, b.raw, b.sig)
end

local function claimMessage(c)
	return ("C|%d|%s|%s"):format(SG.VERSION, c.raw, c.sig)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function db()
	return SG.db.bounties, SG.db.claims
end

-- A claim counts if it was made while the notice was open.
local function claimValid(b, c)
	if not b or not c then
		return false
	end
	if c.t < b.created or c.t > b.expires then
		return false
	end
	if b.status == "cancelled" and c.t > b.u then
		return false
	end
	return true
end

function Bounty.State(b)
	local _, claims = db()
	local c = claims[b.id]
	if claimValid(b, c) then
		return "claimed", c
	end
	if b.status == "cancelled" then
		return "cancelled"
	end
	if SG.now() > b.expires then
		return "expired"
	end
	return "open"
end

-- When the notice stopped being open, for sorting and expiry of the list.
local function closedAt(b, state, c)
	if state == "claimed" then
		return c.t
	elseif state == "cancelled" then
		return b.u
	elseif state == "expired" then
		return b.expires
	end
	return nil
end

function Bounty.Version(kind, key)
	local bounties, claims = db()
	if kind == "bounty" then
		local b = bounties[key]
		return b and b.u or 0
	end
	local c = claims[key]
	return c and (CLAIM_BASE - c.t) or 0
end

function Bounty.Message(id)
	local b = db()[id]
	return b and bountyMessage(b)
end

function Bounty.ClaimMessage(id)
	local _, claims = db()
	local c = claims[id]
	return c and claimMessage(c)
end

-- Records worth relaying: open notices first, then recently closed ones and their claims.
function Bounty.RelayList()
	local bounties, claims = db()
	local now, out, closed = SG.now(), {}, {}
	for id, b in pairs(bounties) do
		local state, c = Bounty.State(b)
		local at = closedAt(b, state, c)
		if not at then
			out[#out + 1] = { "bounty", id }
		elseif now - at < RELAY_CLOSED then
			closed[#closed + 1] = { "bounty", id }
		end
		if claims[id] and (not at or now - at < RELAY_CLOSED) then
			closed[#closed + 1] = { "claim", id }
		end
	end
	for _, rec in ipairs(closed) do
		out[#out + 1] = rec
	end
	return out
end

-- Reports for the Spies tab: open ones (ending soonest first), then eliminated spies.
-- Withdrawn reports leave the list straight away, expired ones after a day, and
-- eliminated spies stay up as trophies until the weekly reset.
function Bounty.List()
	local bounties = db()
	local now, open, closed = SG.now(), {}, {}
	local weekStart = now + SG.secondsUntilReset() - 7 * 86400
	for _, b in pairs(bounties) do
		local state, c = Bounty.State(b)
		local at = closedAt(b, state, c)
		local show
		if not at then
			open[#open + 1] = { b = b, state = state }
		elseif state == "claimed" then
			show = at >= weekStart
		elseif state == "expired" then
			show = now - at < 86400
		end -- withdrawn: not shown
		if show then
			closed[#closed + 1] = { b = b, state = state, claim = c, at = at }
		end
	end
	table.sort(open, function(x, y)
		return x.b.expires < y.b.expires
	end)
	table.sort(closed, function(x, y)
		return x.at > y.at
	end)
	for _, row in ipairs(closed) do
		open[#open + 1] = row
	end
	return open
end

function Bounty.OpenCount()
	local n = 0
	for _, b in pairs(db()) do
		if Bounty.State(b) == "open" then
			n = n + 1
		end
	end
	return n
end

-- Recalls completed by a player, from the notices this client knows about.
function Bounty.CompletedBy(name)
	local bounties, claims = db()
	local n = 0
	for id, c in pairs(claims) do
		if c.claimer == name and claimValid(bounties[id], c) then
			n = n + 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Officers: post and cancel
---------------------------------------------------------------------------

local function findOpen(target, poster)
	for _, b in pairs(db()) do
		if SG.sameName(b.target, target) and Bounty.State(b) == "open" and (not poster or b.poster == poster) then
			return b
		end
	end
	return nil
end

-- Returns true on success, or false and a message for the officer.
function Bounty.Post(target, reward)
	local officer = SG.IsOfficer(SG.myName)
	if officer == nil then
		return false, "The guild roster hasn't loaded yet. Try again in a moment."
	elseif not officer then
		return false, "Only officers can report corporate spies."
	end
	-- Names can have a surname ("Legs Dogman"); capitalise each part.
	target = SG.fullName(trim(target)) or ""
	if #target < 2 or #target > 40 then
		return false, "Enter the player's name, like Fizzwick or Legs Dogman."
	end
	if target:find("%d") then
		return false, "\"" .. target .. "\" looks like a reward, not a name. Use /gnomes spy Name reward, or target the player first."
	end
	target = target:gsub("(%S)(%S*)", function(a, b) return a:upper() .. b end)
	if findOpen(target) then
		return false, "There's already a spy report on " .. target .. "."
	end
	reward = trim(reward)
	if reward == "" then
		reward = "Bragging rights"
	end
	reward = reward:sub(1, 30)

	local now = SG.now()
	local b = {
		id = makeId(now, SG.myName), poster = SG.myName, target = target, reward = reward,
		created = now, expires = now + DURATION, status = "open", u = now,
	}
	seal(b, BFIELDS, "B")
	while #bountyMessage(b) > MAX_MSG and #b.reward > 1 do
		b.reward = b.reward:sub(1, -2)
		seal(b, BFIELDS, "B")
	end
	if #bountyMessage(b) > MAX_MSG then
		return false, "That name is too long."
	end
	SG.db.bounties[b.id] = b
	ns.Sync.Enqueue("bounty", b.id, true, true)
	ns.UI.Notice("Corporate spy: " .. target, "red", "Reward: " .. reward, "Reported to the guild. Zero tolerance: it's on sight.")
	ns.UI.Refresh()
	return true
end

function Bounty.Cancel(target)
	local b = findOpen(SG.fullName(trim(target)) or "", SG.myName)
	if not b then
		return false, "You haven't reported that player as a spy."
	end
	b.status, b.u = "cancelled", SG.now()
	seal(b, BFIELDS, "B")
	ns.Sync.Enqueue("bounty", b.id, true, true)
	ns.UI.Refresh()
	return true
end

---------------------------------------------------------------------------
-- Claiming: called for every resolved world PvP kill
---------------------------------------------------------------------------

-- Full name match ("Legs Dogman"); a report with just a first name matches any surname.
local function matches(b, name, realm)
	return SG.sameName(b.target, name)
end

local function better(new, old)
	if not old then
		return true
	end
	if new.t ~= old.t then
		return new.t < old.t
	end
	return new.claimer < old.claimer
end

function Bounty.OnKill(guid, name, realm, zone, kind)
	if not name or (kind ~= "me" and kind ~= "pet") then
		return
	end
	local bounties, claims = db()
	for id, b in pairs(bounties) do
		if Bounty.State(b) == "open" and matches(b, name, realm) then
			local c = { id = id, claimer = SG.myName, t = SG.now(), guid = guid, victim = name, zone = zone or "" }
			seal(c, CFIELDS, "C")
			if better(c, claims[id]) then
				claims[id] = c
				ns.Sync.Enqueue("claim", id, true, true)
				ns.UI.Notice("Spy eliminated!", "gold", name .. "  ·  Reward: " .. b.reward,
					"Collect from " .. SG.shortName(b.poster) .. ".")
				SG.print(("You eliminated corporate spy %s. Collect %s from %s."):format(name, b.reward, SG.shortName(b.poster)))
			end
		end
	end
	ns.UI.Refresh()
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

function Bounty.Receive(raw, sig, sender)
	local b = decodeBounty(raw, sig)
	if not b then
		return
	end
	ns.Sync.MarkHeard("bounty", b.id, b.u)
	if SG.IsOfficer(b.poster) == false then
		return -- the poster is in the guild but not an officer
	end
	local bounties = db()
	local old = bounties[b.id]
	if old and b.u <= old.u then
		return
	end
	bounties[b.id] = b

	local fresh = SG.now() - b.u < NEWS_WINDOW
	if b.status == "open" and not old and SG.now() < b.expires then
		if fresh then
			ns.UI.Notice("Corporate spy: " .. b.target, "red", "Reward: " .. b.reward,
				"Reported by " .. SG.shortName(b.poster) .. ". It's on sight.")
			SG.print(("Corporate spy reported: %s. Reward: %s. Reported by %s. It's on sight."):format(b.target, b.reward, SG.shortName(b.poster)))
		end
	elseif b.status == "cancelled" and old and old.status == "open" and fresh then
		SG.print(("The spy report on %s was withdrawn."):format(b.target))
	end
	ns.UI.Refresh()
end

function Bounty.ReceiveClaim(raw, sig, sender)
	local c = decodeClaim(raw, sig)
	if not c then
		return
	end
	ns.Sync.MarkHeard("claim", c.id, CLAIM_BASE - c.t)
	local bounties, claims = db()
	local b = bounties[c.id]
	if b then
		if not claimValid(b, c) then
			return
		end
		-- If this client knows the victim GUID, it must be the named target.
		local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, c.guid)
		name = ok and SG.str(name)
		if name and not matches(b, name, SG.str(realm)) then
			return
		end
	end
	if not better(c, claims[c.id]) then
		return
	end
	local hadClaim = claims[c.id] ~= nil
	claims[c.id] = c

	if b and not hadClaim and c.claimer ~= SG.myName and SG.now() - c.t < NEWS_WINDOW then
		ns.UI.Notice("Spy eliminated", "gold", SG.shortName(c.claimer) .. " took out " .. b.target,
			"Reward: " .. b.reward .. ".")
		SG.print(("%s eliminated corporate spy %s (%s)."):format(SG.shortName(c.claimer), b.target, b.reward))
	end
	ns.UI.Refresh()
end

---------------------------------------------------------------------------
-- Load: verify stored records, drop old ones, tell the player what's open.
---------------------------------------------------------------------------

function Bounty.Load()
	SG.db.bounties = SG.db.bounties or {}
	SG.db.claims = SG.db.claims or {}
	local bounties, claims = db()
	local now = SG.now()
	for id, stored in pairs(bounties) do
		local b = decodeBounty(stored.raw, stored.sig)
		if b and b.id == id then
			local state, c = Bounty.State(b)
			local at = closedAt(b, state, c)
			if at and now - at > KEEP then
				bounties[id], claims[id] = nil, nil
			else
				bounties[id] = b
			end
		else
			bounties[id] = nil
		end
	end
	for id, stored in pairs(claims) do
		local c = decodeClaim(stored.raw, stored.sig)
		if c and c.id == id then
			claims[id] = c
		elseif not (c and bounties[id]) then
			claims[id] = nil
		end
	end
	-- Give relays a moment, then mention open notices once.
	C_Timer.After(30, function()
		local n = Bounty.OpenCount()
		if n > 0 then
			SG.print((n == 1 and "1 corporate spy at large." or (n .. " corporate spies at large.")) .. " Type /gnomes to see them.")
		end
	end)
end

-- Used by /gnomes check: a signed notice and claim must round-trip, edits must fail.
function Bounty.SelfTest()
	local now = SG.now()
	local b = { id = makeId(now, "Test-Realm"), poster = "Test-Realm", target = "Fizzwick", reward = "50 gold",
		created = now, expires = now + DURATION, status = "open", u = now }
	seal(b, BFIELDS, "B")
	local c = { id = b.id, claimer = "Other-Realm", t = now, guid = "Player-1-0000", victim = "Fizzwick", zone = "Hillsbrad" }
	seal(c, CFIELDS, "C")
	local okB = decodeBounty(b.raw, b.sig) ~= nil and decodeBounty((b.raw:gsub("50 gold", "500 gold")), b.sig) == nil
	local okC = decodeClaim(c.raw, c.sig) ~= nil and decodeClaim((c.raw:gsub("Other", "Cheat")), c.sig) == nil
	local okM = matches(b, "fizzwick", "") and not matches(b, "Fizzbang", "")
	return okB and okC and okM
end

-- Drop notices from players the roster now shows aren't officers.
function Bounty.OnRoster()
	local bounties = db()
	for id, b in pairs(bounties) do
		if SG.IsOfficer(b.poster) == false then
			bounties[id] = nil
		end
	end
end
