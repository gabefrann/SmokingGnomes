-- Smoking Gnomes Inc.: guild sync with relay.
--
-- Messages (GUILD addon channel; every record is signed, see SG.sign in Core.lua):
--   H|version                                   "I just logged in"
--   R|version|Name-Realm|<11 fields>|signature  one player's numbers
--   B|version|<8 fields>|signature              a Recall Notice (bounty), see Bounty.lua
--   C|version|<6 fields>|signature              a claim on a Recall Notice
--   S|version|name|class|level|map              a gnome spotted in gank mode (not signed:
--                                               display only, shown to members on that map)
-- The owner of a record sends it when it changes. Anyone may relay any record, so news
-- made while you were offline still reaches you through whoever is online. A record is
-- only replaced by a newer, valid one.

local _, ns = ...
local SG = ns.SG

local Sync = {}
ns.Sync = Sync

local OWN_THROTTLE = 10      -- my own numbers: at most one send every 10 s
local PACE = 1.2             -- gap between queued messages (the client allows ~1/s sustained)
local RETRY = 5              -- wait while chat messaging is locked down or throttled
local MAX_TRIES = 24         -- then drop the message; the next event queues it again
local HEARD_WINDOW = 120     -- skip relaying a version someone else sent this recently
local RELAY_DELAY = { 3, 10 } -- random wait before relaying, so one player usually goes first
local RELAY_MAX_AGE = 60 * 86400
local FRESH_HOLD = 45        -- after a blank start, wait this long for the guild's copy of me
local BURST = 3              -- kills allowed in one update regardless of time passed...
local KILL_SECONDS = 30      -- ...plus one per 30 s since the previous update
local MAX_STEP = 100         -- and never more than this in one update

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(SG.PREFIX)
end

---------------------------------------------------------------------------
-- Records the outbox can send. kind = "entry" | "bounty" | "claim"
---------------------------------------------------------------------------

local function entryMessage(name)
	local e = SG.db.players[name]
	if not e or not e.raw or not e.sig then
		return nil
	end
	return ("R|%d|%s|%s|%s"):format(SG.VERSION, name, e.raw, e.sig)
end

local function messageFor(item)
	if item.kind == "hello" then
		return "H|" .. SG.VERSION .. "|" .. (SG.prevOnline or 0) .. "|" .. SG.RELEASE
	elseif item.kind == "version" then
		return "V|" .. SG.VERSION .. "|" .. SG.RELEASE
	elseif item.kind == "entry" then
		return entryMessage(item.key)
	elseif item.kind == "bounty" then
		return ns.Bounty.Message(item.key)
	elseif item.kind == "claim" then
		return ns.Bounty.ClaimMessage(item.key)
	elseif item.kind == "kill" then
		return ns.Ledger.Message(item.key)
	elseif item.kind == "spot" then
		return ns.Gank.SpotMessage(item.key)
	end
end

-- The version number of a record: newer versions replace older ones everywhere.
local function versionOf(kind, key)
	if kind == "entry" then
		local e = SG.db.players[key]
		return e and e.u or 0
	elseif kind == "kill" then
		return SG.db.kills[key] and 1 or 0 -- kill records never change
	elseif kind == "spot" then
		return 1 -- a guildmate who just shared the same gnome makes mine unnecessary
	end
	return ns.Bounty.Version(kind, key)
end

---------------------------------------------------------------------------
-- Sending: one paced outbox for everything.
---------------------------------------------------------------------------

local outbox, queuedKeys = {}, {}
local pumping = false
local heard = {}             -- "kind:key" -> { v = version, t = GetTime() } last version seen on the wire
local ownScheduled, lastOwn = false, -OWN_THROTTLE
local relayScheduled = false

local function lockedDown()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		return ok and (SG.secret(locked) or locked == true)
	end
	return false
end

local function inGuild()
	local ok, g = pcall(IsInGuild)
	return ok and g == true
end

-- true = sent, false = try again later
local function send(msg)
	if lockedDown() then
		return false
	end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, SG.PREFIX, msg, "GUILD")
	if not ok or result == false then
		return false
	end
	return SG.secret(result) or type(result) ~= "number" or result == 0
end

function Sync.MarkHeard(kind, key, version)
	local id = kind .. ":" .. key
	local h = heard[id]
	if not h or version >= h.v then
		heard[id] = { v = version, t = GetTime() }
	end
end

local function recentlyHeard(kind, key)
	local h = heard[kind .. ":" .. key]
	return h and h.v >= versionOf(kind, key) and GetTime() - h.t < HEARD_WINDOW
end

