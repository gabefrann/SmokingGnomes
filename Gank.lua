-- Smoking Gnomes Inc.: gank mode.
--
-- While it's on, enemy gnomes (and Recall Notice targets of any race) seen on
-- nameplates, under the mouse or as your target are called out and listed on a small
-- panel. Clicking a name targets that player, and a keybind targets the most recent
-- one. Targeting always needs your click or key press: addons can't pick a target on
-- their own, so this works like Next!, with secure buttons running /targetexact.
-- Secure buttons can only be changed outside combat, so the list freezes during a fight.
-- Also listed, quietly: gnomes a groupmate has targeted, and gnomes guildmates on the
-- same map spotted (shared over the guild addon channel).

local _, ns = ...
local SG = ns.SG

local Gank = {}
ns.Gank = Gank

local CALLOUT_EVERY = 180 -- seconds between callouts for the same player
local KEEP = 180          -- seconds a spotted player stays on the list
local SHARE_EVERY = 120   -- seconds between telling the guild about the same gnome
local GROUP_COLOR = "66bbff" -- a groupmate's target
local SEEN_COLOR = "d9b35c"  -- spotted by a guildmate in my zone
local ROWS = 5         -- rows shown at the default size
local MAX_ROWS = 12    -- rows available when the panel is resized taller
local ROW_H = 20
local W = 240
local MIN_W, MIN_H, MAX_W = 220, 52 + 1 * ROW_H, 420 -- the status column needs room for "Molly's target"
local MAX_H = 52 + MAX_ROWS * ROW_H
local visibleRows = ROWS
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
	fs:SetFont(FONT, size, "OUTLINE") -- thin outline keeps text readable over any background
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

-- An open corporate spy report on this player, if any.
local function recallFor(name)
	for _, row in ipairs(ns.Bounty.List()) do
		if row.state == "open" and SG.sameName(row.b.target, name) then
			return row.b
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Callout sounds. Sound kits are looked up by name so a missing one is skipped
-- instead of playing nothing silently. Soft sounds use the sound-effects volume.
---------------------------------------------------------------------------

Gank.SOUNDS = {
	{ key = "soft", label = "Soft", kit = "TELL_MESSAGE", channel = "SFX" },
	{ key = "coins", label = "Coins", kit = "LOOT_WINDOW_COIN_SOUND", channel = "SFX" },
	{ key = "ding", label = "Ding", file = 567458, channel = "Master" },
	{ key = "off", label = "Off" },
}

function Gank.SoundChoice()
	local s = SG.db.settings
	if s.gankSoundChoice == nil and s.gankSound == false then
		s.gankSoundChoice = "off" -- older setting
	end
	local key = s.gankSoundChoice or "soft"
	for i, snd in ipairs(Gank.SOUNDS) do
		if snd.key == key then
			return snd, i
		end
	end
	return Gank.SOUNDS[1], 1
end

local function play(snd)
	if snd.kit then
		local id = SOUNDKIT and SOUNDKIT[snd.kit]
		local ok, played = false, false
		if id then
			ok, played = pcall(PlaySound, id, snd.channel)
		end
		if not (ok and played ~= false) then
			pcall(PlaySoundFile, 567458, "SFX") -- that sound isn't on this client: quiet ding
		end
	elseif snd.file then
		pcall(PlaySoundFile, snd.file, snd.channel)
	end
end

