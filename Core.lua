-- Smoking Gnomes: kill detection, counting and storage.

local ADDON, ns = ...

local SG = {}
ns.SG = SG

SG.VERSION = 1 -- sync protocol version (unchanged as long as old and new clients understand each other)

-- Release version from the .toc. The release packager writes the git tag in there;
-- an unpackaged copy reads "@project-version@" and counts as a dev build.
do
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local ok, v = pcall(get, ADDON, "Version")
	v = ok and type(v) == "string" and v:gsub("^v", "") or ""
	SG.RELEASE = v:match("^%d+%.%d+") and v or "dev"
end

-- Compares "1.2.3" style versions: returns true when a is newer than b.
function SG.newer(a, b)
	if type(a) ~= "string" or type(b) ~= "string" or a == "dev" or b == "dev" then
		return false
	end
	local pa, pb = {}, {}
	for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x > y
		end
	end
	return false
end
SG.PREFIX = "SmokingGnomes"
SG.ACCENT = "4cb56b"

local DEDUPE_SECONDS = 10    -- ignore a repeat PARTY_KILL for the same target
local PENDING_TTL = 120      -- how long a kill with an unreadable race waits for combat to end
local RECENT_MAX = 25        -- kills kept in "My kills"
local PRUNE_DAYS = 90        -- forget guildies with no kills not seen for this long
local WEEK = 7 * 86400

---------------------------------------------------------------------------
-- Secret-value guards. Never compare or do math on a value before these.
---------------------------------------------------------------------------

local issecret = _G.issecretvalue

function SG.secret(v)
	if v == nil or type(issecret) ~= "function" then
		return false
	end
	local ok, s = pcall(issecret, v)
	return (not ok) or s == true
end

function SG.str(v)
	if SG.secret(v) or type(v) ~= "string" or v == "" then
		return nil
	end
	return v
end

function SG.num(v)
	if SG.secret(v) or type(v) ~= "number" then
		return nil
	end
	return v
end

local str, num = SG.str, SG.num

