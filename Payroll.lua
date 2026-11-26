-- Smoking Gnomes Inc.: weekly payroll.
--
-- Every job title has a weekly salary (SG.TITLES in Core.lua). After the weekly reset,
-- everyone who harvested at least one honorable gnome last week is owed their title's
-- salary ("no work, no pay"); the guild master (CEO) is not on the payroll. Officers can
-- cap the total: above the cap, every salary is cut by the same share.
-- Officers pay by hand, then mark the week paid. That makes one signed record per week,
-- relayed like the others and accepted only from the guild master and officers:
--   P|version|week|total|count|percent|by|u|signature
-- Employees on that payroll get a popup when it arrives. Nothing goes to guild chat.

local _, ns = ...
local SG = ns.SG

local Payroll = {}
ns.Payroll = Payroll

local START_WEEK = 20789 -- the week ending 2 Dec 2026 is the first payroll
local FIELDS = { "week", "total", "count", "percent", "by", "u" }
local NUMBERS = { week = true, total = true, count = true, percent = true, u = true }

local function db()
	SG.db.payroll = SG.db.payroll or {}
	return SG.db.payroll
end

Payroll.START_WEEK = START_WEEK

-- The cap in gold (0 = no cap). Set by an officer on their own computer.
function Payroll.Cap()
	return SG.db.settings.payrollCap or 0
end

