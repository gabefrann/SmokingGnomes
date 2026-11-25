-- Smoking Gnomes Inc.: Production Report window, popups, player tooltips,
-- AddOn compartment button.

local _, ns = ...
local SG = ns.SG

local UI = {}
ns.UI = UI

local W, ROW_H, ROWS = 300, 20, 10
local RECALL_ROWS = 9 -- the officer form takes the last row's space on the Recalls tab
local PAD = 14
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT

local LOGO = "Interface\\AddOns\\SmokingGnomes\\Media\\logo"
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12:0:0|t"
local ICON_OPEN = "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12:0:0|t"
local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local ICON_CLOSED = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"

-- Guild green, taken from the logo (#25783E), plus a lighter tint that stays readable as text.
local BORDER = { 0.145, 0.471, 0.243 }
local ACCENT = { 0.30, 0.71, 0.42 }
local GOLD = { 1.0, 0.82, 0.30 }
local RED = { 0.90, 0.36, 0.30 }
local MUTED = { 0.55, 0.55, 0.58 }
local TEXT = { 0.92, 0.92, 0.93 }
local COLORS = { red = RED, gold = GOLD, green = ACCENT, white = TEXT }
local STALE_DAYS = 14

local LAB_NOTES = {
	"Sample sent to the lab.",
	"Quality control approved.",
	"Another batch for R&D.",
}

local frame, rows, tabs, footer, footerRight, sub, empty, colHeads, form, companyLine
local mode = "week"
local champion -- last week's winner, refreshed with the window

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

local function rect(parent, r, g, b, a, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	t:SetVertexColor(r, g, b, a)
	return t
end

local function hex(c)
	return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function classColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return unpack(TEXT)
end

---------------------------------------------------------------------------
-- Guild crest: drawn live from the game's own tabard textures and colours, so it is
-- the real guild emblem at the game's own quality. Falls back to Media\logo.
---------------------------------------------------------------------------

local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a white filled circle
local crests = {}

-- The live crest is opt-in (/gnomes crest on): Forever's emblem file doesn't map onto
-- a single icon, so the logo file is the default. `force` is for the crest sheet,
-- which always shows what the game gives so it can be captured.
local function tabardInfo(force)
	if not force and not (SG.db and SG.db.settings.crest == true) then
		return nil
	end
	if not (C_GuildInfo and C_GuildInfo.GetGuildTabardInfo) then
		return nil
	end
	local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
	if ok and type(info) == "table" and SG.num(info.emblemFileID) then
		return info
	end
	return nil
end

local function rgb(color)
	if type(color) == "table" and color.GetRGB then
		local ok, r, g, b = pcall(color.GetRGB, color)
		if ok and SG.num(r) and SG.num(g) and SG.num(b) then
			return r, g, b
		end
	end
	return 1, 1, 1
end

local function applyCrest(c)
	local info = tabardInfo(c.force)
	local live = info ~= nil
	c.fallback:SetShown(not live)
	c.ring:SetShown(live)
	c.bg:SetShown(live)
	c.emblem:SetShown(live)
	if live then
		c.ring:SetVertexColor(rgb(info.borderColor))
		c.bg:SetVertexColor(rgb(info.backgroundColor))
		c.emblem:SetTexture(info.emblemFileID)
		c.emblem:SetVertexColor(rgb(info.emblemColor))
	end
end

local function makeCrest(parent, size)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(size, size)
	c.fallback = c:CreateTexture(nil, "ARTWORK")
	c.fallback:SetTexture(LOGO)
	c.fallback:SetAllPoints()
	c.ring = c:CreateTexture(nil, "ARTWORK", nil, 1)
	c.ring:SetTexture(CIRCLE)
	c.ring:SetAllPoints()
	c.bg = c:CreateTexture(nil, "ARTWORK", nil, 2)
	c.bg:SetTexture(CIRCLE)
	c.bg:SetPoint("CENTER")
	c.bg:SetSize(size * 0.86, size * 0.86)
	c.emblem = c:CreateTexture(nil, "ARTWORK", nil, 3)
	c.emblem:SetPoint("CENTER")
	c.emblem:SetSize(size * 0.74, size * 0.74)
	crests[#crests + 1] = c
	applyCrest(c)
	return c
end

function UI.RefreshCrests()
	for _, c in ipairs(crests) do
		applyCrest(c)
	end
end

-- A large crest on a plain background plus the exact tabard data, for screenshots
-- and for rebuilding the logo outside the game.
local sheet
function UI.ShowCrestSheet()
	if not sheet then
		sheet = CreateFrame("Frame", "SmokingGnomesCrestSheet", UIParent, "BackdropTemplate")
		sheet:SetSize(560, 640)
		sheet:SetPoint("CENTER")
		sheet:SetFrameStrata("DIALOG")
		sheet:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		sheet:SetBackdropColor(0.06, 0.06, 0.07, 1)
		sheet:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
		sheet:EnableMouse(true)
		sheet:SetScript("OnMouseUp", sheet.Hide)
		tinsert(UISpecialFrames, "SmokingGnomesCrestSheet")
		sheet.crest = makeCrest(sheet, 512)
		sheet.crest.force = true
		sheet.crest:SetPoint("TOP", 0, -24)
		sheet.info = text(sheet, 12, TEXT, "CENTER")
		sheet.info:SetPoint("BOTTOM", 0, 44)
		sheet.hint = text(sheet, 11, MUTED, "CENTER")
		sheet.hint:SetPoint("BOTTOM", 0, 20)
		sheet.hint:SetText("Take a screenshot (Print Screen), then click or press Escape to close.")
	end
	applyCrest(sheet.crest)
	local info = tabardInfo(true)
	if info then
		local function hexOf(c)
			local r, g, b = rgb(c)
			return ("#%02X%02X%02X"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
		end
		local line = ("Emblem file %d   ·   Emblem %s   ·   Background %s   ·   Border %s"):format(
			info.emblemFileID, hexOf(info.emblemColor), hexOf(info.backgroundColor), hexOf(info.borderColor))
		sheet.info:SetText(line)
		SG.print("Guild crest: " .. line)
	else
		sheet.info:SetText("The game didn't provide the guild tabard here, so this is the logo file.")
	end
	sheet:Show()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function savePosition()
	local point, _, rel, x, y = frame:GetPoint()
	SG.db.settings.pos = { point, rel, x, y }
end

local function makeRow()
	local r = CreateFrame("Frame", nil, frame)
	r:SetSize(W - PAD * 2, ROW_H)
	r.hl = rect(r, ACCENT[1], ACCENT[2], ACCENT[3], 0.10)
	r.hl:SetAllPoints()
	r.rank = text(r, 11, MUTED, "RIGHT")
	r.rank:SetPoint("LEFT", 0, 0)
	r.rank:SetWidth(20)
	r.name = text(r, 12)
	r.name:SetPoint("LEFT", 28, 0)
	r.assists = text(r, 11, MUTED, "RIGHT")
	r.assists:SetPoint("RIGHT", 0, 0)
	r.kills = text(r, 12, TEXT, "RIGHT")
	r.kills:SetPoint("RIGHT", r.assists, "LEFT", -6, 0)
	r:EnableMouse(true)
	r:SetScript("OnEnter", function(self)
		if not self.tip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		for idx, line in ipairs(self.tip) do
			if idx == 1 then
				GameTooltip:AddLine(line, 1, 1, 1)
			elseif idx == 2 and self.tipColor then
				GameTooltip:AddLine(line, self.tipColor[1], self.tipColor[2], self.tipColor[3])
			else
				GameTooltip:AddLine(line, MUTED[1], MUTED[2], MUTED[3])
			end
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	r:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and IsShiftKeyDown() and self.cancelTarget then
			-- Cancel refreshes the list, which clears self.cancelTarget, so keep a copy.
			local target = self.cancelTarget
			local ok, err = ns.Bounty.Cancel(target)
			SG.print(ok and ("Spy report on " .. target .. " withdrawn.") or tostring(err))
		end
	end)
	return r
end

-- Column widths differ between the boards and the Recalls tab.
local function layoutRow(r, recall)
	r.assists:SetWidth(recall and 64 or 56)
	r.kills:SetWidth(recall and 84 or 50)
	r.kills:SetFont(FONT, recall and 11 or 12, "OUTLINE")
	r.name:SetWidth(recall and 92 or 150)
	r.cancelTarget = nil
end

local function makeTab(label, key, x)
	local b = CreateFrame("Button", nil, frame)
	b.label = text(b, 12)
	b.label:SetPoint("LEFT")
	b.label:SetText(label)
	b:SetSize(b.label:GetStringWidth() + 2, 20)
	b:SetPoint("TOPLEFT", x, -58)
	b.line = rect(b, ACCENT[1], ACCENT[2], ACCENT[3], 1, "ARTWORK")
	b.line:SetHeight(2)
	b.line:SetPoint("BOTTOMLEFT", 0, -3)
	b.line:SetPoint("BOTTOMRIGHT", 0, -3)
	b.key = key
	b:SetScript("OnClick", function()
		mode = key
		UI.Refresh()
	end)
	return b
end

-- A flat text box that matches the window, with grey placeholder text.
local function makeInput(parent, width, placeholder, maxLetters)
	local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	eb:SetSize(width, 20)
	eb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	eb:SetBackdropColor(1, 1, 1, 0.04)
	eb:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.8)
	eb:SetFont(FONT, 11, "OUTLINE")
	eb:SetTextColor(unpack(TEXT))
	eb:SetTextInsets(6, 6, 0, 0)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(maxLetters)
	eb.hint = text(eb, 11, MUTED)
	eb.hint:SetPoint("LEFT", 6, 0)
	eb.hint:SetText(placeholder)
	eb:SetScript("OnTextChanged", function(self)
		self.hint:SetShown(self:GetText() == "")
	end)
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	eb:SetScript("OnEditFocusGained", function(self)
		self:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	end)
	eb:SetScript("OnEditFocusLost", function(self)
		self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.8)
	end)
	return eb
end

local function postFromForm()
	local target, reward = form.target:GetText(), form.reward:GetText()
	if target == "" then
		local okP, isPlayer = pcall(UnitIsPlayer, "target")
		if okP and not SG.secret(isPlayer) and isPlayer == true then
			target = SG.unitFullName("target") or ""
		end
	end
	local ok, err = ns.Bounty.Post(target, reward)
	if ok then
		form.target:SetText("")
		form.reward:SetText("")
		form.target:ClearFocus()
		form.reward:ClearFocus()
	else
		SG.print(err)
	end
end

-- Commands view: the slash commands people actually use, one line each.
local HELP = {
	{ "/gnomes", "Open this window" },
	{ "/gnomes stats", "Your title and numbers" },
	{ "/gnomes status", "Check it's working" },
	{ "/gnomes points", "How weekly points work" },
	{ "/gnomes gank", "Gank mode on or off" },
	{ "   Party member", "Their target" },
	{ "   Guild member · 2m", "Seen in your zone" },
	{ "/gnomes settings", "Size, opacity, switches" },
	{ "/gnomes spies", "List suspected spies" },
	{ "/gnomes spy Name 50g", "Report one (officers)" },
	{ "/gnomes spy cancel Name", "Withdraw yours" },
	{ "/gnomes sync", "Refresh from guild" },
	{ "/gnomes version", "Check for updates" },
	{ "/gnomes test", "Preview the kill popup" },
	{ "/gnomes check", "Self-test" },
}
local helpPanel, lastMode

local function buildHelp()
	helpPanel = CreateFrame("Frame", nil, frame)
	helpPanel:SetPoint("TOPLEFT", PAD, -92)
	helpPanel:SetPoint("BOTTOMRIGHT", -PAD, 40)
	for i, row in ipairs(HELP) do
		local y = -(i - 1) * 17
		local cmd = text(helpPanel, 11, ACCENT)
		cmd:SetPoint("TOPLEFT", 0, y)
		cmd:SetWidth(162)
		cmd:SetText(row[1])
		local desc = text(helpPanel, 10, MUTED)
		desc:SetPoint("TOPLEFT", 166, y - 1)
		desc:SetPoint("RIGHT", helpPanel, "RIGHT", 0, 0)
		desc:SetText(row[2])
	end
	helpPanel:Hide()
end

---------------------------------------------------------------------------
-- Settings view
---------------------------------------------------------------------------

local settingsPanel

-- Window size and background opacity, for this window and the gank panel.
function UI.ApplyLook()
	if not frame then
		return
	end
	local s = SG.db.settings
	frame:SetScale(s.scale or 1)
	frame:SetBackdropColor(0.06, 0.06, 0.07, s.opacity or 0.98)
	if ns.Gank and ns.Gank.ApplyLook then
		ns.Gank.ApplyLook()
	end
end

local function flatButton(parent, w, label)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, 20)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.25)
	b:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
	b.label = text(b, 11, TEXT, "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.6)
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.25)
	end)
	return b