local function pump()
	if pumping then
		return
	end
	local item = outbox[1]
	if not item then
		return
	end
	local msg
	if item.force or item.kind == "hello" or not recentlyHeard(item.kind, item.key) then
		msg = messageFor(item)
	end
	if not msg or not inGuild() then
		table.remove(outbox, 1)
		queuedKeys[item.id] = nil
		return pump()
	end

	pumping = true
	local sent = send(msg)
	if sent or item.tries >= MAX_TRIES then
		table.remove(outbox, 1)
		queuedKeys[item.id] = nil
		if sent and item.key then
			Sync.MarkHeard(item.kind, item.key, versionOf(item.kind, item.key))
		end
		if sent and item.own then
			lastOwn = GetTime()
		end
	else
		item.tries = item.tries + 1
	end
	C_Timer.After(sent and PACE or RETRY, function()
		pumping = false
		pump()
	end)
end

-- force: send even if someone else just sent the same version (used for my own records)
function Sync.Enqueue(kind, key, front, force)
	local id = kind .. ":" .. (key or "")
	if queuedKeys[id] then
		return
	end
	queuedKeys[id] = true
	local item = { id = id, kind = kind, key = key, force = force, own = kind == "entry" and key == SG.myName, tries = 0 }
	if front then
		table.insert(outbox, 1, item)
	else
		outbox[#outbox + 1] = item
	end
	pump()
end

---------------------------------------------------------------------------
-- What gets sent and when
---------------------------------------------------------------------------

local function ownReady()
	local e = SG.db.players[SG.myName]
	-- Nothing to report yet, or still waiting for the guild's copy of me.
	return e and (e.u or 0) > 0 and not SG.freshStart
end

-- Send my own numbers soon (after a kill, a login, or someone saying hello).
function Sync.Queue(delay)
	if ownScheduled then
		return
	end
	ownScheduled = true
	local wait = math.max(delay or 0, lastOwn + OWN_THROTTLE - GetTime(), 0.1)
	C_Timer.After(wait, function()
		ownScheduled = false
		if ownReady() then
			Sync.Enqueue("entry", SG.myName, true, true)
		end
	end)
end

-- Relay everything I know: the player who just logged in first, then Recall Notices
-- and claims, then everyone else's numbers (most recently updated first), then the
-- company's gnome kills since `since`. Versions someone else just sent are skipped.
local function relayAll(first, since)
	if first and SG.db.players[first] then
		Sync.Enqueue("entry", first)
	end
	for _, rec in ipairs(ns.Bounty.RelayList()) do
		Sync.Enqueue(rec[1], rec[2])
	end
	local kills = ns.Ledger.RelayList(since)
	local list = {}
	local cutoff = SG.now() - RELAY_MAX_AGE
	for name, e in pairs(SG.db.players) do
		if name ~= SG.myName and name ~= first and ((e.total or 0) > 0 or (e.assists or 0) > 0) and (e.u or 0) > cutoff then
			list[#list + 1] = name
		end
	end
	table.sort(list, function(a, b)
		return (SG.db.players[a].u or 0) > (SG.db.players[b].u or 0)
	end)
	for _, name in ipairs(list) do
		Sync.Enqueue("entry", name)
	end
	for _, rec in ipairs(kills) do
		Sync.Enqueue(rec[1], rec[2])
	end
end

-- Several logins close together merge into one relay pass covering the oldest `since`.
local pendingFirst, pendingSince
local function scheduleRelay(first, since)
	pendingFirst = pendingFirst or first
	if not since then
		pendingSince = 0 -- unknown last login: use the default window
	elseif pendingSince ~= 0 then
		pendingSince = math.min(pendingSince or since, since)
	end
	if relayScheduled then
		return
	end
	relayScheduled = true
	C_Timer.After(math.random(RELAY_DELAY[1], RELAY_DELAY[2]), function()
		relayScheduled = false
		local f, s = pendingFirst, pendingSince
		pendingFirst, pendingSince = nil, nil
		relayAll(f, s ~= 0 and s or nil)
	end)
end

-- H|version|lastOnline: lets others send only the kills I missed.
function Sync.Hello()
	Sync.Enqueue("hello", nil, false, true)
end

function Sync.Start()
	C_Timer.After(8, function()
		Sync.Hello()
		Sync.Queue(10)
		scheduleRelay(nil, SG.now() - 86400) -- share the last day's kills I carry
	end)
	if SG.freshStart then
		C_Timer.After(8 + FRESH_HOLD, function()
			if SG.freshStart then
				SG.freshStart = false
				Sync.Queue()
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Receiving player numbers
---------------------------------------------------------------------------

local function flag(name)
	local e = SG.db.players[name]
	if e then
		e.bad = (e.bad or 0) + 1
	end
end

-- Is `new` a believable successor to `old`?
local function plausible(old, new)
	if new.week > new.total or new.wa > new.assists then
		return false
	end
	-- At most 1.25 points (5 quarters) per gnome.
	if (new.wp or 0) > 5 * new.week or (new.pp or 0) > 5 * (new.prevWeek or 0) then
		return false
	end
	-- Alliance kills include the gnomes; this week's can't exceed the lifetime count.
	if (new.ak or 0) < new.total or (new.aw or 0) < new.week or (new.aw or 0) > (new.ak or 0) then
		return false
	end
	if new.weekId > SG.weekId() + 7 or new.u > SG.now() + 600 then
		return false
	end
	if old then
		local elapsed = math.max(0, new.u - (old.u or 0))
		local allowed = math.min(MAX_STEP, BURST + math.floor(elapsed / KILL_SECONDS))
		if new.total - (old.total or 0) > allowed or new.assists - (old.assists or 0) > allowed
			or (new.ak or 0) - (old.ak or 0) > allowed then
			return false
		end
	end
	return true
end

local function ingest(name, raw, sig, firsthand)
	local new = SG.decode(name, raw, sig)
	if not new then
		flag(name)
		return
	end
	Sync.MarkHeard("entry", name, new.u)

	if name == SG.myName then
		if SG.adoptOwn(new) then
			Sync.Queue()
			ns.UI.Refresh()
		end
		return
	end

	-- My own numbers from before 0.14, kept under my first name by a guildmate.
	if name == SG.myFirstName() then
		new.raw, new.sig = nil, nil
		if SG.mergeLegacy(new) then
			Sync.Queue()
			ns.UI.Refresh()
		end
		return
	end

	local players = SG.db.players
	-- Before 0.14 entries used the first name only ("Lih"). Ignore such an entry when
	-- this player is already known under the full name ("Lih Zaddi").
	if not name:find(" ", 1, true) then
		for key in pairs(players) do
			if key:sub(1, #name + 1) == name .. " " then
				return
			end
		end
	end
	local old = players[name]
	if firsthand and old then
		old.seen = SG.now()
	end
	if old and new.u <= (old.u or 0) then
		return -- same or older news
	end
	if old and (new.total < (old.total or 0) or new.assists < (old.assists or 0)) then
		return -- numbers never go down; keep the higher copy
	end
	if not plausible(old, new) then
		flag(name)
		return
	end
	new.seen = firsthand and SG.now() or (old and old.seen)
	new.bad = old and old.bad
	players[name] = new
	-- The full-name entry replaces the same player's old first-name entry.
	local first = name:match("^%S+")
	if first and first ~= name and players[first] and first ~= SG.myName then
		players[first] = nil
	end
	ns.UI.Refresh()
end

-- Newest release seen in the guild; told to the player once per session.
local told = false
local function noteVersion(v)
	if type(v) ~= "string" or not v:match("^%d+%.%d+") then
		return
	end
	if SG.newer(v, SG.latestRelease or SG.RELEASE) then
		SG.latestRelease = v
	end
	if not told and SG.newer(SG.latestRelease or "", SG.RELEASE) then
		told = true
		SG.print(("Version %s is out (you have %s). Update in WowUp or CurseForge, then /reload."):format(SG.latestRelease, SG.RELEASE))
		ns.UI.Refresh()
	end
end

function Sync.OnMessage(prefix, text, channel, sender)
	if SG.secret(prefix) or SG.secret(text) or SG.secret(channel) or SG.secret(sender) then
		return
	end
	if prefix ~= SG.PREFIX or channel ~= "GUILD" or type(text) ~= "string" then
		return
	end
	sender = SG.fullName(sender)
	if not sender or sender == SG.myName then
		return
	end
	SG.diag.msgs = SG.diag.msgs + 1
	SG.diag.peers[sender] = SG.now()

	local p = { strsplit("|", text) }
	local kind = p[1]
	if kind == "H" or kind == "V" then
		local theirs = kind == "H" and p[4] or p[3]
		noteVersion(theirs)
		-- Tell someone on an older release (or one too old to say) that a newer one exists.
		if kind == "H" and (not theirs or SG.newer(SG.RELEASE, theirs)) then
			Sync.Enqueue("version", nil, false, true)
		end
	end
	if kind == "H" then
		local e = SG.db.players[sender]
		if e then
			e.seen = SG.now()
		end
		Sync.Queue(math.random(1, 4))
		local since = tonumber(p[3])
		scheduleRelay(sender, (since and since > 0) and since or nil)
	elseif kind == "R" and SG.FIELD_COUNTS[#p - 4] then
		-- Names may come without a realm: WoW Forever doesn't report one.
		local name = p[3]
		if not name or name == "" then
			return
		end
		local raw = table.concat(p, "|", 4, #p - 1)
		ingest(name, raw, p[#p], name == sender)
	elseif kind == "K" then
		ns.Ledger.Receive(table.concat(p, "|", 3, #p - 1), p[#p])
	elseif kind == "S" and #p == 6 then
		-- S|version|name|class|level|map: a gnome a guildmate just spotted (gank mode)
		Sync.MarkHeard("spot", p[3], 1)
		ns.Gank.Remote(sender, p[3], p[4], p[5], p[6])
	elseif kind == "B" or kind == "C" then
		-- fields sit between the version and the signature
		local raw = table.concat(p, "|", 3, #p - 1)
		if kind == "B" then
			ns.Bounty.Receive(raw, p[#p], sender)
		else
			ns.Bounty.ReceiveClaim(raw, p[#p], sender)
		end
	end
end
