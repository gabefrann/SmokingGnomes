-- Smoking Gnomes Inc.: gank mode.
--
-- While it's on, enemy gnomes (and Recall Notice targets of any race) seen on
-- nameplates, under the mouse or as your target are called out and listed on a small
-- panel. Clicking a name targets that player, and a keybind targets the most recent
-- one. Targeting always needs your click or key press: addons can't pick a target on
-- their own, so this works like Next!, with secure buttons running /targetexact.
-- Secure buttons can only be changed outside combat, so the list freezes during a fight.

local _, ns = ...
local SG = ns.SG

local Gank = {}
ns.Gank = Gank

local CALLOUT_EVERY = 180 -- seconds between callouts for the same player
local KEEP = 180          -- seconds a spotted player stays on the list
local ROWS = 5
local ROW_H = 20
local W = 210
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT

local BORDER = { 0.145, 0.471, 0.243 }
local ACCENT = { 0.30, 0.71, 0.42 }
local RED = { 0.90, 0.36, 0.30 }
local MUTED = { 0.55, 0.55, 0.58 }
local TEXT = { 0.92, 0.92, 0.93 }

BINDING_HEADER_SMOKINGGNOMES = "Smoking Gnomes Inc."
_G["BINDING_NAME_CLICK SmokingGnomesTargetGnome:LeftButton"] = "Target the last spotted gnome"
BINDING_NAME_SMOKINGGNOMES_GANK = "Gank mode on or off"

local spotted = {} -- name -> { name, class, level, t, callout, recall }
local hud, rows, targetButton
local pending = false

local function isOn()
	return SG.db ~= nil and SG.db.settings.gank == true
end

local function plain(v)
	if v == nil or SG.secret(v) then
		return nil
	end
	return v
end

local function text(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "")
	fs:SetTextColor(unpack(color or TEXT))
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	fs:SetShadowColor(0, 0, 0, 0.8)
	fs:SetShadowOffset(1, -1)
	return fs
end

local function className(class)
	if not class then
		return nil
	end
	local names = LOCALIZED_CLASS_NAMES_MALE
	return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

local function classColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return unpack(TEXT)
end

-- An open Recall Notice on this name, if any.
local function recallFor(name)
	local want = name:lower()
	for _, row in ipairs(ns.Bounty.List()) do
		if row.state == "open" then
			local t = row.b.target:match("^[^%-%s]+")
			if t and t:lower() == want then
				return row.b
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Callouts
---------------------------------------------------------------------------

local function details(s)
	local out = {}
	if s.level and s.level > 0 then
		out[#out + 1] = "Level " .. s.level
	end
	if s.class then
		out[#out + 1] = className(s.class)
	end
	return table.concat(out, "  ·  ")
end

local function callout(s, bounty)
	if bounty then
		ns.UI.Notice("Recall target spotted: " .. s.name, "red", details(s), "Reward: " .. bounty.reward)
	else
		local v = ns.Ledger.Victim(s.name)
		local note = (v and v.n > 0) and ("Smoked %d× before."):format(v.n) or "No record with the company yet."
		ns.UI.Notice("Gnome spotted: " .. s.name, "green", details(s), note)
	end
	if SG.db.settings.gankSound ~= false then
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.MAP_PING) or 3175, "Master")
	end
end

function Gank.Spot(name, class, level, bounty)
	local now = GetTime()
	local s = spotted[name]
	if not s then
		s = { name = name }
		spotted[name] = s
	end
	s.class = class or s.class
	s.level = level or s.level
	s.t = now
	s.recall = bounty ~= nil
	if not s.callout or now - s.callout > CALLOUT_EVERY then
		s.callout = now
		callout(s, bounty)
	end
	Gank.Refresh()
end

-- Look at one unit: an enemy player who is a gnome or has an open Recall Notice.
local function check(unit)
	if not isOn() then
		return
	end
	-- World PvP only: battlegrounds and arenas would call out a gnome every few seconds.
	local okI, _, kind = pcall(IsInInstance)
	kind = okI and SG.str(kind)
	if kind == "pvp" or kind == "arena" then
		return
	end
	local okP, isPlayer = pcall(UnitIsPlayer, unit)
	if not okP or plain(isPlayer) ~= true then
		return
	end
	local okE, enemy = pcall(UnitIsEnemy, "player", unit)
	if not okE or plain(enemy) ~= true then
		return
	end
	local okN, name = pcall(UnitName, unit)
	name = okN and SG.str(name)
	if not name then
		return
	end
	local okR, _, race = pcall(UnitRace, unit)
	race = okR and SG.str(race)
	local bounty = recallFor(name)
	if race ~= "Gnome" and not bounty then
		return
	end
	local okC, _, class = pcall(UnitClass, unit)
	local okL, level = pcall(UnitLevel, unit)
	Gank.Spot(name, okC and SG.str(class) or nil, okL and SG.num(level) or nil, bounty)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function macroFor(name)
	return "/targetexact " .. name
end

local function secureButton(name, parent)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("useOnKeyDown", false)
	b:SetAttribute("type1", "macro")
	b:SetAttribute("macrotext1", "")
	return b
end

local function savePosition()
	local point, _, rel, x, y = hud:GetPoint()
	SG.db.settings.gankPos = { point, rel, x, y }
end