end

local function buildSettings()
	settingsPanel = CreateFrame("Frame", nil, frame)
	settingsPanel:SetPoint("TOPLEFT", PAD, -94)
	settingsPanel:SetPoint("BOTTOMRIGHT", -PAD, 40)
	local width = W - PAD * 2
	local y = 0
	local updaters = {}

	local function label(title, note)
		local l = text(settingsPanel, 12, TEXT)
		l:SetPoint("TOPLEFT", 0, y)
		l:SetText(title)
		if note then
			local n = text(settingsPanel, 10, MUTED)
			n:SetPoint("TOPLEFT", 0, y - 15)
			n:SetWidth(150)
			n:SetText(note)
		end
	end

	-- [-] value [+]
	local function stepper(title, note, get, set, step, min, max, fmt)
		label(title, note)
		local value = text(settingsPanel, 12, TEXT, "CENTER")
		local plus = flatButton(settingsPanel, 22, "+")
		plus:SetPoint("TOPRIGHT", 0, y + 2)
		value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
		value:SetWidth(42)
		local minus = flatButton(settingsPanel, 22, "-")
		minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
		local function change(delta)
			local v = math.floor((get() + delta) * 100 + 0.5) / 100
			set(math.max(min, math.min(max, v)))
			UI.ApplyLook()
			UI.Refresh()
		end
		minus:SetScript("OnClick", function() change(-step) end)
		plus:SetScript("OnClick", function() change(step) end)
		updaters[#updaters + 1] = function()
			value:SetText(fmt(get()))
		end
		y = y - 31 -- 8 settings fit the window
	end

	-- On / Off
	local function toggle(title, note, get, set)
		label(title, note)
		local b = flatButton(settingsPanel, 50, "")
		b:SetPoint("TOPRIGHT", 0, y + 2)
		b:SetScript("OnClick", function()
			set(not get())
			UI.Refresh()
		end)
		updaters[#updaters + 1] = function()
			local on = get()
			b.label:SetText(on and "On" or "Off")
			b.label:SetTextColor(unpack(on and ACCENT or MUTED))
		end
		y = y - 31 -- 8 settings fit the window
	end

	-- A button showing the current choice; clicking steps to the next one.
	local function cycler(title, note, current, step)
		label(title, note)
		local b = flatButton(settingsPanel, 50, "")
		b:SetPoint("TOPRIGHT", 0, y + 2)
		b:SetScript("OnClick", function()
			step()
			UI.Refresh()
		end)
		updaters[#updaters + 1] = function()
			local v = current()
			b.label:SetText(v)
			b.label:SetTextColor(unpack(v == "Off" and MUTED or ACCENT))
		end
		y = y - 31 -- 8 settings fit the window
	end

	local s = function() return SG.db.settings end
	local pct = function(v) return math.floor(v * 100 + 0.5) .. "%" end

	stepper("Window size", "This window and the gank panel",
		function() return s().scale or 1 end, function(v) s().scale = v end, 0.1, 0.7, 1.5, pct)
	stepper("Background opacity", "Text stays fully visible",
		function() return s().opacity or 0.98 end, function(v) s().opacity = v end, 0.1, 0, 1, pct)
	toggle("Gank mode", "Call out gnomes, click to target",
		function() return s().gank == true end, function(v) ns.Gank.Toggle(v) end)
	toggle("Guild spots", "Gnomes guildmates here spot",
		function() return s().gankGuild ~= false end, function(v) ns.Gank.SetGuildSpots(v) end)
	cycler("Callout sound", "Click to hear the next one",
		function() return (ns.Gank.SoundChoice()).label end, function() ns.Gank.CycleSound() end)
	toggle("Popups", "Kills, promotions and callouts",
		function() return s().toast ~= false end, function(v) s().toast = v end)
	toggle("Login standings", "Top 3 in chat when you log in",
		function() return s().loginStandings ~= false end, function(v) s().loginStandings = v end)
	toggle("Minimap button", nil,
		function() return not (s().minimap and s().minimap.hide) end, function(v) UI.SetMinimap(v) end)

	settingsPanel.update = function()
		for _, fn in ipairs(updaters) do
			fn()
		end
	end
	settingsPanel:Hide()
end

local function buildForm()
	form = CreateFrame("Frame", nil, frame)
	form:SetSize(W - PAD * 2, 22)
	form:SetPoint("TOPLEFT", PAD, -106 - RECALL_ROWS * ROW_H - 4)
	form.target = makeInput(form, 104, "Name (or target)", 40)
	form.target:SetPoint("LEFT", 0, 0)
	form.reward = makeInput(form, 104, "Reward", 30)
	form.reward:SetPoint("LEFT", form.target, "RIGHT", 6, 0)

	local post = CreateFrame("Button", nil, form, "BackdropTemplate")
	post:SetSize(W - PAD * 2 - 104 * 2 - 12, 20)
	post:SetPoint("RIGHT", 0, 0)
	post:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	post:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.35)
	post:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
	post.label = text(post, 11, TEXT, "CENTER")
	post.label:SetPoint("CENTER")
	post.label:SetText("Report")
	post:SetScript("OnEnter", function(self)
		self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.7)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Report a corporate spy", 1, 1, 1)
		GameTooltip:AddLine("Leave the name empty to use your current target.", MUTED[1], MUTED[2], MUTED[3])
		GameTooltip:AddLine("The first employee to take them out collects.", MUTED[1], MUTED[2], MUTED[3])
		GameTooltip:Show()
	end)
	post:SetScript("OnLeave", function(self)
		self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.35)
		GameTooltip:Hide()
	end)
	post:SetScript("OnClick", postFromForm)
	form.target:SetScript("OnEnterPressed", function()
		form.reward:SetFocus()
	end)
	form.reward:SetScript("OnEnterPressed", postFromForm)
	form.target:SetScript("OnTabPressed", function()
		form.reward:SetFocus()
	end)
	form:Hide()