-- Recall targets always get the coins (there's money on them), unless sound is off.
function Gank.PlayCallout(recall)
	local snd = Gank.SoundChoice()
	if snd.key == "off" then
		return
	end
	play(recall and Gank.SOUNDS[2] or snd)
end

-- Settings: step to the next sound and play it as a preview.
function Gank.CycleSound()
	local _, i = Gank.SoundChoice()
	local nextSnd = Gank.SOUNDS[i % #Gank.SOUNDS + 1]
	SG.db.settings.gankSoundChoice = nextSnd.key
	play(nextSnd)
	return nextSnd
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
		ns.UI.Notice("Corporate spy spotted: " .. s.name, "red", details(s), "Reward: " .. bounty.reward .. ". It's on sight.")
	else
		local v = ns.Ledger.Victim(s.name)
		local note = (v and v.n > 0) and ("Smoked %d× before."):format(v.n) or "No record with the company yet."
		ns.UI.Notice("Gnome spotted: " .. s.name, "green", details(s), note)
	end
	Gank.PlayCallout(bounty ~= nil)
end

-- Is this unit token still the spotted player?
local function isUnit(unit, name)
	local ok, exists = pcall(UnitExists, unit)
	return ok and plain(exists) == true and SG.unitFullName(unit) == name
end

-- In view right now: their nameplate is up (within nameplate range) or they're my target.
-- Keeps "last seen" current while they're in view. Returns the unit token, or nil.
local function inView(s)
	if s.unit and not isUnit(s.unit, s.name) then
		s.unit = nil
	end
	local unit = s.unit or (isUnit("target", s.name) and "target") or nil
	if unit then
		s.t = GetTime()
	end
	return unit
end

local function isDead(unit)
	local ok, dead = pcall(UnitIsDeadOrGhost, unit)
	return ok and plain(dead) == true
end

-- A groupmate still has them targeted.
local function groupTarget(s)
	if s.byUnit and isUnit(s.byUnit, s.name) then
		s.t = GetTime()
		return true
	end
	s.byUnit = nil
	return false
end

-- The map I'm on, used to keep guildmates' spots to my zone.
local function myMap()
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and SG.num(map) or nil
end

local function inBattle()
	local ok, _, kind = pcall(IsInInstance)
	kind = ok and SG.str(kind)
	return kind == "pvp" or kind == "arena"
end

-- First word of a name, at most 7 letters, for the narrow status column.
local function short(name)
	local first = (name or ""):match("^%S+") or ""
	return #first > 7 and first:sub(1, 7) or first
end

local function ago(seconds)
	seconds = math.max(0, math.floor(seconds))
	return seconds < 60 and (seconds .. "s") or (math.floor(seconds / 60) .. "m")
end

-- Seen by a guildmate more recently than by me.
local function guildSpot(s)
	return s.seenBy and (not s.mine or s.seenAt > s.mine)
end

-- The status column: level, then near / dead / a groupmate's target / a guildmate's
-- spot / time since I last saw them.
function Gank.Status(s)
	local lvl = s.level and s.level > 0 and (s.level .. "  ") or ""
	local unit = inView(s)
	if unit then
		return lvl .. (isDead(unit) and "|cff8c8c94dead|r" or "|cff4cb56bnear|r")
	end
	if groupTarget(s) then
		return lvl .. (isDead(s.byUnit) and "|cff8c8c94dead|r" or ("|cff" .. GROUP_COLOR .. short(s.by) .. "'s target|r"))
	end
	if guildSpot(s) then
		return lvl .. "|cff" .. SEEN_COLOR .. short(s.seenBy) .. " · " .. ago(GetTime() - s.seenAt) .. " ago|r"
	end
	return lvl .. ago(GetTime() - s.t) .. " ago"
end

-- Row tooltip: who this is and where the sighting came from.
function Gank.Tooltip(row)
	local s = row.spot
	if not s then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:AddLine(s.name, classColor(s.class))
	local d = details(s)
	if d ~= "" then
		GameTooltip:AddLine(d, 1, 1, 1)
	end
	if s.recall then
		GameTooltip:AddLine("Corporate spy. It's on sight.", unpack(RED))
	end
	local unit = inView(s)
	if unit then
		GameTooltip:AddLine("In view: within nameplate range.", unpack(ACCENT))
	elseif groupTarget(s) then
		GameTooltip:AddLine(s.by .. " has them targeted right now.", 0.4, 0.73, 1)
	elseif guildSpot(s) then
		GameTooltip:AddLine(("Seen by %s in your zone %s ago."):format(s.seenBy, ago(GetTime() - s.seenAt)), 0.85, 0.7, 0.36)
	else
		GameTooltip:AddLine("You last saw them " .. ago(GetTime() - s.t) .. " ago.", unpack(MUTED))
	end
	GameTooltip:AddLine("Click to target. Works when they're within about 100 yards.", unpack(MUTED))
	GameTooltip:Show()
end

-- opts.member: spotted as this groupmate's target (unit is their "...target" token).
-- opts.test: a test row; never shared with the guild.
function Gank.Spot(name, class, level, bounty, unit, opts)
	opts = opts or {}
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
	if opts.member then
		-- Someone else's target: listed quietly, no popup and no sound.
		s.by, s.byUnit = opts.member, unit
		Gank.Refresh()
		return
	end
	if unit and unit:match("^nameplate") then
		s.unit = unit
	end
	s.mine = now
	if not s.callout or now - s.callout > CALLOUT_EVERY then
		s.callout = now
		callout(s, bounty)
	end
	-- Tell guildmates in the same zone (skipped if one of them just did).
	if not opts.test and (not s.shared or now - s.shared > SHARE_EVERY) and myMap() then
		s.shared = now
		ns.Sync.Enqueue("spot", name, true) -- front of the queue: it's only useful right away
	end
	Gank.Refresh()
end

-- The guild message for a gnome I spotted: S|version|name|class|level|map
function Gank.SpotMessage(name)
	local s, map = spotted[name], myMap()
	if not s or not map or not isOn() or inBattle() then
		return nil
	end
	return ("S|%d|%s|%s|%d|%d"):format(SG.VERSION, name, s.class or "", s.level or 0, map)
end

-- A guildmate spotted a gnome. Listed quietly, and only if they're on my map.
function Gank.Remote(sender, name, class, level, map)
	if not isOn() or inBattle() then
		return
	end
	name = SG.fullName(name)
	if not name or #name > 48 or tonumber(map) ~= myMap() then
		return
	end
	local now = GetTime()
	local s = spotted[name]
	if not s then
		s = { name = name }
		spotted[name] = s
	end
	if class and class:match("^%u+$") then
		s.class = s.class or class
	end
	level = tonumber(level)
	if level and level > 0 and level < 100 then
		s.level = s.level or level
	end
	s.seenBy, s.seenAt = sender, now
	s.t = math.max(s.t or 0, now)
	s.recall = recallFor(name) ~= nil
	Gank.Refresh()
end

-- Look at one unit: an enemy player who is a gnome or has an open Recall Notice.
-- member: the groupmate whose target this unit is (unit = "party1target" and so on).
local function check(unit, member)
	if not isOn() then
		return
	end
	-- World PvP only: battlegrounds and arenas would call out a gnome every few seconds.
	if inBattle() then
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
	local name = SG.unitFullName(unit) -- "Legs Dogman": first name and surname
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
	Gank.Spot(name, okC and SG.str(class) or nil, okL and SG.num(level) or nil, bounty, unit,
		member and { member = member } or nil)
end

-- What each groupmate has targeted. The game shares this with every addon; nothing is sent.
local function checkGroupTarget(member)
	if not member:match("^party%d$") and not member:match("^raid%d+$") then
		return
	end
	local okMe, isMe = pcall(UnitIsUnit, member, "player")
	if not okMe or plain(isMe) ~= false then
		return
	end
	local who = SG.unitFullName(member)
	if who then
		check(member .. "target", who)
	end
end

local function scanGroupTargets()
	local okR, raid = pcall(IsInRaid)
	local prefix = okR and plain(raid) == true and "raid" or "party"
	local okN, n = pcall(GetNumGroupMembers)
	n = okN and SG.num(n) or 0
	for i = 1, (prefix == "raid" and n or math.min(n, 4)) do
		checkGroupTarget(prefix .. i)
	end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

-- Forever names have a surname; it's not confirmed whether /targetexact wants the full
-- name or the first name, so try the full name and then the first name.
local function macroFor(name)
	local first = name:match("^%S+")
	if first and first ~= name then
		return "/targetexact " .. name .. "\n/targetexact " .. first
	end
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
	local size = SG.db.settings.gankSize
	hud:SetSize(math.max(MIN_W, size and size[1] or W), size and size[2] or (52 + ROWS * ROW_H))
	hud:SetFrameStrata("MEDIUM")
	hud:SetClampedToScreen(true)
	hud:SetMovable(true)
	hud:EnableMouse(true)
	hud:RegisterForDrag("LeftButton")
	-- Moving and sizing are blocked in combat (the panel holds secure buttons).
	hud:SetScript("OnDragStart", function(self)
		if not InCombatLockdown() then
			self.busy = true
			self:StartMoving()
		end
	end)
	hud:SetScript("OnDragStop", function(self)
		if self.busy and not InCombatLockdown() then
			self.busy = false
			self:StopMovingOrSizing()
			savePosition()
		end
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
	for i = 1, MAX_ROWS do
		local r = secureButton("SmokingGnomesGankRow" .. i, hud)
		r:SetHeight(ROW_H)
		r:SetPoint("TOPLEFT", 8, -32 - (i - 1) * ROW_H)
		r:SetPoint("TOPRIGHT", -8, -32 - (i - 1) * ROW_H)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture(WHITE)
		hl:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
		hl:SetAllPoints()
		r.name = text(r, 12)
		r.name:SetPoint("LEFT", 4, 0)
		r.name:SetPoint("RIGHT", r, "RIGHT", -124, 0)
		r.info = text(r, 11, MUTED, "RIGHT")
		r.info:SetPoint("RIGHT", -4, 0)
		r.info:SetWidth(120)
		r:SetScript("OnEnter", Gank.Tooltip)
		r:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		r:Hide()
		rows[i] = r
	end

	hud.empty = text(hud, 11, MUTED, "CENTER")
	hud.empty:SetPoint("TOP", 0, -56)
	hud.empty:SetText("No gnomes in sight.")
	hud.hint = text(hud, 10, MUTED, "CENTER")
	hud.hint:SetPoint("BOTTOM", 0, 7)
	hud.hint:SetText("Click a name to target it")

	-- "near" while in view, else time since last seen. Updated twice a second; text only,
	-- so it also works during combat.
	local elapsed = 0
	hud:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		for _, r in ipairs(rows) do
			if r.spot then
				r.info:SetText(Gank.Status(r.spot))
			end
		end
	end)

	-- Corner grip: resize outside combat (the panel holds secure buttons, which the
	-- game won't let addons move or resize during a fight).
	hud:SetResizable(true)
	if hud.SetResizeBounds then
		hud:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	else
		hud:SetMinResize(MIN_W, MIN_H)
		hud:SetMaxResize(MAX_W, MAX_H)
	end
	local grip = CreateFrame("Button", nil, hud)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture(386864)    -- the chat window's size grabber
	grip:SetPushedTexture(386862)
	grip:SetHighlightTexture(386863)
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and not InCombatLockdown() then
			hud.busy = true
			hud:StartSizing("BOTTOMRIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", function()
		if hud.busy and not InCombatLockdown() then
			hud.busy = false
			hud:StopMovingOrSizing()
			SG.db.settings.gankSize = { math.floor(hud:GetWidth() + 0.5), math.floor(hud:GetHeight() + 0.5) }
			savePosition() -- sizing can re-anchor the panel
			Gank.Refresh()
		end
	end)
	hud:SetScript("OnSizeChanged", function(_, _, h)
		visibleRows = math.max(1, math.min(MAX_ROWS, math.floor((h - 52) / ROW_H)))
	end)
	visibleRows = math.max(1, math.min(MAX_ROWS, math.floor((hud:GetHeight() - 52) / ROW_H)))

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

	local list = {}
	for _, s in pairs(spotted) do
		s.near = inView(s) ~= nil
		s.grp = not s.near and groupTarget(s)
	end
	local now = GetTime()
	for name, s in pairs(spotted) do
		if now - s.t > KEEP then
			spotted[name] = nil
		else
			list[#list + 1] = s
		end
	end
	-- Spies first, then whoever is in view, then the most recently seen.
	table.sort(list, function(a, b)
		if a.recall ~= b.recall then
			return a.recall
		end
		if a.near ~= b.near then
			return a.near
		end
		if a.grp ~= b.grp then
			return a.grp
		end
		return a.t > b.t
	end)

	for i, r in ipairs(rows) do
		local s = i <= visibleRows and list[i] or nil
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
	-- Names from the group or guild may be out of targeting range: say so, so a click
	-- that does nothing doesn't look broken.
	local secondhand = false
	for i = 1, math.min(#list, visibleRows) do
		local s = list[i]
		if not s.near and (s.grp or guildSpot(s)) then
			secondhand = true
		end
	end
	hud.hint:SetText(secondhand and "Group/guild names may be out of range" or "Click a name to target it")
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
	SG.print(state and "Gank mode on. Gnomes you see are called out and listed, along with gnomes your group targets and guildmates in this zone spot. Click a name to target it (within about 100 yards)."
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
	f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("UNIT_TARGET")
	f:RegisterEvent("GROUP_ROSTER_UPDATE")
	f:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_TARGET" then
			unit = SG.str(unit)
			if unit then
				checkGroupTarget(unit)
			end
			return
		elseif event == "GROUP_ROSTER_UPDATE" then
			scanGroupTargets()
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then
			-- Combat is starting: let go of a drag or resize while that's still allowed.
			if hud and hud.busy then
				hud.busy = false
				pcall(hud.StopMovingOrSizing, hud)
				SG.db.settings.gankSize = { math.floor(hud:GetWidth() + 0.5), math.floor(hud:GetHeight() + 0.5) }
				savePosition()
			end
			return
		end
		-- Remember enemy levels (gank mode on or off) so kills can be scored by level.
		if event == "NAME_PLATE_UNIT_ADDED" and SG.str(unit) then
			SG.noteLevel(unit)
		elseif event == "UPDATE_MOUSEOVER_UNIT" then
			SG.noteLevel("mouseover")
		elseif event == "PLAYER_TARGET_CHANGED" then
			SG.noteLevel("target")
		end
		if event == "NAME_PLATE_UNIT_ADDED" then
			if SG.str(unit) then
				check(unit)
			end
		elseif event == "NAME_PLATE_UNIT_REMOVED" then
			-- Out of nameplate range (or hidden): last seen now.
			for _, s in pairs(spotted) do
				if s.unit and s.unit == unit then
					s.unit = nil
					s.t = GetTime()
				end
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
		if isOn() then
			scanGroupTargets()
		end
		if isOn() and not InCombatLockdown() then
			Gank.Refresh()
		end
	end)
	if isOn() then
		scanNameplates()
	end
end

Gank.ScanNameplates = scanNameplates