local function build()
	hud = CreateFrame("Frame", "SmokingGnomesGankPanel", UIParent, "BackdropTemplate")
	hud:SetSize(W, 52 + ROWS * ROW_H)
	hud:SetFrameStrata("MEDIUM")
	hud:SetClampedToScreen(true)
	hud:SetMovable(true)
	hud:EnableMouse(true)
	hud:RegisterForDrag("LeftButton")
	hud:SetScript("OnDragStart", hud.StartMoving)
	hud:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	hud:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	hud:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
	local pos = SG.db.settings.gankPos
	if pos then
		hud:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		hud:SetPoint("RIGHT", UIParent, "RIGHT", -220, 80)
	end

	hud.title = text(hud, 12, TEXT)
	hud.title:SetPoint("TOPLEFT", 10, -9)
	hud.title:SetText("Gank mode")
	hud.count = text(hud, 11, MUTED, "RIGHT")
	hud.count:SetPoint("TOPRIGHT", -10, -10)

	local div = hud:CreateTexture(nil, "ARTWORK")
	div:SetTexture(WHITE)
	div:SetVertexColor(BORDER[1], BORDER[2], BORDER[3], 0.6)
	div:SetHeight(1)
	div:SetPoint("TOPLEFT", 8, -28)
	div:SetPoint("TOPRIGHT", -8, -28)

	rows = {}
	for i = 1, ROWS do
		local r = secureButton("SmokingGnomesGankRow" .. i, hud)
		r:SetSize(W - 16, ROW_H)
		r:SetPoint("TOPLEFT", 8, -32 - (i - 1) * ROW_H)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture(WHITE)
		hl:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
		hl:SetAllPoints()
		r.name = text(r, 12)
		r.name:SetPoint("LEFT", 4, 0)
		r.name:SetWidth(108)
		r.info = text(r, 11, MUTED, "RIGHT")
		r.info:SetPoint("RIGHT", -4, 0)
		r.info:SetWidth(80)
		r:Hide()
		rows[i] = r
	end

	hud.empty = text(hud, 11, MUTED, "CENTER")
	hud.empty:SetPoint("TOP", 0, -56)
	hud.empty:SetText("No gnomes in sight.")
	hud.hint = text(hud, 10, MUTED, "CENTER")
	hud.hint:SetPoint("BOTTOM", 0, 7)
	hud.hint:SetText("Click a name to target it")

	-- Ages tick every second; that's text only, so it also works during combat.
	local elapsed = 0
	hud:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 1 then
			return
		end
		elapsed = 0
		local now = GetTime()
		for _, r in ipairs(rows) do
			if r.spot then
				local age = math.floor(now - r.spot.t)
				local lvl = r.spot.level and r.spot.level > 0 and (r.spot.level .. "  ") or ""
				r.info:SetText(lvl .. (age < 60 and (age .. "s") or (math.floor(age / 60) .. "m")))
			end
		end
	end)

	targetButton = secureButton("SmokingGnomesTargetGnome", UIParent)
	targetButton:SetSize(1, 1)
	targetButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	targetButton:Hide()

	hud:Hide()
end

function Gank.ApplyLook()
	if not hud or InCombatLockdown() then
		return
	end
	local s = SG.db.settings
	hud:SetScale(s.scale or 1)
	hud:SetBackdropColor(0.06, 0.06, 0.07, s.opacity or 0.98)
end

function Gank.Refresh()
	if not hud then
		return
	end
	if InCombatLockdown() then
		pending = true -- secure buttons can't change now; catch up after combat
		return
	end
	pending = false
	hud:SetShown(isOn())

	local now = GetTime()
	local list = {}
	for name, s in pairs(spotted) do
		if now - s.t > KEEP then
			spotted[name] = nil
		else
			list[#list + 1] = s
		end
	end
	table.sort(list, function(a, b)
		if a.recall ~= b.recall then
			return a.recall
		end
		return a.t > b.t
	end)

	for i, r in ipairs(rows) do
		local s = list[i]
		r.spot = s
		if s then
			r:SetAttribute("macrotext1", macroFor(s.name))
			r.name:SetText(s.name)
			if s.recall then
				r.name:SetTextColor(unpack(RED))
			else
				r.name:SetTextColor(classColor(s.class))
			end
			r:Show()
		else
			r:SetAttribute("macrotext1", "")
			r:Hide()
		end
	end
	targetButton:SetAttribute("macrotext1", list[1] and macroFor(list[1].name) or "")
	hud.empty:SetShown(#list == 0)
	hud.count:SetText(#list == 0 and "watching" or (#list .. " spotted"))
end

function Gank.Toggle(state)
	if InCombatLockdown() then
		SG.print("Gank mode can't be switched during combat.")
		return
	end
	if state == nil then
		state = not isOn()
	end
	SG.db.settings.gank = state
	if not state then
		wipe(spotted)
	end
	Gank.Refresh()
	if state then
		Gank.ScanNameplates()
	end
	ns.UI.Refresh()
	SG.print(state and "Gank mode on. Gnomes you see are called out and listed; click a name to target it."
		or "Gank mode off.")
end

function SmokingGnomes_ToggleGank()
	Gank.Toggle()
end

-- Check what's already on screen when gank mode turns on or the UI loads.
local function scanNameplates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then
		return
	end
	for _, plate in ipairs(plates) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		unit = SG.str(unit)
		if unit then
			check(unit)
		end
	end
end

function Gank.Init()
	build()
	Gank.ApplyLook()
	Gank.Refresh()
	local f = CreateFrame("Frame")
	f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			if SG.str(unit) then
				check(unit)
			end
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			check("mouseover")
		elseif event == "PLAYER_TARGET_CHANGED" then
			check("target")
		elseif event == "PLAYER_REGEN_ENABLED" then
			if pending then
				Gank.Refresh()
			end
			Gank.ApplyLook()
		end
	end)
	-- Drop stale names now and then.
	C_Timer.NewTicker(15, function()
		if isOn() and not InCombatLockdown() then
			Gank.Refresh()
		end
	end)
	if isOn() then
		scanNameplates()
	end
end

Gank.ScanNameplates = scanNameplates