end

local function build()
	frame = CreateFrame("Frame", "SmokingGnomesFrame", UIParent, "BackdropTemplate")
	frame:SetSize(W, 104 + (ROWS + 1) * ROW_H + 66)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.06, 0.06, 0.07, 0.98)
	frame:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
	frame:Hide()
	tinsert(UISpecialFrames, "SmokingGnomesFrame") -- Escape closes it

	local pos = SG.db.settings.pos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER", 0, 60)
	end

	local logo = makeCrest(frame, 34)
	logo:SetPoint("TOPLEFT", PAD - 2, -10)

	local title = text(frame, 14, TEXT)
	title:SetPoint("TOPLEFT", PAD + 40, -13)
	title:SetText("Smoking Gnomes Inc.")

	local close = CreateFrame("Button", nil, frame)
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -8, -10)
	close.x = text(close, 16, MUTED, "CENTER")
	close.x:SetPoint("CENTER")
	close.x:SetText("×")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	close:SetScript("OnEnter", function(self)
		self.x:SetTextColor(unpack(TEXT))
	end)
	close:SetScript("OnLeave", function(self)
		self.x:SetTextColor(unpack(MUTED))
	end)

	-- "?" toggles the Commands view; clicking it again goes back to the last tab.
	local helpBtn = CreateFrame("Button", nil, frame)
	helpBtn:SetSize(20, 20)
	helpBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
	helpBtn.q = text(helpBtn, 13, MUTED, "CENTER")
	helpBtn.q:SetPoint("CENTER")
	helpBtn.q:SetText("?")
	helpBtn:SetScript("OnClick", function()
		UI.ShowView("help", mode ~= "help")
	end)
	helpBtn:SetScript("OnEnter", function(self)
		self.q:SetTextColor(unpack(TEXT))
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Commands", 1, 1, 1)
		GameTooltip:Show()
	end)
	helpBtn:SetScript("OnLeave", function(self)
		self.q:SetTextColor(unpack(MUTED))
		GameTooltip:Hide()
	end)
	frame.helpBtn = helpBtn

	-- Cog: the Settings view (size, opacity, gank mode and other switches).
	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(20, 20)
	gear:SetPoint("RIGHT", helpBtn, "LEFT", -2, 0)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	gear.icon:SetTexture("Interface\\AddOns\\SmokingGnomes\\Media\\gear")
	gear.icon:SetSize(13, 13)
	gear.icon:SetPoint("CENTER")
	gear.icon:SetVertexColor(unpack(MUTED))
	gear:SetScript("OnClick", function()
		UI.ShowView("settings", mode ~= "settings")
	end)
	gear:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(unpack(TEXT))
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Settings", 1, 1, 1)
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(unpack(mode == "settings" and ACCENT or MUTED))
		GameTooltip:Hide()
	end)
	frame.gear = gear

	sub = text(frame, 11, MUTED)
	sub:SetPoint("TOPLEFT", PAD + 40, -31)
	sub:SetPoint("RIGHT", -PAD, 0)

	local GAP = 14
	tabs = { makeTab("Weekly", "week", PAD) }
	local x = PAD + tabs[1]:GetWidth() + GAP
	tabs[2] = makeTab("Lifetime", "all", x)
	x = x + tabs[2]:GetWidth() + GAP
	tabs[3] = makeTab("Spies", "recall", x)
	x = x + tabs[3]:GetWidth() + GAP
	tabs[4] = makeTab("Lab Log", "mine", x)

	local div = rect(frame, BORDER[1], BORDER[2], BORDER[3], 0.6, "ARTWORK")
	div:SetHeight(1)
	div:SetPoint("TOPLEFT", PAD, -82)
	div:SetPoint("TOPRIGHT", -PAD, -82)

	colHeads = CreateFrame("Frame", nil, frame)
	colHeads:SetSize(W - PAD * 2, 14)
	colHeads:SetPoint("TOPLEFT", PAD, -88)
	colHeads.name = text(colHeads, 10, MUTED)
	colHeads.name:SetPoint("LEFT", 28, 0)
	colHeads.assists = text(colHeads, 10, MUTED, "RIGHT")
	colHeads.assists:SetPoint("RIGHT", 0, 0)
	colHeads.kills = text(colHeads, 10, MUTED, "RIGHT")

	rows = {}
	for i = 1, ROWS + 1 do
		local r = makeRow()
		local y = -106 - (i - 1) * ROW_H - (i > ROWS and 6 or 0)
		r:SetPoint("TOPLEFT", PAD, y)
		rows[i] = r
	end

	buildForm()
	buildHelp()
	buildSettings()

	empty = text(frame, 12, MUTED, "CENTER")
	empty:SetPoint("TOP", 0, -150)
	empty:SetWidth(W - PAD * 4)
	empty:SetWordWrap(true)

	local div2 = rect(frame, BORDER[1], BORDER[2], BORDER[3], 0.6, "ARTWORK")
	div2:SetHeight(1)
	div2:SetPoint("BOTTOMLEFT", PAD, 50)
	div2:SetPoint("BOTTOMRIGHT", -PAD, 50)

	footer = text(frame, 11, TEXT)
	footer:SetPoint("BOTTOMLEFT", PAD, 30)
	footerRight = text(frame, 11, MUTED, "RIGHT")
	footerRight:SetPoint("BOTTOMRIGHT", -PAD, 30)

	-- The whole company's output this week, on every view.
	companyLine = text(frame, 10, MUTED, "CENTER")
	companyLine:SetPoint("BOTTOM", 0, 12)

	frame:SetScript("OnShow", UI.Refresh)
