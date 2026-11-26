-- Smoking Gnomes Inc.: Employee of the Week records and the weekly bonus.
--
-- One record per week naming that week's Employee of the Week, the bonus and whether
-- it was paid. (The Hall of Fame view that listed them is switched off for now; the
-- records are still kept, so it can come back with the full history.) Only the guild master and officers create or change records
-- (checked against the guild roster); everyone stores and relays them like the others.
--   W|version|week|winner|points|gnomes|prize|paid|by|paidBy|u|signature
-- week = SG.weekId() of the week that was won (the day number of the reset ending it).
--
-- Guild chat (visible to everyone, addon or not), once a week at most:
--   - the new Employee of the Week, posted by the officer whose addon records it,
--   - the prize being paid, posted by the officer who marks it paid.
-- Individual harvests are not posted: that was too much guild chat.

local _, ns = ...
local SG = ns.SG

local Hall = {}
ns.Hall = Hall

local START_WEEK = 20789        -- the week ending 2 Dec 2026 is the first in the Hall of Fame
local CHECK_DELAY = { 90, 150 } -- after login: wait for guildmates' numbers before naming a winner
local CHECK_EVERY = 300         -- and look again every 5 minutes (catches the reset while online)
local POST_TRIES = 60           -- wait up to 2 minutes for combat to end before giving up
local TAG = "Smoking Gnomes Inc.: "
local INSTALL = "github.com/gabefrann/SmokingGnomes"

local FIELDS = { "week", "winner", "pts", "n", "prize", "paid", "by", "paidBy", "u" }
local NUMBERS = { week = true, pts = true, n = true, prize = true, paid = true, u = true }

local function db()
	SG.db.hall = SG.db.hall or {}
	return SG.db.hall
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local function encode(h)
	local out = {}
	for i, f in ipairs(FIELDS) do
		local v = h[f]
		if NUMBERS[f] then
			out[i] = tostring(math.max(0, math.floor(tonumber(v) or 0)))
		else
			out[i] = tostring(v or ""):gsub("|", "")
		end
	end
	return table.concat(out, "|")
end

local function decode(raw, sig)
	if type(raw) ~= "string" or sig ~= SG.sign("W", raw) then
		return nil
	end
	local p = { strsplit("|", raw) }
	if #p ~= #FIELDS then
		return nil
	end
	local h = {}
	for i, f in ipairs(FIELDS) do
		if NUMBERS[f] then
			h[f] = tonumber(p[i])
			if not h[f] then
				return nil
			end
		else
			h[f] = p[i]
		end
	end
	if h.winner == "" or h.by == "" then
		return nil
	end
	return h
end

-- Only the guild master and officers may name a winner or mark a prize paid.
-- nil (roster not loaded yet) is given the benefit of the doubt.
local function allowed(name)
	return name and name ~= "" and SG.IsOfficer(name) ~= false
end

local function save(h)
	db()[h.week] = h
	ns.Sync.MarkHeard("fame", tostring(h.week), h.u)
	ns.UI.Refresh()
end

function Hall.Version(key)
	local h = db()[tonumber(key)]
	return h and h.u or 0
end

function Hall.Message(key)
	local h = db()[tonumber(key)]
	if not h then
		return nil
	end
	local raw = encode(h)
	return ("W|%d|%s|%s"):format(SG.VERSION, raw, SG.sign("W", raw))
end