local function call(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

---------------------------------------------------------------------------
-- Time, weeks, names
---------------------------------------------------------------------------

function SG.now()
	local ok, t = call(GetServerTime)
	return (ok and num(t)) or time()
end

local function secondsUntilReset()
	if C_DateAndTime then
		local ok, s = call(C_DateAndTime.GetSecondsUntilWeeklyReset)
		s = ok and num(s)
		if s and s > 0 and s <= WEEK then
			return s
		end
	end
	-- Fallback: EU reset, Wednesday 07:00 UTC. Epoch day 0 was a Thursday, so Wednesday is day % 7 == 6.
	local now = SG.now()
	local d = math.floor((now - 7 * 3600) / 86400)
	local k = (6 - d % 7) % 7
	if k == 0 then
		k = 7
	end
	return (d + k) * 86400 + 7 * 3600 - now
end
SG.secondsUntilReset = secondsUntilReset

-- A week is identified by the day number of its *next* reset, so every client agrees.
function SG.weekId()
	return math.floor((SG.now() + secondsUntilReset()) / 86400)
end

-- My realm as the game reports it. WoW Forever reports none, so this is often nil.
function SG.myRealm()
	local ok, realm = call(GetNormalizedRealmName)
	realm = ok and str(realm)
	if not realm then
		local ok2, r2 = call(GetRealmName)
		r2 = ok2 and str(r2)
		realm = r2 and str((r2:gsub("[%s%-]", "")))
	end
	return realm
end

-- One consistent key per player: the full character name. WoW Forever characters have
-- a first name and a surname ("Lih Zaddi"), and chat senders and GetPlayerInfoByGUID
-- give both. A "-Realm" suffix, if any, is dropped: a guild lives on one realm.
function SG.fullName(name)
	name = str(name)
	if not name then
		return nil
	end
	name = name:gsub("%-.*$", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return name ~= "" and name or nil
end

-- A unit's full name ("Lih Zaddi"). GetPlayerInfoByGUID gives first name and surname
-- together (proven by the kill log); UnitName may give the first name only, with the
-- surname as its second value on some builds, so it's the fallback.
function SG.unitFullName(unit)
	local okG, guid = call(UnitGUID, unit)
	guid = okG and str(guid)
	if guid and guid:match("^Player%-") then
		local okI, _, _, _, _, _, name = call(GetPlayerInfoByGUID, guid)
		name = okI and SG.fullName(name)
		if name then
			return name
		end
	end
	local ok, first, surname = call(UnitName, unit)
	first = ok and str(first)
	if not first then
		return nil
	end
	surname = str(surname)
	if surname and not first:find(" ", 1, true) then
		first = first .. " " .. surname
	end
	return SG.fullName(first)
end

-- Do two names refer to the same character? "Legs" matches "Legs Dogman" when only a
-- first name was given (an officer typing a spy's name, older saved data).
function SG.sameName(a, b)
	a, b = SG.fullName(a), SG.fullName(b)
	if not a or not b then
		return false
	end
	a, b = a:lower(), b:lower()
	if a == b then
		return true
	end
	if not a:find(" ", 1, true) or not b:find(" ", 1, true) then
		return a:match("^%S+") == b:match("^%S+")
	end
	return false
end

-- The name as shown: first name and surname, without any realm.
function SG.shortName(full)
	if not full then
		return "?"
	end
	return SG.fullName(full) or full
end

function SG.ago(t)
	if not t or t <= 0 then
		return "never"
	end
	local d = SG.now() - t
	if d < 60 then
		return "just now"
	elseif d < 3600 then
		return math.floor(d / 60) .. "m ago"
	elseif d < 86400 then
		return math.floor(d / 3600) .. "h ago"
	end
	return math.floor(d / 86400) .. "d ago"
end

function SG.duration(s)
	s = math.max(0, math.floor(s or 0))
	local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
	if d > 0 then
		return d .. "d " .. h .. "h"
	end
	return h .. "h " .. m .. "m"
end

function SG.print(msg)
	print("|cff" .. SG.ACCENT .. "Smoking Gnomes Inc.|r " .. msg)
end

---------------------------------------------------------------------------
-- Storage. One entry per character (Name-Realm) in the account-wide DB.
-- entry = { total, week, weekId, assists, wa, prevWeek, prevWeekId, lastKill, class, seen, test }
---------------------------------------------------------------------------

local function initDB()
	SmokingGnomesDB = SmokingGnomesDB or {}
	local db = SmokingGnomesDB
	if db.schema ~= 2 then
		-- 0.4.x stored unsigned numbers; only test data existed, so start clean.
		db.players, db.schema = {}, 2
	end
	db.players = db.players or {}
	db.recent = db.recent or {}
	db.settings = db.settings or {}
	if db.settings.toast == nil then
		db.settings.toast = true
	end
	SG.db = db
end

function SG.rollWeek(e)
	local cur = SG.weekId()
	if e.weekId ~= cur then
		if e.weekId == cur - 7 then
			e.prevWeek, e.prevWeekId = e.week or 0, e.weekId
		end
		e.week, e.wa, e.weekId = 0, 0, cur
	end
end

-- Weekly numbers for any entry, without mutating someone else's data.
function SG.weekCounts(e, cur)
	if e.weekId == cur then
		return e.week or 0, e.wa or 0
	end
	return 0, 0
end

function SG.lastWeekCount(e, cur)
	local lw = cur - 7
	if e.weekId == lw then
		return e.week or 0
	elseif e.prevWeekId == lw then
		return e.prevWeek or 0
	end
	return 0
end

---------------------------------------------------------------------------
-- Signed entries.
-- Each player's numbers live in one canonical string (`raw`) plus a signature over
-- name + raw. The numbers shown are always parsed from `raw`, so editing them in the
-- SavedVariables file does nothing, and editing `raw` breaks the signature. The same
-- raw + sig travels over sync, so relayed numbers can't be altered on the way.
-- This stops casual tampering (file edits, pasted /run scripts). It can't stop someone
-- who reads this code; peers' plausibility checks in Sync.lua limit what they can do.
---------------------------------------------------------------------------

local SALT = "SmokingGnomes|v2|gnomes-first|lok'tar"
local FIELDS = { "total", "week", "weekId", "assists", "wa", "prevWeek", "prevWeekId", "lastKill", "u", "class", "lastVictim" }
local NUMERIC = 9 -- the first 9 fields are whole numbers
SG.FIELD_COUNT = #FIELDS

local function hash(s)
	local h1, h2 = 5381, 52711
	for i = 1, #s do
		local c = s:byte(i)
		h1 = (h1 * 33 + c) % 4294967296
		h2 = (h2 * 31 + c * 7 + i) % 4294967296
	end
	return tostring(h1) .. "x" .. tostring(h2)
end

function SG.sign(name, raw)
	return hash(SALT .. "|" .. name .. "|" .. raw)
end

function SG.encode(e)
	local out = {}
	for i, k in ipairs(FIELDS) do
		if i <= NUMERIC then
			out[i] = tostring(math.max(0, math.floor(tonumber(e[k]) or 0)))
		else
			out[i] = tostring(e[k] or ""):gsub("|", "")
		end
	end
	return table.concat(out, "|")
end

-- Returns a fresh entry table when the signature and every field check out, else nil.
function SG.decode(name, raw, sig)
	if type(name) ~= "string" or type(raw) ~= "string" or sig ~= SG.sign(name, raw) then
		return nil
	end
	local parts = { strsplit("|", raw) }
	if #parts ~= #FIELDS then
		return nil
	end
	local e = { raw = raw, sig = sig }
	for i, k in ipairs(FIELDS) do
		if i <= NUMERIC then
			local n = tonumber(parts[i])
			if not n or n < 0 or n ~= math.floor(n) then
				return nil
			end
			e[k] = n
		else
			e[k] = parts[i] ~= "" and parts[i] or nil
		end
	end
	return e
end

-- Re-sign my own entry after any change.
function SG.seal(e)
	local raw = SG.encode(e)
	if raw ~= e.raw then
		e.raw, e.sig = raw, SG.sign(SG.myName, raw)
	end
end

local function blankEntry()
	return { total = 0, week = 0, wa = 0, assists = 0, weekId = SG.weekId(), u = 0 }
end

-- Rebuild every stored entry from its signed string; drop anything that fails.
local function verifyStore()
	local players = SG.db.players
	for name, stored in pairs(players) do
		local e = SG.decode(name, stored.raw, stored.sig)
		if e then
			e.seen, e.bad = stored.seen, stored.bad
			players[name] = e
		elseif name == SG.myName then
			players[name] = blankEntry()
			SG.recovering = true
		else
			players[name] = nil
		end
	end
end

function SG.me()
	local players = SG.db.players
	local e = players[SG.myName]
	if not e then
		e = blankEntry()
		players[SG.myName] = e
	end
	SG.rollWeek(e)
	e.class = SG.myClass or e.class
	e.seen = SG.now()
	SG.seal(e)
	return e
end

-- The guild holds a copy of my numbers. Used after a reinstall, a new PC or a broken
-- file (SG.freshStart: my entry started blank this session and hasn't been sent yet),
-- or when playing the same character from two PCs.
function SG.adoptOwn(remote)
	local e = SG.db.players[SG.myName]
	SG.rollWeek(remote)
	if SG.freshStart and e then
		-- Keep any kills made since login on top of the guild's copy.
		remote.total = remote.total + (e.total or 0)
		remote.assists = remote.assists + (e.assists or 0)
		if remote.weekId == e.weekId then
			remote.week = remote.week + (e.week or 0)
			remote.wa = remote.wa + (e.wa or 0)
		end
		if (e.lastKill or 0) > (remote.lastKill or 0) then
			remote.lastKill, remote.lastVictim = e.lastKill, e.lastVictim
		end
		remote.u = math.max(remote.u or 0, e.u or 0)
		SG.freshStart = false
	elseif e and (remote.u or 0) <= (e.u or 0) then
		return false
	end
	remote.seen = SG.now()
	SG.db.players[SG.myName] = remote
	SG.me()
	if SG.recovering then
		SG.print("Restored your numbers from the guild.")
		SG.recovering = false
	end
	return true
end

-- My first name when my full name has a surname ("Lih" for "Lih Zaddi"), else nil.
function SG.myFirstName()
	local first = SG.myName and SG.myName:match("^%S+")
	return first ~= SG.myName and first or nil
end

-- Merge numbers kept under my first name (before 0.14) into my full-name entry. Each
-- field takes the higher value, so merging the same copy again changes nothing.
-- Returns true if my numbers went up.
function SG.mergeLegacy(old)
	local e = SG.me()
	SG.rollWeek(old)
	local changed = false
	local function up(k, v)
		if (v or 0) > (e[k] or 0) then
			e[k] = v
			changed = true
		end
	end
	up("total", old.total)
	up("assists", old.assists)
	if old.weekId == e.weekId then
		up("week", old.week)
		up("wa", old.wa)
	end
	if old.prevWeekId and old.prevWeekId == e.weekId - 7 then
		if e.prevWeekId ~= old.prevWeekId then
			e.prevWeek, e.prevWeekId = 0, old.prevWeekId
		end
		up("prevWeek", old.prevWeek)
	end
	if (old.lastKill or 0) > (e.lastKill or 0) then
		e.lastKill, e.lastVictim = old.lastKill, old.lastVictim
	end
	if changed then
		e.u = math.max(SG.now(), e.u or 0)
		SG.freshStart = false -- my own copy is complete; don't add the guild's on top
		SG.seal(e)
	end
	return changed
end

-- My own numbers are never lower than my signed kill records in the company ledger.
function SG.recountOwn()
	local first = SG.myFirstName()
	local weekStart = SG.now() + secondsUntilReset() - 7 * 86400
	local c = { total = 0, week = 0, assists = 0, wa = 0, weekId = SG.weekId(), lastKill = 0 }
	for _, k in pairs(SG.db.kills or {}) do
		if k.killer == SG.myName or (first and k.killer == first) then
			c.total = c.total + 1
			if k.t >= weekStart then
				c.week = c.week + 1
			end
			if k.t > c.lastKill then
				c.lastKill, c.lastVictim = k.t, k.victim
			end
		end
	end
	if c.total > 0 then
		return SG.mergeLegacy(c)
	end
	return false
end

-- Test kills never touch your numbers; their rows vanish on the next reload.
local function clearTestKills()
	local list = SG.db.recent[SG.myName]
	if list then
		for i = #list, 1, -1 do
			if list[i].test then
				table.remove(list, i)
			end
		end
	end
end

local function prune()
	local cutoff = SG.now() - PRUNE_DAYS * 86400
	for name, e in pairs(SG.db.players) do
		if name ~= SG.myName and (e.seen or 0) < cutoff and (e.total or 0) == 0 then
			SG.db.players[name] = nil
		end
	end
end

function SG.recordKill(info)
	local e = SG.me()
	local t = SG.now()
	if info.test then
		-- shown in the popup and My kills only
	elseif info.assist then
		e.assists = (e.assists or 0) + 1
		e.wa = (e.wa or 0) + 1
		e.u = t
	else
		local before = SG.jobTitle(SG.myName, e.total)
		local after = SG.jobTitle(SG.myName, (e.total or 0) + 1)
		if after ~= before then
			info.promoted = after
		end
		e.total = (e.total or 0) + 1
		e.week = (e.week or 0) + 1
		e.lastKill = t
		e.lastVictim = info.victim
		e.u = t
	end
	SG.seal(e)

	local list = SG.db.recent[SG.myName] or {}
	SG.db.recent[SG.myName] = list
	table.insert(list, 1, { name = info.victim, realm = info.realm, zone = info.zone, t = t, assist = info.assist or nil, test = info.test or nil })
	while #list > RECENT_MAX do
		table.remove(list)
	end

	if not info.test and not info.assist then
		ns.Ledger.Record(info.victim, info.realm, info.zone)
	end
	ns.UI.Toast(e, info)
	ns.UI.Refresh()
	if not info.test then
		ns.Sync.Queue()
	end
end

---------------------------------------------------------------------------
-- Kill detection: PARTY_KILL(attackerGUID, targetGUID)
---------------------------------------------------------------------------

local GROUP_UNITS = {}
for i = 1, 4 do
	GROUP_UNITS[#GROUP_UNITS + 1] = "party" .. i
	GROUP_UNITS[#GROUP_UNITS + 1] = "partypet" .. i
end
for i = 1, 40 do
	GROUP_UNITS[#GROUP_UNITS + 1] = "raid" .. i
	GROUP_UNITS[#GROUP_UNITS + 1] = "raidpet" .. i
end

local recentTargets = {}
local pending = {}

-- What this session has seen, for /gnomes status and /gnomes killlog.
SG.diag = { events = 0, mine = 0, msgs = 0, peers = {}, killlog = {} }

-- Kill recorder: the last 20 kill-related signals, so we can see what the game sends.
local function logKill(fmt, ...)
	local ok, line = pcall(string.format, fmt, ...)
	local log = SG.diag.killlog
	log[#log + 1] = date("%H:%M:%S") .. "  " .. (ok and line or fmt)
	while #log > 20 do
		table.remove(log, 1)
	end
end

local function guidOf(unit)
	local ok, g = call(UnitGUID, unit)
	return ok and str(g) or nil
end

local function attackerKind(attacker)
	SG.myGUID = SG.myGUID or guidOf("player")
	if attacker == SG.myGUID then
		return "me"
	end
	if attacker == guidOf("pet") then
		return "pet"
	end
	local ok, grouped = call(IsInGroup)
	if not (ok and grouped == true) then
		return nil
	end
	for _, unit in ipairs(GROUP_UNITS) do
		if guidOf(unit) == attacker then
			return "group"
		end
	end
	return nil
end

-- World PvP only: skip battlegrounds and arenas.
local function inWorld()
	local ok, _, kind = call(IsInInstance)
	kind = ok and str(kind)
	return not (kind == "pvp" or kind == "arena")
end

local function zoneName()
	local ok, z = call(GetZoneText)
	return ok and str(z) or nil
end

-- Returns true when resolved (gnome or not), false when the race is still unreadable.
local function resolve(p)
	local ok, _, _, _, race, _, name, realm = call(GetPlayerInfoByGUID, p.target)
	race = ok and str(race)
	if not race then
		return false
	end
	name = str(name)
	logKill("party kill by %s: %s (%s)", p.kind, tostring(name), race)
	if p.kind ~= "group" then
		SG.diag.last = { t = SG.now(), name = name or "?", race = race, counted = race == "Gnome" }
	end
	if race == "Gnome" then
		SG.recordKill({ victim = name, realm = str(realm), zone = p.zone, assist = p.kind == "group" })
	end
	-- Recall Notices can name any player, gnome or not.
	ns.Bounty.OnKill(p.target, name, str(realm), p.zone, p.kind)
	return true
end

local function resolvePending()
	if #pending == 0 then
		return
	end
	local t = SG.now()
	for i = #pending, 1, -1 do
		local p = pending[i]
		if resolve(p) or t - p.t > PENDING_TTL then
			table.remove(pending, i)
		end
	end
end

local function onPartyKill(attacker, target)
	SG.diag.events = SG.diag.events + 1
	if SG.secret(attacker) or SG.secret(target) then
		SG.diag.secret = (SG.diag.secret or 0) + 1
		logKill("party kill: unreadable (combat restriction)")
		return
	end
	attacker, target = str(attacker), str(target)
	if not attacker or not target or not target:match("^Player%-") then
		return
	end
	local t = SG.now()
	if recentTargets[target] and t - recentTargets[target] < DEDUPE_SECONDS then
		return
	end
	local kind = attackerKind(attacker)
	if not kind or not inWorld() then
		return
	end
	if kind ~= "group" then
		SG.diag.mine = SG.diag.mine + 1
	end
	recentTargets[target] = t
	local p = { target = target, kind = kind, zone = zoneName(), t = t }
	if not resolve(p) then
		pending[#pending + 1] = p
	end
end

---------------------------------------------------------------------------
-- Helped kills. The game only reports kills by you, your pet or your group. A gnome
-- that dies near you while you're awarded honor for it counts as an assist, whoever
-- landed the blow: honor is the game's own proof that you took part.
---------------------------------------------------------------------------

local HELP_WINDOW = 6  -- seconds allowed between the death and your honor
local SETTLE = 1.5     -- wait so a party kill (killing blow, group assist) is credited first
local TARGET_MEMORY = 30
local deaths = {}      -- recent player deaths near you
local lastHonor = 0
local lastGnomeTarget  -- { name, guid, t }: fallback when the death is unreadable
local helped = {}      -- guid or name -> time credited

-- Already credited as a killing blow or group assist?
local function claimed(guid)
	return guid ~= nil and recentTargets[guid] ~= nil and SG.now() - recentTargets[guid] < 60
end

local function matchHelped()
	if not inWorld() then
		return
	end
	local now = SG.now()
	if now - lastHonor > HELP_WINDOW + SETTLE then
		return
	end
	for i = #deaths, 1, -1 do
		local d = deaths[i]
		if now - d.t > 60 then
			table.remove(deaths, i)
		elseif not d.done and math.abs(lastHonor - d.t) <= HELP_WINDOW then
			local name, guid, race = d.name, d.guid, d.race
			if d.secret then
				-- Unreadable death: credit the gnome you're targeting, but only if it's dead.
				local g = lastGnomeTarget
				local okD, dead = call(UnitIsDeadOrGhost, "target")
				if g and now - g.t < TARGET_MEMORY and guidOf("target") == g.guid
					and okD and not SG.secret(dead) and dead == true then
					name, guid, race = g.name, g.guid, "Gnome"
				end
			end
			if race == "Gnome" and name then
				d.done = true
				local key = guid or name
				if claimed(guid) then
					logKill("helped: %s already credited", name)
				elseif not (helped[key] and now - helped[key] < 60) then
					helped[key] = now
					if guid then
						recentTargets[guid] = now
					end
					logKill("helped: assist credited for %s%s", name, d.secret and " (from your target)" or "")
					SG.recordKill({ victim = name, zone = zoneName(), assist = true })
				end
			end
		end
	end
end

local function onUnitDied(guid)
	local now = SG.now()
	for i = #deaths, 1, -1 do
		if now - deaths[i].t > 60 then
			table.remove(deaths, i)
		end
	end
	if SG.secret(guid) then
		deaths[#deaths + 1] = { t = now, secret = true }
		logKill("death: unreadable unit (combat restriction)")
	else
		guid = str(guid)
		if not guid or not guid:match("^Player%-") then
			return
		end
		local ok, _, _, _, race, _, name = call(GetPlayerInfoByGUID, guid)
		race, name = ok and str(race) or nil, ok and str(name) or nil
		deaths[#deaths + 1] = { t = now, guid = guid, race = race, name = name }
		logKill("death: %s (%s)", tostring(name), tostring(race))
	end
	C_Timer.After(SETTLE, matchHelped)
end

local function onHonor(event, text)
	text = str(text)
	-- System and currency messages are only honor if they say so.
	if (event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_CURRENCY") and not (text and text:lower():find("honor", 1, true)) then
		return
	end
	lastHonor = SG.now()
	logKill("honor (%s): %s", event, text and text:sub(1, 70) or "")
	C_Timer.After(SETTLE, matchHelped)
end

-- Remember the last enemy gnome you targeted, for deaths the game won't name.
local function onTargetChanged()
	local okP, isPlayer = call(UnitIsPlayer, "target")
	if not okP or SG.secret(isPlayer) or isPlayer ~= true then
		return
	end
	local okE, enemy = call(UnitIsEnemy, "player", "target")
	if not okE or SG.secret(enemy) or enemy ~= true then
		return
	end
	local okR, _, race = call(UnitRace, "target")
	if not okR or str(race) ~= "Gnome" then
		return
	end
	local name = SG.unitFullName("target")
	if name then
		lastGnomeTarget = { name = name, guid = guidOf("target"), t = SG.now() }
	end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

function SG.ranked(mode)
	local cur = SG.weekId()
	local rows = {}
	for name, e in pairs(SG.db.players) do
		local kills, assists
		if mode == "week" then
			kills, assists = SG.weekCounts(e, cur)
		else
			kills, assists = e.total or 0, e.assists or 0
		end
		if kills > 0 or assists > 0 or name == SG.myName then
			rows[#rows + 1] = { name = name, kills = kills, assists = assists, e = e }
		end
	end
	table.sort(rows, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.assists ~= b.assists then
			return a.assists > b.assists
		end
		return a.name < b.name
	end)
	return rows
end

function SG.lastWeekWinner()
	local cur, best, bestN = SG.weekId(), nil, 0
	for name, e in pairs(SG.db.players) do
		local n = SG.lastWeekCount(e, cur)
		if n > bestN or (n == bestN and n > 0 and best and name < best) then
			best, bestN = name, n
		end
	end
	return best, bestN
end

---------------------------------------------------------------------------
-- Job titles (by lifetime gnomes). CEO belongs to the guild master and can't be earned.
---------------------------------------------------------------------------

SG.TITLES = {
	{ 0, "Unpaid Intern" },
	{ 1, "Lab Assistant" },
	{ 10, "Field Harvester" },
	{ 25, "Pharmacist" },
	{ 50, "Senior Chemist" },
	{ 100, "Head of R&D" },
	{ 250, "Chief Medical Officer" },
}

-- Returns title, next title (or nil), gnomes still needed for it.
function SG.jobTitle(name, total)
	if name and SG.guildMaster and SG.sameName(name, SG.guildMaster) then
		return "CEO"
	end
	total = total or 0
	local title, nextTitle, need = SG.TITLES[1][2], nil, nil
	for i, t in ipairs(SG.TITLES) do
		if total >= t[1] then
			title = t[2]
			local n = SG.TITLES[i + 1]
			nextTitle, need = n and n[2], n and (n[1] - total)
		end
	end
	return title, nextTitle, need
end

-- Last week's winner is this week's Employee of the Week.
function SG.isEmployeeOfWeek(name)
	local winner = SG.lastWeekWinner()
	return winner ~= nil and winner == name
end

-- Guild roster: rank index per member (0 = guild master). Used for CEO and officer checks.
local function scanRoster()
	local ok, n = call(GetNumGuildMembers)
	n = ok and num(n)
	if not n or n == 0 then
		return
	end
	local roster = {}
	for i = 1, n do
		local ok2, name, _, rankIndex = call(GetGuildRosterInfo, i)
		local full = ok2 and SG.fullName(name)
		rankIndex = ok2 and num(rankIndex)
		if full and rankIndex then
			roster[full] = rankIndex
			if rankIndex == 0 then
				SG.guildMaster = full
			end
		end
	end
	SG.roster = roster
	ns.Bounty.OnRoster()
end

-- Shown once at login, after guildmates' numbers have had time to sync:
-- this week's top 3, your own place if you're outside it, and the Employee of the Week.
function SG.loginStandings()
	if SG.db.settings.loginStandings == false then
		return
	end
	local rows = SG.ranked("week")
	local top, myRank, mine = {}, nil, nil
	for i, r in ipairs(rows) do
		if r.kills > 0 and #top < 3 then
			top[#top + 1] = ("%d. %s %d"):format(i, SG.shortName(r.name), r.kills)
		end
		if r.name == SG.myName then
			myRank, mine = i, r.kills
		end
	end
	local gold = "|cffffd14d"
	if #top == 0 then
		SG.print("No gnomes harvested yet this week. First one sets the pace.")
	else
		SG.print("This week's top harvesters: " .. gold .. table.concat(top, "  ·  ") .. "|r")
		if myRank and myRank > 3 and mine > 0 then
			print(("  You: #%d with %d."):format(myRank, mine))
		end
	end
	local champ, n = SG.lastWeekWinner()
	if champ then
		print(("  Employee of the Week: %s%s|r (%d last week)"):format(gold, SG.shortName(champ), n))
	end
end

local function printBoard()
	local rows = SG.ranked("week")
	SG.print("This week:")
	local shown = 0
	for i, r in ipairs(rows) do
		if i > 10 or r.kills == 0 then
			break
		end
		print(("  %d. %s  %d"):format(i, SG.shortName(r.name), r.kills))
		shown = shown + 1
	end
	if shown == 0 then
		print("  No gnomes yet this week.")
	end
end

local HELP = {
	"/gnomes  open the Production Report",
	"/gnomes stats  your job title and numbers",
	"/gnomes status  is it working? kills seen, guildmates heard, version",
	"/gnomes board  this week's top 10 in chat",
	"/gnomes standings  the login message: top 3 and Employee of the Week",
	"/gnomes spies  list suspected corporate spies",
	"/gnomes spy <name> [reward]  officers: report a corporate spy (or target the player)",
	"/gnomes spy cancel <name>  officers: withdraw your report",
	"/gnomes toast  turn the kill popup on or off",
	"/gnomes minimap  hide or show the minimap button",
	"/gnomes gank  gank mode: call out gnomes you see and list them; click a name to target it",
	"/gnomes settings  window size, background opacity and switches",
	"/gnomes help  this list, and the Commands view in the window",
	"/gnomes crest  show the guild crest large, with its colours (for screenshots)",
	"/gnomes crest on | off  try the live guild crest instead of the logo file, or switch back",
	"/gnomes tipdebug  print what the tooltip hook sees for the next 5 players you hover",
	"/gnomes killlog  the last 20 kill signals (deaths near you, honor, party kills)",
	"/gnomes version  your version, and whether a newer one is out",
	"/gnomes sync  ask the guild for fresh numbers",
	"/gnomes test  show a fake kill (doesn't change your numbers)",
	"/gnomes test promo  show a fake promotion",
	"/gnomes test gank  show a fake spotted gnome",
	"/gnomes check  self-test the anti-tamper signing",
}

SLASH_SMOKINGGNOMES1 = "/gnomes"
SLASH_SMOKINGGNOMES2 = "/sg"
SlashCmdList.SMOKINGGNOMES = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" then
		ns.UI.Toggle()
	elseif cmd == "stats" then
		local e = SG.me()
		local title, nextTitle, need = SG.jobTitle(SG.myName, e.total)
		SG.print(("%s. %d this week, %d lifetime, %d assists. Last harvest %s."):format(title, e.week, e.total, e.assists or 0, SG.ago(e.lastKill)))
		if nextTitle then
			SG.print(("%d more gnome%s to %s."):format(need, need == 1 and "" or "s", nextTitle))
		end
	elseif cmd == "board" then
		printBoard()
	elseif cmd == "standings" then
		local was = SG.db.settings.loginStandings
		SG.db.settings.loginStandings = true
		SG.loginStandings()
		SG.db.settings.loginStandings = was
	elseif cmd == "toast" then
		SG.db.settings.toast = not SG.db.settings.toast
		SG.print("Kill popup " .. (SG.db.settings.toast and "on." or "off."))
	elseif cmd == "crest" then
		local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
		if arg == "off" or arg == "on" then
			SG.db.settings.crest = arg == "on"
			ns.UI.RefreshCrests()
			SG.print(arg == "off" and "Using the logo file instead of the live guild crest."
				or "Using the live guild crest (falls back to the logo file if the game doesn't provide it).")
		else
			ns.UI.ShowCrestSheet()
		end
	elseif cmd == "status" then
		local d = SG.diag
		SG.print(("Version %s. You are %s."):format(SG.RELEASE, tostring(SG.myName)))
		-- Where the name comes from, in case a surname goes missing.
		local okN, n1, n2 = call(UnitName, "player")
		local okI, _, _, _, _, _, gName = call(GetPlayerInfoByGUID, SG.myGUID or "")
		print(("  Name sources: UnitName = %s / %s, by GUID = %s"):format(
			tostring(okN and str(n1)), tostring(okN and str(n2)), tostring(okI and str(gName))))
		-- Guildmates running the addon, heard from this session.
		local peers = {}
		for name in pairs(d.peers) do
			peers[#peers + 1] = SG.shortName(name)
		end
		table.sort(peers)
		if #peers > 0 then
			print(("  Guildmates with the addon heard this session: %d (%s)"):format(#peers, table.concat(peers, ", ")))
		else
			print("  No guildmates with the addon heard from this session. Only members who install it appear on the board.")
		end
		local known = 0
		for name, e in pairs(SG.db.players) do
			if name ~= SG.myName and ((e.total or 0) > 0 or (e.assists or 0) > 0) then
				known = known + 1
			end
		end
		print(("  Guildmates on the board: %d"):format(known))
		-- Kill detection.
		print(("  Player kills seen this session: %d by you or your pet, %d kill events in total."):format(d.mine, d.events))
		if d.last then
			print(("  Last: %s (%s), %s, %s."):format(d.last.name, d.last.race, SG.ago(d.last.t),
				d.last.counted and "counted" or "not a gnome, not counted"))
		elseif d.events == 0 then
			print("  No kill events yet. Kill any enemy player in the open world and run this again: the count should go up.")
		end
		if (d.secret or 0) > 0 then
			print(("  %d kill event(s) were unreadable (combat restriction)."):format(d.secret))
		end
	elseif cmd == "killlog" then
		local log = SG.diag.killlog
		if #log == 0 then
			SG.print("Kill log is empty. It records deaths near you, honor awards and party kills from this session.")
		else
			SG.print(("Last %d kill signals this session:"):format(#log))
			for _, line in ipairs(log) do
				print("  " .. line)
			end
		end
	elseif cmd == "tipdebug" then
		ns.UI.TipDebug()
	elseif cmd == "version" then
		SG.print(("You have %s.%s"):format(SG.RELEASE,
			SG.latestRelease and SG.newer(SG.latestRelease, SG.RELEASE) and (" " .. SG.latestRelease .. " is out.") or ""))
	elseif cmd == "sync" then
		ns.Sync.Hello()
		SG.print("Asked the guild for numbers.")
	elseif cmd == "recall" or cmd == "spy" then
		-- /gnomes recall <name> [reward]   /gnomes recall cancel <name>   (name defaults to your target)
		local rest = (msg or ""):match("^%s*%S+%s*(.*)$") or ""
		local cancel = rest:lower():match("^cancel%s") ~= nil or rest:lower() == "cancel"
		if cancel then
			rest = rest:gsub("^%S+%s*", "")
		end
		-- Name: one word, or two if the second is capitalised like a surname ("Legs Dogman").
		-- The reward is the rest, so it should start with a number or a lower-case word.
		local name, reward = rest:match("^(%S+)%s*(.*)$")
		if name and reward then
			local surname, after = reward:match("^(%u[%l']+)%s*(.*)$")
			if surname then
				name, reward = name .. " " .. surname, after
			end
		end
		if not name then
			local okT, isPlayer = call(UnitIsPlayer, "target")
			if okT and not SG.secret(isPlayer) and isPlayer == true then
				name = SG.unitFullName("target")
			end
		end
		if not name then
			SG.print("Usage: /gnomes spy <name> [reward], or target the player first.")
			return
		end
		local ok, err
		if cancel then
			ok, err = ns.Bounty.Cancel(name)
		else
			ok, err = ns.Bounty.Post(name, reward)
		end
		if not ok then
			SG.print(err)
		elseif cancel then
			SG.print("Spy report withdrawn.")
		end
	elseif cmd == "recalls" or cmd == "spies" then
		local list = ns.Bounty.List()
		local shown = 0
		for _, row in ipairs(list) do
			if row.state == "open" then
				print(("  %s  ·  %s  ·  posted by %s"):format(row.b.target, row.b.reward, SG.shortName(row.b.poster)))
				shown = shown + 1
			end
		end
		SG.print(shown == 0 and "No corporate spies at large." or (shown .. " corporate spy report(s) open."))
	elseif cmd == "check" then
		-- Self-test of the signing: a round trip must pass, any edit must fail.
		local sample = { total = 12, week = 3, weekId = SG.weekId(), assists = 4, wa = 1, lastKill = SG.now(), u = SG.now(), class = "PRIEST", lastVictim = "Fizzwick" }
		local raw = SG.encode(sample)
		local sig = SG.sign(SG.myName, raw)
		local roundTrip = SG.decode(SG.myName, raw, sig)
		local edited = SG.decode(SG.myName, raw:gsub("^12|", "99|"), sig)
		local otherName = SG.decode("Someone-Else", raw, sig)
		local own = SG.db.players[SG.myName]
		local ownOk = own and SG.decode(SG.myName, own.raw, own.sig) ~= nil
		local recallsOk = ns.Bounty.SelfTest()
		local pass = roundTrip and roundTrip.total == 12 and roundTrip.lastVictim == "Fizzwick" and not edited and not otherName and ownOk and recallsOk
		SG.print(pass and "Check passed: signing works and your saved numbers are intact."
			or ("Check FAILED (roundtrip=%s edited=%s othername=%s own=%s recalls=%s)"):format(tostring(roundTrip ~= nil), tostring(edited ~= nil), tostring(otherName ~= nil), tostring(ownOk), tostring(recallsOk)))
		local officer = SG.IsOfficer(SG.myName)
		SG.print("Corporate spies: you " .. (officer and "can" or officer == false and "can't" or "may (roster still loading)") .. " report them.")
	elseif cmd == "test" and (msg or ""):lower():find("gank", 1, true) then
		if not SG.db.settings.gank then
			SG.print("Turn gank mode on first (/gnomes gank) to see the panel.")
		end
		ns.Gank.Spot("Testgnome", "MAGE", 51, nil)
	elseif cmd == "test" then
		local info = { victim = "Test Gnome", zone = zoneName(), test = true }
		if (msg or ""):lower():find("promo", 1, true) then
			local _, nextTitle = SG.jobTitle(SG.myName, SG.me().total)
			info.promoted = nextTitle or "Chief Medical Officer"
		end
		SG.recordKill(info)
	elseif cmd == "minimap" then
		ns.UI.ToggleMinimap()
	elseif cmd == "gank" then
		ns.Gank.Toggle()
	elseif cmd == "settings" or cmd == "options" or cmd == "config" then
		ns.UI.ShowView("settings", true)
	else
		-- help, ?, or anything unknown: the full list in chat, plus the Commands view.
		if cmd ~= "help" and cmd ~= "?" then
			SG.print(("Unknown command \"%s\". Here's the list:"):format(cmd))
		end
		for _, line in ipairs(HELP) do
			print(line)
		end
		ns.UI.ShowHelp(true)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PARTY_KILL")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Helped kills: any death near you plus the honor you get for it. Some of these may
-- not exist on every client, so they're registered safely.
for _, e in ipairs({ "ADDON_RESTRICTION_STATE_CHANGED", "UNIT_DIED", "CHAT_MSG_COMBAT_HONOR_GAIN",
	"CHAT_MSG_CURRENCY", "CHAT_MSG_SYSTEM", "PLAYER_PVP_KILLS_CHANGED" }) do
	pcall(f.RegisterEvent, f, e)
end
local HONOR_EVENTS = { CHAT_MSG_COMBAT_HONOR_GAIN = true, CHAT_MSG_CURRENCY = true,
	CHAT_MSG_SYSTEM = true, PLAYER_PVP_KILLS_CHANGED = true }

f:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			initDB()
		end
	elseif event == "PLAYER_LOGIN" then
		SG.myName = SG.unitFullName("player")
		SG.myGUID = guidOf("player")
		local _, classFile = UnitClass("player")
		SG.myClass = str(classFile)
		-- Before 0.14 players were keyed by first name only. My numbers saved under the
		-- first name are merged into the full-name entry and re-signed under it.
		local first = SG.myFirstName()
		local old = first and SG.db.players[first]
		local legacy = old and SG.decode(first, old.raw, old.sig)
		if first then
			SG.db.recent[SG.myName] = SG.db.recent[SG.myName] or SG.db.recent[first]
			SG.db.recent[first] = nil
			SG.db.players[first] = nil
		end
		verifyStore()
		local own = SG.db.players[SG.myName]
		SG.freshStart = not own or (own.u or 0) == 0
		clearTestKills()
		prune()
		SG.me()
		SG.prevOnline = SG.db.lastOnline -- tells guildmates which kills I missed
		SG.db.lastOnline = SG.now()
		ns.Ledger.Load()
		if legacy then
			SG.mergeLegacy(legacy)
		end
		SG.recountOwn()
		ns.Bounty.Load()
		scanRoster()
		call(C_GuildInfo and C_GuildInfo.GuildRoster) -- ask for a roster update (CEO and officers)
		ns.UI.Init()
		ns.Gank.Init()
		ns.Sync.Start()
		C_Timer.NewTicker(30, function()
			SG.db.lastOnline = SG.now()
			resolvePending()
			ns.UI.Refresh()
		end)
	elseif event == "PARTY_KILL" then
		if SG.db and SG.myName then
			onPartyKill(...)
		end
	elseif event == "UNIT_DIED" then
		if SG.db and SG.myName then
			onUnitDied(...)
		end
	elseif HONOR_EVENTS[event] then
		if SG.db and SG.myName then
			onHonor(event, event ~= "PLAYER_PVP_KILLS_CHANGED" and (...) or nil)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Standings only on a real login, not on /reload or zoning.
		local isInitialLogin = ...
		if isInitialLogin == true and SG.db and SG.myName then
			C_Timer.After(35, SG.loginStandings)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		if SG.db and SG.myName then
			onTargetChanged()
		end
	elseif event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
		if SG.db and SG.myName then
			resolvePending()
		end
	elseif event == "GUILD_ROSTER_UPDATE" then
		if SG.db and SG.myName then
			scanRoster()
		end
	elseif event == "CHAT_MSG_ADDON" then
		if SG.db and SG.myName then
			ns.Sync.OnMessage(...)
		end
	end
end)