end

local function setHeads(name, kills, assists, killsRight)
	colHeads.name:SetText(name)
	colHeads.kills:SetText(kills)
	colHeads.assists:SetText(assists)
	colHeads.kills:ClearAllPoints()
	colHeads.kills:SetPoint("RIGHT", killsRight, 0)
end

local function displayName(name)
	local short = SG.shortName(name)
	if name == champion then
		return STAR .. " " .. short
	end
	return short
end

---------------------------------------------------------------------------
-- Boards
---------------------------------------------------------------------------

local function setRow(r, rank, name, kills, assists, e, isMe)
	r:Show()
	r.hl:SetShown(isMe)
	r.rank:SetText(rank or "")
	r.name:SetText(displayName(name))
	r.name:SetTextColor(classColor(e and e.class))
	local active = e and math.max(e.seen or 0, e.u or 0) or 0
	local stale = e and not isMe and (SG.now() - active) > STALE_DAYS * 86400
	r.name:SetAlpha(stale and 0.5 or 1)
	r.kills:SetText(kills)
	r.assists:SetText(assists > 0 and assists or "")

	local title = SG.jobTitle(name, e and e.total)
	if name == champion then
		title = title .. "  ·  Employee of the Week"
	end
	local last = "No harvests yet"
	if e and e.lastVictim then
		last = ("Last harvest: %s, %s"):format(e.lastVictim, SG.ago(e.lastKill))
	elseif e and e.lastKill then
		last = "Last harvest " .. SG.ago(e.lastKill)
	end
	r.tipColor = ACCENT
	r.tip = { SG.shortName(name), title, last }
	local recalls = ns.Bounty.CompletedBy(name)
	if recalls > 0 then
		r.tip[#r.tip + 1] = ("Spies eliminated: %d"):format(recalls)
	end
	if isMe then
		r.tip[#r.tip + 1] = "That's you"
	elseif e and e.seen then
		r.tip[#r.tip + 1] = "Online " .. SG.ago(e.seen)
	else
		r.tip[#r.tip + 1] = "Heard through coworkers"
	end
	if e and (e.bad or 0) > 0 then
		r.tip[#r.tip + 1] = ("|cffd08050%d report(s) rejected as invalid|r"):format(e.bad)
	end
end

local function myCareer(e)
	local title, nextTitle, need = SG.jobTitle(SG.myName, e.total)
	if nextTitle then
		return title, ("%d to %s"):format(need, nextTitle)
	end
	return title, nil
end

-- Weekly ranks by points: the POINTS column replaces HARVESTED, gnomes move to the
-- second column, and assists go to the row tooltip.
local function boardRow(r, rank, row, isMe)
	if mode == "week" then
		setRow(r, rank, row.name, SG.points(row.points), row.kills, row.e, isMe)
		r.tip[#r.tip + 1] = ("This week: %d gnome%s, %s points%s"):format(row.kills, row.kills == 1 and "" or "s",
			SG.points(row.points), row.assists > 0 and (", " .. row.assists .. " assists") or "")
	else
		setRow(r, rank, row.name, row.kills, row.assists, row.e, isMe)
	end
end

local function refreshBoard()
	if mode == "week" then
		setHeads("EMPLOYEE", "POINTS", "GNOMES", -62)
	else
		setHeads("EMPLOYEE", "HARVESTED", "ASSISTS", -62)
	end
	local list = SG.ranked(mode)
	local myRank, shown = nil, 0
	for i, row in ipairs(list) do
		if row.name == SG.myName then
			myRank = i
		end
	end

	for i = 1, ROWS do
		local row = list[i]
		if row and (row.kills > 0 or row.assists > 0) then
			boardRow(rows[i], i, row, row.name == SG.myName)
			shown = shown + 1
		else
			rows[i]:Hide()
		end
	end

	-- Your own row under the top 10 when you're outside it.
	local me = rows[ROWS + 1]
	local mine = myRank and list[myRank]
	if mine and myRank > ROWS and (mine.kills > 0 or mine.assists > 0) then
		boardRow(me, myRank, mine, true)
	else
		me:Hide()
	end

	colHeads:SetShown(shown > 0)
	empty:SetShown(shown == 0)
	empty:SetText((mode == "week" and "No gnomes harvested this week." or "No gnomes harvested yet.")
		.. "\n\n|cff8c8c94Land the killing blow on a gnome\nin the open world to start production.|r")

	local e = SG.me()
	local title = myCareer(e)
	local count = mode == "week" and e.week or e.total
	if count > 0 and myRank then
		footer:SetText(("You: #%d  ·  |cff%s%s|r"):format(myRank, hex(ACCENT), title))
	else
		footer:SetText(("You: |cff%s%s|r"):format(hex(ACCENT), title))
	end
	footerRight:SetText("Resets in " .. SG.duration(SG.secondsUntilReset()))
end

---------------------------------------------------------------------------
-- Recalls tab
---------------------------------------------------------------------------

local function refreshRecalls()
	setHeads("SUSPECT", "REWARD", "STATUS", -70)
	rows[ROWS]:Hide()
	rows[ROWS + 1]:Hide()
	local officer = SG.IsOfficer(SG.myName) == true
	form:SetShown(officer)

	local list = ns.Bounty.List()
	local now = SG.now()
	for i = 1, RECALL_ROWS do
		local r, row = rows[i], list[i]
		if row then
			local b, state = row.b, row.state
			r:Show()
			r.hl:Hide()
			r.name:SetAlpha(1)
			r.name:SetText(b.target)
			r.tipColor = GOLD
			r.tip = { b.target, "Reward: " .. b.reward, ("Posted by %s, %s"):format(SG.shortName(b.poster), SG.ago(b.created)) }
			if state == "open" then
				r.rank:SetText(ICON_OPEN)
				r.name:SetTextColor(unpack(TEXT))
				r.kills:SetText(b.reward)
				r.kills:SetTextColor(unpack(GOLD))
				r.assists:SetText(SG.duration(b.expires - now) .. " left")
				r.tip[#r.tip + 1] = "Kill them in the open world to claim it."
				if b.poster == SG.myName then
					r.cancelTarget = b.target
					r.tip[#r.tip + 1] = "Shift + right-click to cancel."
				end
			else
				r.name:SetTextColor(unpack(MUTED))
				r.kills:SetText(b.reward)
				r.kills:SetTextColor(unpack(MUTED))
				if state == "claimed" then
					local c = row.claim
					r.rank:SetText(ICON_DONE)
					r.assists:SetText(SG.shortName(c.claimer))
					r.assists:SetTextColor(unpack(ACCENT))
					local where = (c.zone and c.zone ~= "") and (" in " .. c.zone) or ""
					r.tip[#r.tip + 1] = ("Eliminated by %s%s, %s"):format(SG.shortName(c.claimer), where, SG.ago(c.t))
				else
					r.rank:SetText(ICON_CLOSED)
					r.assists:SetText(state == "cancelled" and "withdrawn" or "expired")
				end
			end
		else
			r:Hide()
		end
	end

	colHeads:SetShown(#list > 0)
	empty:SetShown(#list == 0)
	empty:SetText("No corporate spies reported.\n\n|cff8c8c94We have a zero tolerance policy for\ncorporate espionage. If you are\nsuspected, it's on sight.|r")

	local open = ns.Bounty.OpenCount()
	footer:SetText(open == 1 and "1 spy at large" or (open .. " spies at large"))
	local mine = ns.Bounty.CompletedBy(SG.myName)
	footerRight:SetText(mine > 0 and ("You've eliminated " .. mine) or "")
end

---------------------------------------------------------------------------
-- Lab Log
---------------------------------------------------------------------------

local function refreshMine()
	setHeads("", "", "", -62)
	colHeads:Hide()
	rows[ROWS + 1]:Hide()
	local list = SG.db.recent[SG.myName] or {}
	for i = 1, ROWS do
		local k, r = list[i], rows[i]
		if k then
			r:Show()
			r.hl:Hide()
			r.rank:SetText("")
			r.name:SetText((k.name or "Unknown gnome") .. (k.test and " (test)" or ""))
			r.name:SetTextColor(unpack(k.assist and MUTED or TEXT))
			r.name:SetAlpha(1)
			r.tipColor = nil
			r.tip = { k.name or "Unknown gnome", k.zone or "Unknown zone", SG.ago(k.t) }
			if k.pts then
				r.tip[#r.tip + 1] = ("+%s points (level %s vs your %s)"):format(SG.points(k.pts),
					k.lvl and (k.lvl < 0 and "??" or k.lvl) or "unknown", k.myLvl or "?")
			end
			local v = not k.test and ns.Ledger.Victim(k.name, k.realm)
			if k.assist then
				r.kills:SetText("assist")
			elseif v and v.n > 1 then
				r.kills:SetText(v.n .. "×")
				r.tip[#r.tip + 1] = ("Smoked by the company %d×"):format(v.n)
			else
				r.kills:SetText("")
			end
			r.kills:SetTextColor(unpack(MUTED))
			r.assists:SetText(SG.ago(k.t))
		else
			r:Hide()
		end
	end
	empty:SetShown(#list == 0)
	empty:SetText("Your harvests will be logged here.")
	local e = SG.me()
	local title, progress = myCareer(e)
	footer:SetText(("|cff%s%s|r"):format(hex(ACCENT), title))
	footerRight:SetText(progress or ("%d lifetime"):format(e.total))
end

function UI.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	champion = SG.lastWeekWinner()
	UI.RefreshCrests() -- tabard data can arrive after login

	-- Gnomes harvested by all employees this week (everyone running the addon).
	local cur, company = SG.weekId(), 0
	for _, e in pairs(SG.db.players) do
		company = company + (SG.weekCounts(e, cur))
	end
	companyLine:SetText(("Employees harvested |cff%s%d|r gnome%s this week"):format(hex(GOLD), company, company == 1 and "" or "s"))
	for _, t in ipairs(tabs) do
		local active = t.key == mode
		t.label:SetTextColor(unpack(active and TEXT or MUTED))
		t.line:SetShown(active)
	end
	local recall = mode == "recall"
	for i = 1, ROWS + 1 do
		layoutRow(rows[i], recall)
		rows[i].kills:SetTextColor(unpack(TEXT))
		rows[i].assists:SetTextColor(unpack(MUTED))
	end
	if not recall then
		form:Hide()
	end

	if champion then
		local _, pts = SG.lastWeekWinner()
		sub:SetText(("%s Employee of the Week: |cff%s%s|r (%s pts)"):format(STAR, hex(GOLD), SG.shortName(champion), pts))
	else
		sub:SetText("Production Report")
	end

	local help, settings = mode == "help", mode == "settings"
	helpPanel:SetShown(help)
	settingsPanel:SetShown(settings)
	frame.helpBtn.q:SetTextColor(unpack(help and ACCENT or MUTED))
	frame.gear.icon:SetVertexColor(unpack(settings and ACCENT or MUTED))
	if help or settings then
		for i = 1, ROWS + 1 do
			rows[i]:Hide()
		end
		colHeads:Hide()
		empty:Hide()
		if settings then
			settingsPanel.update()
			footer:SetText("Saved for all your characters")
		else
			footer:SetText("Type /gnomes help for the full list")
		end
		footerRight:SetText(SG.RELEASE == "dev" and "" or ("v" .. SG.RELEASE))
	elseif recall then
		refreshRecalls()
	elseif mode == "mine" then
		refreshMine()
	else
		refreshBoard()
	end
end

function UI.Toggle()
	if not frame then
		return
	end
	frame:SetShown(not frame:IsShown())
end

-- Open the window on the Commands or Settings view (show = true), or go back to the
-- last tab.
function UI.ShowView(view, show)
	if not frame then
		return
	end
	if show then
		if mode ~= "help" and mode ~= "settings" then
			lastMode = mode
		end
		mode = view
	else
		mode = lastMode or "week"
	end
	frame:Show()
	UI.Refresh()
end

function UI.ShowHelp(show)
	UI.ShowView("help", show)
end

---------------------------------------------------------------------------
-- Popups: small, centred, fade out.
---------------------------------------------------------------------------

local toast

local function buildToast()
	toast = CreateFrame("Frame", nil, UIParent)
	toast:SetSize(400, 60)
	toast:SetPoint("TOP", 0, -90)
	toast:SetFrameStrata("HIGH")
	toast:Hide()
	toast.main = text(toast, 20, TEXT, "CENTER")
	toast.main:SetPoint("TOP", 18, 0)
	toast.logo = makeCrest(toast, 36)
	toast.logo:SetPoint("RIGHT", toast.main, "LEFT", -10, -8)
	toast.sub = text(toast, 12, MUTED, "CENTER")
	toast.sub:SetPoint("TOP", toast.main, "BOTTOM", 0, -4)
	toast.note = text(toast, 11, MUTED, "CENTER")
	toast.note:SetPoint("TOP", toast.sub, "BOTTOM", 0, -3)
	toast.note:SetAlpha(0.75)

	local ag = toast:CreateAnimationGroup()
	local fadeIn = ag:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.2)
	fadeIn:SetOrder(1)
	local fadeOut = ag:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(3.5)
	fadeOut:SetDuration(0.6)
	fadeOut:SetOrder(2)
	ag:SetScript("OnFinished", function()
		toast:Hide()
	end)
	toast.anim = ag
end

-- A popup with a title, one detail line and an optional note. color: red, gold, green, white.
function UI.Notice(main, color, subText, note)
	if not SG.db.settings.toast then
		return
	end
	if not toast then
		buildToast()
	end
	toast.main:SetText(main)
	toast.main:SetTextColor(unpack(COLORS[color] or TEXT))
	toast.sub:SetText(subText or "")
	toast.note:SetText(note or "")
	toast.anim:Stop()
	toast:Show()
	toast.anim:Play()
end

function UI.Toast(e, info)
	local parts = { info.victim or "Unknown gnome" }
	if info.zone then
		parts[#parts + 1] = info.zone
	end
	local main, color, note
	if info.promoted then
		main, color = "Promoted: " .. info.promoted, "gold"
		note = ("%d gnomes harvested. HR has been notified."):format(e.total)
	elseif info.assist then
		main, color, note = "Gnome assist", "white", "Sample sent to the lab."
	else
		main, color = "Gnome smoked!", "green"
		if info.points then
			parts[#parts + 1] = "+" .. SG.points(info.points) .. " pts"
		end
		parts[#parts + 1] = e.week .. " this week"
		note = LAB_NOTES[math.random(#LAB_NOTES)]
	end
	UI.Notice(main, color, table.concat(parts, "  ·  ") .. (info.test and "  (test)" or ""), note)
end

---------------------------------------------------------------------------
-- Player tooltips: coworkers show their job title to everyone running the addon.
---------------------------------------------------------------------------

-- /gnomes tipdebug prints what the hook sees for the next few unit tooltips.
local tipDebug = 0
function UI.TipDebug()
	tipDebug = 5
	SG.print("Hover over 5 players (yourself included). I'll print what the tooltip hook sees.")
end
local function dbg(fmt, ...)
	if tipDebug > 0 then
		SG.print("tooltip: " .. fmt:format(...))
	end
end

-- Forever can hand addons a locked ("secret") tooltip data table, especially for
-- players. Reading a field of one errors, so check first (as Questie does).
local function publicTable(v)
	if type(v) ~= "table" or SG.secret(v) then
		return false
	end
	if type(issecrettable) == "function" then
		local ok, locked = pcall(issecrettable, v)
		if not ok or locked == true then
			return false
		end
	end
	return true
end

local function guidOfUnit(unit)
	local ok, g = pcall(UnitGUID, unit)
	return ok and SG.str(g) or nil
end

-- Find out which player a tooltip is about, trying in turn: the tooltip's data, the
-- unit under the mouse (also set when hovering a unit frame), and the tooltip's unit.
local function tooltipPlayer(tt, data)
	local guid, source
	if publicTable(data) then
		local ok, g = pcall(function() return data.guid end)
		guid = ok and SG.str(g) or nil
		source = guid and "data"
	end
	if not guid then
		guid = guidOfUnit("mouseover")
		source = guid and "mouseover"
	end
	local unit
	local okU, _, u = pcall(tt.GetUnit, tt)
	unit = okU and SG.str(u) or nil
	if not guid and unit then
		guid = guidOfUnit(unit)
		source = guid and "unit"
	end
	dbg("guid from %s", tostring(source))
	-- GetPlayerInfoByGUID gives the full name ("Legs Dogman"); UnitName gives the
	-- first name and, on Forever, the surname as its second value.
	local name
	if guid and guid:match("^Player%-") then
		local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, guid)
		name = ok and SG.fullName(n) or nil
	end
	if not name and unit then
		local okP, isPlayer = pcall(UnitIsPlayer, unit)
		if okP and not SG.secret(isPlayer) and isPlayer == true then
			name = SG.unitFullName(unit)
		end
	end
	dbg("unit=%s guid=%s name=%s", tostring(unit), tostring(guid and guid:sub(1, 14)), tostring(name))
	if not name then
		return nil
	end
	return name, name, nil
end

local function onUnitTooltip(tt, data)
	if not SG.db or not SG.myName or not tt or not tt.AddLine then
		return
	end
	local full, vName, vRealm = tooltipPlayer(tt, data)
	if tipDebug > 0 then
		dbg("player=%s known=%s (hook: %s)", tostring(full), tostring(full and SG.db.players[full] ~= nil), tostring(SG.tooltipHook))
		tipDebug = tipDebug - 1
	end
	if not full then
		return
	end
	-- Victims: how often the company has smoked this player.
	local v = ns.Ledger.Victim(vName, vRealm)
	if v and v.n > 0 then
		tt:AddLine(("Smoked by the company: %d×"):format(v.n), ACCENT[1], ACCENT[2], ACCENT[3])
		local label = ns.Ledger.Label(v.n)
		local top, topN = ns.Ledger.TopKiller(v)
		local detail = {}
		if label then
			detail[#detail + 1] = label
		end
		if top and topN > 1 then
			detail[#detail + 1] = ("mostly %s (%d)"):format(SG.shortName(top), topN)
		elseif v.lastBy then
			detail[#detail + 1] = ("last by %s, %s"):format(SG.shortName(v.lastBy), SG.ago(v.last))
		end
		if #detail > 0 then
			tt:AddLine(table.concat(detail, "  ·  "), MUTED[1], MUTED[2], MUTED[3])
		end
	end
	local e = SG.db.players[full]
	if e then
		tt:AddLine(SG.jobTitle(full, e.total) .. " at Smoking Gnomes Inc.", ACCENT[1], ACCENT[2], ACCENT[3])
		if full == SG.lastWeekWinner() then
			tt:AddLine(STAR .. " Employee of the Week", GOLD[1], GOLD[2], GOLD[3])
		end
	end
	-- Players reported as corporate spies.
	for _, row in ipairs(ns.Bounty.List()) do
		if row.state == "open" then
			if SG.sameName(row.b.target, full) then
				tt:AddLine(ICON_OPEN .. " Corporate spy  ·  " .. row.b.reward, RED[1], RED[2], RED[3])
				break
			end
		end
	end
	pcall(tt.Show, tt) -- resize to fit the added lines
end

local function hookTooltips()
	local hooked = false
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt, data)
			local ok, err = pcall(onUnitTooltip, tt, data)
			if not ok then
				dbg("error: %s", tostring(err))
			end
		end)
	end
	if not hooked and GameTooltip:HasScript("OnTooltipSetUnit") then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
			pcall(onUnitTooltip, tt)
		end)
	end
	SG.tooltipHook = hooked and "TooltipDataProcessor" or "OnTooltipSetUnit"
end

---------------------------------------------------------------------------
-- Init and AddOn compartment
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Minimap button: left-click opens the window, right-click the command list,
-- drag to move it around the minimap edge.
---------------------------------------------------------------------------

local minimapButton

local function placeMinimapButton()
	local s = SG.db.settings.minimap
	local angle = math.rad(s.angle or 200)
	local radius = (Minimap:GetWidth() / 2) + 5
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function buildMinimapButton()
	local s = SG.db.settings
	s.minimap = s.minimap or { angle = 200 }
	local b = CreateFrame("Button", "SmokingGnomesMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- Same geometry as LibDBIcon: the modern client centres everything in a 50px ring,
	-- the Classic client uses offsets in a 53px ring.
	local modern = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(LOGO)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	if modern then
		border:SetSize(50, 50)
		bg:SetSize(24, 24)
		bg:SetPoint("CENTER")
		icon:SetSize(21, 21)
		icon:SetPoint("CENTER")
	else
		border:SetSize(53, 53)
		bg:SetSize(20, 20)
		bg:SetPoint("TOPLEFT", 7, -5)
		icon:SetSize(19, 19)
		icon:SetPoint("TOPLEFT", 6, -6)
	end

	b:SetScript("OnClick", function(_, button)
		if button == "LeftButton" and IsShiftKeyDown() then
			ns.Gank.Toggle()
		elseif button == "RightButton" then
			UI.ShowHelp(true)
		else
			UI.Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			cx, cy = cx / scale, cy / scale
			SG.db.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
			placeMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	b:SetScript("OnEnter", function(self)
		SmokingGnomes_OnAddonCompartmentEnter(nil, self)
		GameTooltip:AddLine(("Gank mode: %s"):format(SG.db.settings.gank and "on" or "off"), ACCENT[1], ACCENT[2], ACCENT[3])
		GameTooltip:AddLine("Shift-click: gank mode. Right-click: commands. Drag to move.", MUTED[1], MUTED[2], MUTED[3])
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	minimapButton = b
	placeMinimapButton()
	b:SetShown(not s.minimap.hide)
end

function UI.SetMinimap(show)
	local s = SG.db.settings.minimap
	s.hide = not show
	minimapButton:SetShown(show)
end

function UI.ToggleMinimap()
	local s = SG.db.settings.minimap
	UI.SetMinimap(s.hide == true)
	SG.print(s.hide and "Minimap button hidden. /gnomes minimap brings it back." or "Minimap button shown.")
end

function UI.Init()
	if not frame then
		build()
		hookTooltips()
		buildMinimapButton()
		UI.ApplyLook()
	end
end

function SmokingGnomes_OnAddonCompartmentClick()
	UI.Toggle()
end

function SmokingGnomes_OnAddonCompartmentEnter(_, button)
	local e = SG.me()
	GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine("Smoking Gnomes Inc.", 1, 1, 1)
	GameTooltip:AddLine(("%s  ·  %d this week (%s pts)"):format(SG.jobTitle(SG.myName, e.total), e.week, SG.points(e.wp)), ACCENT[1], ACCENT[2], ACCENT[3])
	local open = ns.Bounty.OpenCount()
	if open > 0 then
		GameTooltip:AddLine(open == 1 and "1 corporate spy at large" or (open .. " corporate spies at large"), RED[1], RED[2], RED[3])
	end
	if SG.latestRelease and SG.newer(SG.latestRelease, SG.RELEASE) then
		GameTooltip:AddLine(("Update available: %s"):format(SG.latestRelease), GOLD[1], GOLD[2], GOLD[3])
	end
	GameTooltip:AddLine("Click to open the Production Report", MUTED[1], MUTED[2], MUTED[3])
	GameTooltip:Show()
end

function SmokingGnomes_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