-- The payroll for the week ending `week`. With `live`, the current week so far.
-- Everyone who worked is listed, unpaid titles too (pay 0), so people see where they stand.
-- Returns rows { name, honor, title, pay } (highest pay first), the total, and the
-- percentage paid (100 unless the cap cut it). `percent` forces a percentage (a paid week).
function Payroll.Compute(week, live, percent)
	local cur = SG.weekId()
	local rows, total = {}, 0
	for name, e in pairs(SG.db.players) do
		local worked, lifetime
		if live then
			worked = e.weekId == cur and (e.hw or e.week or 0) or 0
			lifetime = SG.honorCount(e)
		else
			worked = SG.lastWeekHonor(e, week + 7)
			-- The title held at the end of that week: this week's gnomes don't count yet.
			lifetime = SG.honorCount(e) - (e.weekId == cur and week + 7 == cur and (e.hw or e.week or 0) or 0)
		end
		-- The guild master (CEO) is never paid, so isn't listed.
		local ceo = SG.guildMaster and SG.sameName(name, SG.guildMaster)
		if worked > 0 and not ceo then
			local title, _, _, pay = SG.jobTitle(name, lifetime)
			rows[#rows + 1] = { name = name, honor = worked, title = title, pay = pay, lifetime = lifetime, e = e }
			total = total + pay
		end
	end
	if not percent then
		percent = 100
		local cap = Payroll.Cap() * 10000
		if cap > 0 and total > cap then
			percent = math.floor(cap / total * 100)
		end
	end
	if percent < 100 then
		total = 0
		for _, r in ipairs(rows) do
			r.pay = math.floor(r.pay * percent / 100 / 100) * 100 -- whole silver
			total = total + r.pay
		end
	end
	table.sort(rows, function(a, b)
		if a.pay ~= b.pay then
			return a.pay > b.pay
		end
		if a.honor ~= b.honor then
			return a.honor > b.honor
		end
		return a.name < b.name
	end)
	return rows, total, percent
end

-- The week the payroll view shows: last week, or the current week as a preview while
-- the first payroll week is still running.
function Payroll.ViewWeek()
	local last = SG.weekId() - 7
	if last < START_WEEK then
		return SG.weekId(), true
	end
	return last, false
end

function Payroll.Record(week)
	return db()[week]
end

---------------------------------------------------------------------------
-- Paid records
---------------------------------------------------------------------------

local function encode(p)
	local out = {}
	for i, f in ipairs(FIELDS) do
		local v = p[f]
		if NUMBERS[f] then
			out[i] = tostring(math.max(0, math.floor(tonumber(v) or 0)))
		else
			out[i] = tostring(v or ""):gsub("|", "")
		end
	end
	return table.concat(out, "|")
end

local function decode(raw, sig)
	if type(raw) ~= "string" or sig ~= SG.sign("P", raw) then
		return nil
	end
	local parts = { strsplit("|", raw) }
	if #parts ~= #FIELDS then
		return nil
	end
	local p = {}
	for i, f in ipairs(FIELDS) do
		if NUMBERS[f] then
			p[f] = tonumber(parts[i])
			if not p[f] then
				return nil
			end
		else
			p[f] = parts[i]
		end
	end
	return p.by ~= "" and p or nil
end

function Payroll.Version(key)
	local p = db()[tonumber(key)]
	return p and p.u or 0
end

function Payroll.Message(key)
	local p = db()[tonumber(key)]
	if not p then
		return nil
	end
	local raw = encode(p)
	return ("P|%d|%s|%s"):format(SG.VERSION, raw, SG.sign("P", raw))
end

function Payroll.RelayList()
	local out = {}
	for week in pairs(db()) do
		out[#out + 1] = { "payroll", tostring(week) }
	end
	return out
end

-- Tell me if I was on a payroll that was just paid.
local function notifyMine(p)
	if p.by == SG.myName then
		return
	end
	local rows = Payroll.Compute(p.week, false, p.percent)
	for _, r in ipairs(rows) do
		if r.name == SG.myName and r.pay > 0 then
			ns.UI.Notice("Payroll processed", "gold", ("Your salary: %s"):format(SG.money(r.pay)),
				("%s as %s, week ending %s. Check your mail."):format(SG.shortName(p.by), r.title, ns.Hall.WeekLabel(p.week)))
			return
		end
	end
end

function Payroll.Receive(raw, sig)
	local p = decode(raw, sig)
	if not p or p.week < START_WEEK or p.week > SG.weekId() then
		return
	end
	ns.Sync.MarkHeard("payroll", tostring(p.week), p.u)
	if SG.IsOfficer(p.by) == false then
		return
	end
	local old = db()[p.week]
	if old and p.u <= (old.u or 0) then
		return
	end
	db()[p.week] = p
	if not old and SG.now() - p.u < 7 * 86400 then
		notifyMine(p)
	end
	ns.UI.Refresh()
end

---------------------------------------------------------------------------
-- Officer commands
---------------------------------------------------------------------------

-- /gnomes payroll paid: last week's payroll has been paid out.
function Payroll.MarkPaid()
	if SG.IsOfficer(SG.myName) ~= true then
		return false, "Only the guild master and officers can mark the payroll paid."
	end
	local week, preview = Payroll.ViewWeek()
	if preview then
		return false, "The first payroll is for the week ending 2 December. Pay it after that reset."
	end
	if db()[week] then
		return false, ("The payroll for the week ending %s is already marked paid."):format(ns.Hall.WeekLabel(week))
	end
	local rows, total, percent = Payroll.Compute(week)
	local paidRows = 0
	for _, r in ipairs(rows) do
		if r.pay > 0 then
			paidRows = paidRows + 1
		end
	end
	if paidRows == 0 then
		return false, "Nobody is owed a salary for last week."
	end
	local p = { week = week, total = total, count = paidRows, percent = percent, by = SG.myName, u = SG.now() }
	db()[week] = p
	ns.Sync.MarkHeard("payroll", tostring(week), p.u)
	ns.Sync.Enqueue("payroll", tostring(week), true, true)
	ns.UI.Refresh()
	return true, ("Payroll for the week ending %s marked paid: %d employee%s, %s in total."):format(
		ns.Hall.WeekLabel(week), paidRows, paidRows == 1 and "" or "s", SG.money(total))
end

-- /gnomes payroll cap <gold>: the most the payroll may cost in a week (0 = no cap).
function Payroll.SetCap(gold)
	if SG.IsOfficer(SG.myName) ~= true then
		return false, "Only the guild master and officers can set the payroll cap."
	end
	gold = math.floor(tonumber(gold) or -1)
	if gold < 0 then
		return false, "Usage: /gnomes payroll cap 25  (gold per week, 0 for no cap)"
	end
	SG.db.settings.payrollCap = gold
	return true, gold > 0 and ("Payroll capped at %dg a week. Above that, every salary is cut by the same share."):format(gold)
		or "Payroll cap removed."
end