function Hall.RelayList()
	local out = {}
	for week, h in pairs(db()) do
		if not h.test then
			out[#out + 1] = { "fame", tostring(week) }
		end
	end
	return out
end

-- Removes made-up winners from the old /gnomes test hall preview.
function Hall.ClearTests()
	for week, h in pairs(db()) do
		if h.test then
			db()[week] = nil
		end
	end
end

function Hall.Receive(raw, sig)
	local h = decode(raw, sig)
	if not h or h.week < START_WEEK or h.week > SG.weekId() then
		return
	end
	ns.Sync.MarkHeard("fame", tostring(h.week), h.u)
	if not allowed(h.by) or (h.paidBy ~= "" and not allowed(h.paidBy)) then
		return
	end
	local old = db()[h.week]
	if old and h.u <= (old.u or 0) then
		return
	end
	save(h)
end

local function share(h)
	save(h)
	ns.Sync.Enqueue("fame", tostring(h.week), true, true)
end

-- Weeks, newest first.
function Hall.List()
	local list = {}
	for _, h in pairs(db()) do
		list[#list + 1] = h
	end
	table.sort(list, function(a, b) return a.week > b.week end)
	return list
end

-- The date a week ended ("2 Dec").
function Hall.WeekLabel(week)
	return (date("!%d %b", week * 86400):gsub("^0", ""))
end

function Hall.Prize()
	return SG.db.settings.prize or 0
end

---------------------------------------------------------------------------
-- Guild chat
---------------------------------------------------------------------------

local function chatLocked()
	if InCombatLockdown() then
		return true
	end
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

-- Posts once combat (and any chat lockdown) is over; gives up after a couple of minutes.
local function post(msg, tries)
	if not inGuild() then
		return
	end
	tries = tries or 0
	if chatLocked() then
		if tries < POST_TRIES then
			C_Timer.After(2, function() post(msg, tries + 1) end)
		end
		return
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	pcall(send, msg, "GUILD")
end

local function prizeText(h)
	return (h.prize or 0) > 0 and (" Bonus: " .. h.prize .. "g.") or ""
end

---------------------------------------------------------------------------
-- Naming the winner and paying the prize (guild master and officers)
---------------------------------------------------------------------------

-- Officers' addons name last week's winner once it has had time to sync.
function Hall.Check()
	local week = SG.weekId() - 7
	if week < START_WEEK or db()[week] or SG.IsOfficer(SG.myName) ~= true then
		return
	end
	local winner, _, pts, n = SG.lastWeekWinner()
	if not winner or (pts or 0) <= 0 then
		return
	end
	local h = { week = week, winner = winner, pts = pts, n = n, prize = Hall.Prize(), paid = 0,
		by = SG.myName, paidBy = "", u = SG.now() }
	share(h)
	SG.print(("%s is Employee of the Week. Announced in guild chat; it's in the Hall of Fame."):format(SG.shortName(winner)))
	post(("%sEmployee of the Week is %s with %s points (%d gnome%s).%s Compete with the addon: %s"):format(TAG,
		SG.shortName(winner), SG.points(pts), n, n == 1 and "" or "s", prizeText(h), INSTALL))
end

function Hall.Start()
	Hall.ClearTests()
	C_Timer.After(math.random(CHECK_DELAY[1], CHECK_DELAY[2]), function()
		Hall.Check()
		C_Timer.NewTicker(CHECK_EVERY, Hall.Check)
	end)
end

-- Latest week whose prize hasn't been paid.
local function unpaid()
	for _, h in ipairs(Hall.List()) do
		if (h.paid or 0) == 0 and not h.test then
			return h
		end
	end
end

-- /gnomes prize <gold>: the bonus for future weeks, and for the latest unpaid week.
function Hall.SetPrize(gold)
	if SG.IsOfficer(SG.myName) ~= true then
		return false, "Only the guild master and officers can set the bonus."
	end
	gold = math.floor(tonumber(gold) or -1)
	if gold < 0 then
		return false, "Usage: /gnomes prize 50  (gold, 0 for none)"
	end
	SG.db.settings.prize = gold
	local h = unpaid()
	if h then
		h.prize, h.u = gold, math.max(SG.now(), (h.u or 0) + 1)
		share(h)
		return true, ("Bonus set to %dg, including %s's unpaid week."):format(gold, SG.shortName(h.winner))
	end
	return true, ("Bonus set to %dg from the next Employee of the Week."):format(gold)
end

-- /gnomes paid: marks the latest unpaid prize as paid and thanks the winner in guild chat.
function Hall.MarkPaid()
	if SG.IsOfficer(SG.myName) ~= true then
		return false, "Only the guild master and officers can mark the bonus paid."
	end
	local h = unpaid()
	if not h then
		return false, "Every Employee of the Week has been paid."
	end
	h.paid, h.paidBy, h.u = 1, SG.myName, math.max(SG.now(), (h.u or 0) + 1)
	share(h)
	if (h.prize or 0) > 0 then
		post(("%s%dg bonus paid to %s, Employee of the Week. Keep up the good work."):format(TAG, h.prize, SG.shortName(h.winner)))
	end
	return true, ("Marked %s's bonus (week ending %s) as paid."):format(SG.shortName(h.winner), Hall.WeekLabel(h.week))
end
