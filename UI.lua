-- Smoking Gnomes Inc.: Production Report window, popups, player tooltips,
-- AddOn compartment button.

local _, ns = ...
local SG = ns.SG

local UI = {}
ns.UI = UI

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
-- Window: a game-style frame (dark wood, gold trim, the crest over the top-left
-- corner) around a dark page. Tabs hang below
-- the frame. Payroll, Settings and Commands open from the header and have their own
-- Done / Back button. Layout, colours and every page: docs/UI-REDESIGN.md.
---------------------------------------------------------------------------

local W, H = 308, 460 -- H is the starting height; the window then fits the page
local MIN_H = 360          -- never shorter: a board of 3 still has some room under it
local TITLE_H = 36
local HEAD_GAP = 9                 -- trim (4 px in) + 5 px: header buttons sit this far from the top and right
local HEAD_Y = HEAD_GAP + 11       -- the middle of the header buttons
local INSET = 6                    -- the page sits this far inside the frame
local PAD = 18                     -- page margin: everything on the page lines up on it
local CW = W - INSET * 2 - PAD * 2 -- content width
local ROW_H, ROW2_H, CASE_H = 24, 34, 38
local PAGE_ROWS = 8                -- rows shown before a list scrolls
local CASE_ROWS = 5                -- Spies: other cases shown before scrolling
local MAX_ROWS = PAGE_ROWS + 1     -- + your own row, pinned when it's off the page
-- Built-in fonts only: WoW Forever won't load font files from addons (tested 28 Nov 2026:
-- SetFont returns false for ours and for Details' and Plater's alike).
local NARROW = "Fonts\\ARIALN.TTF"  -- numbers and small print
local NUM, NUM_BOLD = NARROW, NARROW
local PORTRAIT = "Interface\\CHARACTERFRAME\\TempPortrait"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local STAR_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

-- The frame is the same in both themes.
local WOOD = { 0.102, 0.075, 0.043 }
local WOOD_EDGE = { 0.290, 0.208, 0.125 }
local TRIM = { 0.722, 0.569, 0.247 }
local TITLE_GOLD = { 1.0, 0.82, 0.0 }

local THEMES = {
	dark = {
		paper = { 0.122, 0.102, 0.078 },
		ink = { 0.918, 0.875, 0.784 },
		muted = { 0.659, 0.596, 0.471 },
		accent = { 0.435, 0.749, 0.525 },
		red = { 0.878, 0.439, 0.373 },
		gold = { 1.0, 0.82, 0.0 },
		rule = { 0.918, 0.875, 0.784 },
		soft = 0.10, hard = 0.45, track = 0.12, wash = 0.05,
		me = { 1.0, 0.82, 0.0, 0.10 },
		hover = { 0.918, 0.875, 0.784, 0.07 },
		bandBg = { 1.0, 0.82, 0.0, 0.07 }, bandEdge = { 1.0, 0.82, 0.0, 0.28 },
		medals = { { 0.878, 0.702, 0.255 }, { 0.722, 0.737, 0.761 }, { 0.773, 0.541, 0.333 } },
		tabOn = { 0.180, 0.141, 0.086 }, tabOnText = { 1.0, 0.82, 0.0 },
		classNames = true, -- names in class colours
		shadow = 0.6,
	},
}
local T = THEMES.dark

local frame, paper, tabs, rows, coin, gear
local heading, headPill, headRight, actionBtn, subtitle
local band, heads, dash, card, strip, careerBox, stats, statsNote, footL, footR, empty, form
local settingsPanel, helpPanel, commandsBtn, welcome
local mode = "week"
local boardPeriod = "week" -- the Production Report's switch: "week" or "all"
local periodSwitch
local lastMode
local champion -- last week's winner, refreshed with the window
local offsets = {} -- first row shown, per page (mouse-wheel scrolling)
local pageTotal, pageVisible = 0, PAGE_ROWS
local cursor = 0   -- layout: next free y on the page

-- Parts that follow the theme repaint themselves through these.
local themers = {}
local withdrawButton -- defined with the Spies helpers below
local function themed(fn)
	themers[#themers + 1] = fn
end

-- Page text: plain (no outline), colour by theme role ("ink", "muted", ...).
local function ptext(parent, size, role, justify, font)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs.font, fs.size, fs.role = font or FONT, size, role
	fs:SetFont(fs.font, size, "")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	themed(function()
		if T.shadow > 0 then
			fs:SetShadowColor(0, 0, 0, T.shadow)
			fs:SetShadowOffset(1, -1)
		else
			fs:SetShadowOffset(0, 0)
		end
		if fs.role then
			local c = T[fs.role]
			fs:SetTextColor(c[1], c[2], c[3])
		end
	end)
	return fs
end

local function ink(fs, role, alpha)
	local c = T[role]
	fs:SetTextColor(c[1], c[2], c[3], alpha or 1)
end

local function solid(parent, layer, sub)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
	t:SetTexture(WHITE)
	return t
end

local function tint(t, c, a)
	t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
end

-- A soft fade from alpha a1 to a2 ("HORIZONTAL": left to right, "VERTICAL": bottom to
-- top). Hidden if this client lacks gradients, so nothing ever looks broken.
local function fade(t, orientation, c, a1, a2)
	local ok = pcall(function()
		t:SetVertexColor(1, 1, 1, 1)
		t:SetGradient(orientation, CreateColor(c[1], c[2], c[3], a1), CreateColor(c[1], c[2], c[3], a2))
	end)
	t:SetShown(ok)
	return ok
end

local function disc(parent, size, layer, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
	t:SetTexture(CIRCLE)
	t:SetSize(size, size)
	return t
end

-- A hairline in the theme's rule colour: "soft" between rows, "hard" under headers.
local function rule(parent, weight)
	local t = solid(parent, "BORDER")
	t:SetHeight(1)
	themed(function()
		tint(t, T.rule, T[weight or "soft"])
	end)
	return t
end

-- Full names, never cut: shrink up to three sizes before the game would truncate.
local function fitText(fs, s, maxW)
	fs:SetFont(fs.font, fs.size, "")
	fs:SetWidth(0)
	fs:SetText(s or "")
	local size = fs.size
	while size > fs.size - 3 and fs:GetStringWidth() > maxW do
		size = size - 1
		fs:SetFont(fs.font, size, "")
	end
	fs:SetWidth(math.min(math.ceil(fs:GetStringWidth()) + 1, maxW))
end

-- A thin progress bar. SetValue takes the share done and the bar's width.
local function makeBar(parent, h)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(h)
	bar.bg = solid(bar, "BORDER")
	bar.bg:SetAllPoints()
	bar.fill = solid(bar, "ARTWORK")
	bar.fill:SetPoint("TOPLEFT")
	bar.fill:SetPoint("BOTTOMLEFT")
	themed(function()
		tint(bar.bg, T.ink, T.track)
		tint(bar.fill, T.accent)
	end)
	function bar:SetValue(share, width)
		share = math.max(0, math.min(1, share or 0))
		self.fill:SetWidth(math.max(1, width * share))
		self.fill:SetShown(share > 0)
	end
	return bar
end

-- A small bordered button on the page (DONE, REPORT, SLASH COMMANDS).
local function pageButton(parent, label, role)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetHeight(20)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b.role = role or "ink"
	b.label = ptext(b, 10, b.role, "CENTER", NUM)
	b.label:SetPoint("CENTER", 0, 0)
	function b:SetLabel(s)
		self.label:SetText(s)
		self:SetWidth(math.ceil(self.label:GetStringWidth()) + 20)
	end
	function b:Paint()
		local c = T[self.role]
		self:SetBackdropColor(c[1], c[2], c[3], self.hover and 0.18 or 0.06)
		self:SetBackdropBorderColor(c[1], c[2], c[3], 0.75)
		ink(self.label, self.role)
	end
	b:SetScript("OnEnter", function(self)
		self.hover = true
		self:Paint()
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		self:Paint()
	end)
	b:SetLabel(label)
	themed(function()
		b:Paint()
	end)
	return b
end

-- A fixed-width status box (PAID, AT LARGE, ELIMINATED ...).
local function makePill(parent, w)
	local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	p:SetSize(w, 16)
	p:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	p.text = ptext(p, 9, nil, "CENTER", NUM)
	p.text:SetPoint("CENTER", 0, 0)
	function p:Set(s, role)
		local c = T[role]
		self.text:SetText(s)
		self.text:SetTextColor(c[1], c[2], c[3])
		self:SetBackdropBorderColor(c[1], c[2], c[3], 0.9)
	end
	return p
end

-- Anchored by its top-left corner, so the window grows and shrinks downwards and
-- the header never jumps when the page changes height.
local function savePosition()
	local l, t = frame:GetLeft(), frame:GetTop()
	if not l or not t then
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	SG.db.settings.pos = { "TOPLEFT", "BOTTOMLEFT", l, t }
end

-- Space kept at the bottom of each page for its fixed parts (strip, boxes, form, footer).
local function bottomSpace()
	if mode == "pvp" then
		return 96
	elseif mode == "mine" then
		return 78
	elseif mode == "recall" then
		return form:IsShown() and 72 or 28
	elseif mode == "settings" then
		return 30
	elseif mode == "help" or mode == "welcome" then
		return 28
	end
	return 56 -- Production Report and Payroll: progress strip and footer
end

-- Fit the window to what's on the page.
local function fitHeight()
	if empty:IsShown() then
		empty:ClearAllPoints()
		empty:SetPoint("TOP", paper, "TOP", 0, -(cursor + 22))
		cursor = cursor + 22 + math.ceil(empty:GetStringHeight()) + 8
	end
	local pageH = cursor + 14 + bottomSpace()
	frame:SetHeight(math.max(MIN_H, TITLE_H + 4 + pageH + INSET))
end

-- Where I stand on the salary ladder.
local function career()
	local honor = SG.honorCount(SG.me())
	local title, nextTitle, need, pay, nextPay = SG.jobTitle(SG.myName, honor)
	local from, to = 0, nil
	for i, t in ipairs(SG.TITLES) do
		if honor >= t[1] then
			from = t[1]
			to = SG.TITLES[i + 1] and SG.TITLES[i + 1][1]
		end
	end
	return {
		honor = honor, title = title, nextTitle = nextTitle, need = need, pay = pay or 0, nextPay = nextPay,
		to = to, share = (nextTitle and to) and (honor - from) / math.max(1, to - from) or 1,
	}
end

local function raiseText(c)
	if c.nextPay and c.nextPay > c.pay then
		return "+" .. SG.money(c.nextPay - c.pay) .. " a week"
	end
	return nil
end

local function ladderTooltip(owner)
	local lines, honor = SG.ladderLines()
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:AddLine("Job titles and salaries", 1, 1, 1)
	GameTooltip:AddLine(("By lifetime honorable gnomes. You have %d."):format(honor), MUTED[1], MUTED[2], MUTED[3])
	for _, l in ipairs(lines) do
		local c = l[3] and GOLD or TEXT
		GameTooltip:AddDoubleLine(l[1], l[2], c[1], c[2], c[3], c[1], c[2], c[3])
	end
	GameTooltip:Show()
end

-- Spies: the class icon when gank mode saw them this session, else a plain portrait.
local function setPortrait(tex, name)
	local class = ns.Gank and ns.Gank.Seen and ns.Gank.Seen(name)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		tex:SetTexture(CLASS_ICONS)
		tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		tex:SetTexture(PORTRAIT)
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

-- A small × that withdraws the spy report in its parent's cancelTarget (your own reports).
function withdrawButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(16, 16)
	b.label = b:CreateFontString(nil, "OVERLAY")
	b.label:SetFont(FONT, 14, "")
	b.label:SetPoint("CENTER", 0, 1)
	b.label:SetText("×")
	local function paint(hover)
		local c = hover and T.red or T.muted
		b.label:SetTextColor(c[1], c[2], c[3])
	end
	b:SetScript("OnShow", function() paint(false) end)
	b:SetScript("OnEnter", function(self)
		paint(true)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Withdraw this report", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		paint(false)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		local target = self:GetParent().cancelTarget
		if target then
			GameTooltip:Hide()
			local ok, err = ns.Bounty.Cancel(target)
			SG.print(ok and ("Spy report on " .. target .. " withdrawn.") or tostring(err))
		end
	end)
	b:Hide()
	return b
end

local function rewardValue(s)
	return tonumber(tostring(s or ""):match("(%d+)")) or 0
end

---------------------------------------------------------------------------
-- Rows: one widget for every list, laid out per page.
---------------------------------------------------------------------------

-- Your row and the hovered row: a band that fades out at both ends instead of stopping dead.
local function paintRowBg(r)
	local c = (r.me and T.me) or (r.hovering and T.hover) or nil
	if c then
		tint(r.bg, c)
		r.bg:Show()
		if r.bgL then
			fade(r.bgL, "HORIZONTAL", c, 0, c[4] or 1)
			fade(r.bgR, "HORIZONTAL", c, c[4] or 1, 0)
		end
	else
		r.bg:Hide()
		if r.bgL then
			r.bgL:Hide()
			r.bgR:Hide()
		end
	end
end

local function makeRow()
	local r = CreateFrame("Frame", nil, paper)
	r:SetHeight(ROW_H)
	r.bg = solid(r, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bgL = solid(r, "BACKGROUND")
	r.bgL:SetWidth(12)
	r.bgL:SetPoint("TOPRIGHT", r, "TOPLEFT")
	r.bgL:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
	r.bgL:Hide()
	r.bgR = solid(r, "BACKGROUND")
	r.bgR:SetWidth(12)
	r.bgR:SetPoint("TOPLEFT", r, "TOPRIGHT")
	r.bgR:SetPoint("BOTTOMLEFT", r, "BOTTOMRIGHT")
	r.bgR:Hide()
	r.line = rule(r, "soft")
	r.line:SetPoint("BOTTOMLEFT")
	r.line:SetPoint("BOTTOMRIGHT")
	-- A dashed line in place of the plain one (under #3 on the Production Report).
	r.dashes = CreateFrame("Frame", nil, r)
	r.dashes:SetHeight(1)
	r.dashes:SetPoint("BOTTOMLEFT")
	r.dashes:SetPoint("BOTTOMRIGHT")
	for i = 0, math.floor(CW / 7) do
		local t = solid(r.dashes, "BORDER")
		t:SetSize(4, 1)
		t:SetPoint("LEFT", i * 7, 0)
		themed(function()
			tint(t, T.rule, T.hard * 0.7)
		end)
	end
	r.dashes:Hide()
	r.rank = ptext(r, 11, "muted", "CENTER", NUM)
	-- Medal ring: a fixed spot at the start of the row (even sizes, so it lands on whole pixels).
	r.ringO = disc(r, 18, "ARTWORK", 0)
	r.ringI = disc(r, 14, "ARTWORK", 1)
	r.ringO:SetPoint("CENTER", r, "LEFT", 9, 0)
	r.ringI:SetPoint("CENTER", r, "LEFT", 9, 0)
	r.pRing = disc(r, 28, "ARTWORK", 0)
	r.portrait = r:CreateTexture(nil, "ARTWORK", nil, 2)
	r.portrait:SetSize(24, 24)
	r.portrait:SetPoint("CENTER", r.pRing, "CENTER", 0, 0)
	r.dot = disc(r, 6, "ARTWORK", 3)
	r.name = ptext(r, 12, "ink")
	r.sub = ptext(r, 10, "muted", "LEFT", NARROW)
	r.star = r:CreateTexture(nil, "ARTWORK")
	r.star:SetTexture(STAR_TEX)
	r.star:SetSize(11, 11)
	r.star:SetPoint("LEFT", r.name, "RIGHT", 3, 0)
	r.tag = ptext(r, 9, "red", "LEFT", NUM)
	r.c1 = ptext(r, 12, "ink", "RIGHT", NUM_BOLD)
	r.c2 = ptext(r, 12, "muted", "RIGHT", NUM)
	r.pill = makePill(r, 60)
	r.x = withdrawButton(r)
	r:EnableMouse(true)
	r:SetScript("OnEnter", function(self)
		self.hovering = true
		paintRowBg(self)
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
	r:SetScript("OnLeave", function(self)
		self.hovering = false
		paintRowBg(self)
		GameTooltip:Hide()
	end)
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

-- Clear a row and lay it out. s: { rank, when, portrait, two, dot, c1W, c2W, pill, x }
local function setupRow(r, s, h)
	r:SetHeight(h)
	r:SetAlpha(1)
	r.me, r.tip, r.tipColor, r.cancelTarget = false, nil, nil, nil
	r.line:Show()
	r.dashes:Hide()
	for _, part in ipairs({ r.ringO, r.ringI, r.pRing, r.portrait, r.dot, r.star, r.pill, r.x }) do
		part:Hide()
	end
	for _, fs in ipairs({ r.rank, r.name, r.sub, r.tag, r.c1, r.c2 }) do
		fs:ClearAllPoints()
		fs:SetText("")
		fs:SetFont(fs.font, fs.size, "")
	end
	ink(r.name, "ink")
	ink(r.c1, "ink")
	ink(r.c2, "muted")
	ink(r.rank, "muted")
	local x = 0
	if s.rank then
		r.rank:SetWidth(18)
		r.rank:SetJustifyH("CENTER")
		r.rank:SetPoint("LEFT", 0, s.two and 0 or 0)
		x = 24
	elseif s.when then
		r.rank:SetWidth(34)
		r.rank:SetJustifyH("LEFT")
		r.rank:SetPoint("LEFT", 0, 0)
		x = 40
	elseif s.portrait then
		r.pRing:ClearAllPoints()
		r.pRing:SetPoint("LEFT", 0, 0)
		r.pRing:Show()
		r.portrait:Show()
		x = 36
	end
	local y = s.two and 6 or 0
	if s.dot and not T.classNames then
		r.dot:ClearAllPoints()
		r.dot:SetPoint("LEFT", x, y)
		r.dot:Show()
		x = x + 10
	end
	r.name:SetPoint("LEFT", x, y)
	r.sub:SetPoint("LEFT", x, -8)
	r.nameX = x
	local right = 0
	if s.x then
		r.x:ClearAllPoints()
		r.x:SetPoint("RIGHT", 0, 0)
		r.x:Show()
		right = 20
	end
	if s.pill then
		r.pill:ClearAllPoints()
		r.pill:SetPoint("RIGHT", -right, 0)
		r.pill:Show()
		right = right + s.pill + 8
	elseif s.c2W then
		r.c2:SetPoint("RIGHT", 0, 0)
		r.c2:SetWidth(s.c2W)
		right = s.c2W + 6
	end
	if s.c1W then
		r.c1:SetPoint("RIGHT", -right, 0)
		r.c1:SetWidth(s.c1W)
		right = right + s.c1W + 6
	end
	r.nameMax = CW - x - right
	paintRowBg(r)
end

-- Medal ring for ranks 1-3, plain number after.
local function setRank(r, rank)
	r.rank:SetText(rank)
	local m = rank <= 3 and T.medals[rank]
	if m then
		-- The digit sits on the ring's own centre (text sized to the digit, not a fixed box).
		r.rank:ClearAllPoints()
		r.rank:SetWidth(0)
		-- Per-digit nudge, measured in game: the 1's stroke sits right of its glyph box,
		-- and all digits sit a touch high in the narrow font.
		local nudge = ({ -0.3, 0.5, 0.25 })[rank] or 0
		r.rank:SetPoint("CENTER", r.ringO, "CENTER", nudge, -0.8)
		tint(r.ringO, m)
		tint(r.ringI, T.paper)
		r.ringO:Show()
		r.ringI:Show()
		r.rank:SetTextColor(m[1], m[2], m[3])
	else
		ink(r.rank, "muted")
	end
end

-- Name (full, fitted), class colour or dot, optional star and tag after it.
local function setName(r, name, class, star, tag)
	local extra = (star and 14 or 0)
	if tag then
		r.tag:SetText(tag)
		extra = extra + math.ceil(r.tag:GetStringWidth()) + 8
	end
	fitText(r.name, name, math.max(40, r.nameMax - extra))
	local cr, cg, cb = classColor(class)
	if T.classNames and class then
		r.name:SetTextColor(cr, cg, cb)
	else
		ink(r.name, "ink")
	end
	if r.dot:IsShown() then
		r.dot:SetVertexColor(cr, cg, cb)
	end
	r.star:SetShown(star == true)
	if tag then
		r.tag:SetPoint("LEFT", star and r.star or r.name, "RIGHT", star and 4 or 8, 0)
	end
end

---------------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------------

-- Put a part on the page at the next free y.
local function place(w, h, gap)
	cursor = cursor + (gap or 0)
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", paper, "TOPLEFT", PAD, -cursor)
	w:SetWidth(CW)
	if h then
		w:SetHeight(h)
	end
	w:Show()
	cursor = cursor + w:GetHeight()
end

local function setHead(title, role, sub, right)
	heading:SetText(title)
	ink(heading, role or "accent")
	subtitle:SetText(sub or "")
	subtitle:SetShown(sub ~= nil)
	headRight:SetText(right or "")
	headRight:SetShown(right ~= nil)
	cursor = 16 + 22 + (sub and (math.ceil(subtitle:GetStringHeight()) + 6) or 0) + 16
end

-- Column header. s: { c0, name, nameX, c1, c1W, c2, c2W, right }
local function setHeads(s)
	heads.c0:SetText(s.c0 or "")
	heads.name:ClearAllPoints()
	heads.name:SetPoint("BOTTOMLEFT", s.nameX or 0, 4)
	heads.name:SetText(s.name or "")
	heads.c2:ClearAllPoints()
	heads.c1:ClearAllPoints()
	local right = s.right or 0
	heads.c2:SetPoint("BOTTOMRIGHT", -right, 4)
	heads.c2:SetWidth(s.c2W or 60)
	heads.c2:SetText(s.c2 or "")
	right = right + (s.c2W or 0) + 6
	heads.c1:SetPoint("BOTTOMRIGHT", -right, 4)
	heads.c1:SetWidth(s.c1W or 60)
	heads.c1:SetText(s.c1 or "")
	place(heads, 18)
	cursor = cursor + 4
end

-- Mouse-wheel scrolling: the first row shown on this page, kept in range.
local function firstRow(total, visible)
	pageTotal, pageVisible = total, visible
	local maxOff = math.max(0, total - visible)
	local off = math.max(0, math.min(offsets[mode] or 0, maxOff))
	offsets[mode] = off
	if total > visible then
		heads.more:SetText(("%d-%d of %d"):format(off + 1, math.min(off + visible, total), total))
		heads.more:Show()
	else
		heads.more:Hide()
	end
	return off
end

function UI.Scroll(delta)
	if pageTotal <= pageVisible then
		return
	end
	offsets[mode] = math.max(0, math.min((offsets[mode] or 0) + delta * 3, pageTotal - pageVisible))
	UI.Refresh()
end

-- The progress strip at the bottom of the Production Report and Payroll.
local function showStrip(left)
	local c = career()
	strip.left:SetText(left or ("You  ·  |cff%s%s|r"):format(hex(T.accent), c.title))
	local room = CW - math.ceil(strip.left:GetStringWidth()) - 12
	local options
	if not c.nextTitle then
		options = { "Top of the ladder" }
	else
		local base, acc = ("%d to %s"):format(c.need, c.nextTitle), hex(T.accent)
		options = {}
		if raiseText(c) then
			options[#options + 1] = base .. ("  ·  |cff%s%s|r"):format(acc, raiseText(c))
			options[#options + 1] = base .. ("  ·  |cff%s+%s|r"):format(acc, SG.money(c.nextPay - c.pay))
		end
		options[#options + 1] = base
		options[#options + 1] = ("%d to next title"):format(c.need)
	end
	for _, text in ipairs(options) do
		strip.right:SetText(text)
		if strip.right:GetStringWidth() <= room then
			break
		end
	end
	strip.bar:SetValue(c.share, CW)
	strip:Show()
	return c
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

-- Tooltip lines for a coworker's row.
local function coworkerTip(r, name, e, isMe)
	local title, _, _, pay = SG.jobTitle(name, SG.honorCount(e))
	if pay > 0 then
		title = title .. "  ·  " .. SG.money(pay) .. " a week"
	end
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

local BOARDS = {
	week = { title = "PRODUCTION REPORT",
		sub = "Kill gnomes in world PvP to climb and get promoted.",
		heads = { c0 = "NO.", name = "EMPLOYEE", nameX = 24, c1 = "POINTS", c1W = 52, c2 = "GNOMES", c2W = 46 },
		row = { rank = true, dot = true, c1W = 52, c2W = 46 }, h = ROW_H },
	all = { title = "PRODUCTION REPORT",
		sub = "Kill gnomes in world PvP to climb and get promoted.",
		heads = { c0 = "NO.", name = "EMPLOYEE", nameX = 24, c1 = "HONORABLE", c1W = 60, c2 = "GNOMES", c2W = 46 },
		row = { rank = true, dot = true, c1W = 60, c2W = 46 }, h = ROW_H },
	pvp = { title = "FIELD REPORT", sub = "Every Alliance player killed in the open world.",
		heads = { c0 = "NO.", name = "EMPLOYEE", nameX = 24, c1 = "WEEK", c1W = 44, c2 = "LIFETIME", c2W = 56 },
		row = { rank = true, dot = true, c1W = 44, c2W = 56 }, h = ROW_H },
}

local function fillBoardRow(r, rank, row, isMe, above)
	local cfg = BOARDS[mode]
	setupRow(r, cfg.row, cfg.h)
	setRank(r, rank)
	local e = row.e
	local tag
	if mode == "week" and isMe and above and above.points > row.points then
		tag = SG.points(above.points - row.points) .. " to #" .. (rank - 1) -- the next place up
	end
	setName(r, SG.shortName(row.name), e and e.class, mode == "week" and row.name == champion, tag)
	local active = e and math.max(e.seen or 0, e.u or 0) or 0
	if e and not isMe and (SG.now() - active) > STALE_DAYS * 86400 then
		r.name:SetAlpha(0.5)
	else
		r.name:SetAlpha(1)
	end
	coworkerTip(r, row.name, e, isMe)
	if mode == "week" then
		r.c1:SetText(SG.points(row.points))
		r.c2:SetText(row.kills)
		r.tip[#r.tip + 1] = ("This week: %d gnome%s, %s points%s"):format(row.kills, row.kills == 1 and "" or "s",
			SG.points(row.points), row.assists > 0 and (", " .. row.assists .. " assists") or "")
	elseif mode == "pvp" then
		r.c1:SetText(row.kills)
		r.c2:SetText(row.assists)
		r.tip[#r.tip + 1] = ("Alliance killed: %d this week, %d lifetime"):format(row.kills, row.assists)
		r.tip[#r.tip + 1] = ("Of those, gnomes: %d this week, %d lifetime"):format((SG.weekCounts(e or {}, SG.weekId())), e and e.total or 0)
	else
		-- All time: honorable gnomes (what titles count) and every gnome harvested.
		local honor = SG.honorCount(e)
		r.c1:SetText(honor)
		r.c2:SetText(row.kills)
		r.tip[#r.tip + 1] = ("All time: %d gnome%s, %d honorable%s"):format(row.kills, row.kills == 1 and "" or "s",
			honor, row.assists > 0 and (", " .. row.assists .. " assists") or "")
	end
	r.me = isMe
	paintRowBg(r)
end

local function refreshBoard()
	local cfg = BOARDS[mode]
	setHead(cfg.title, nil, cfg.sub)
	local report = mode == "week" or mode == "all"
	if report then
		periodSwitch.paint()
		place(periodSwitch, 16)
		cursor = cursor + 12
	end

	local list = {}
	for _, row in ipairs(SG.ranked(mode)) do
		if row.kills > 0 or row.assists > 0 then
			list[#list + 1] = row
		end
	end
	local myRank
	for i, row in ipairs(list) do
		if row.name == SG.myName then
			myRank = i
		end
	end

	-- Employee of the Week: on the Production Report, both periods.
	if report and champion then
		local _, pts = SG.lastWeekWinner()
		band.pts:SetText(pts .. " pts")
		local room = CW - 36 - math.ceil(band.label:GetStringWidth()) - 6 - math.ceil(band.pts:GetStringWidth()) - 16
		fitText(band.name, SG.shortName(champion), room)
		place(band, 26)
		cursor = cursor + 12
	end

	if #list == 0 then
		empty:SetText(mode == "pvp" and "No Alliance killed yet.\n\nEvery Alliance player you kill in the\nopen world counts here, gnome or not."
			or ((mode == "week" and "No gnomes harvested this week." or "No gnomes harvested yet.")
				.. "\n\nLand the killing blow on a gnome\nin the open world to start production."))
		empty:Show()
	else
		setHeads(cfg.heads)
		local off = firstRow(#list, PAGE_ROWS)
		for i = 1, PAGE_ROWS do
			local idx = off + i
			local row = list[idx]
			if row then
				fillBoardRow(rows[i], idx, row, row.name == SG.myName, list[idx - 1])
				place(rows[i])
				if report and idx == 3 and #list > 3 then
					-- Top 3 end here: a dashed line instead of the plain one, same spacing.
					rows[i].line:Hide()
					rows[i].dashes:Show()
				end
			end
		end
		-- My own row, pinned under the page when it's scrolled off.
		if myRank and (myRank <= off or myRank > off + PAGE_ROWS) then
			fillBoardRow(rows[MAX_ROWS], myRank, list[myRank], true, list[myRank - 1])
			place(rows[MAX_ROWS], nil, 6)
		end
	end

	local cur = SG.weekId()
	if mode == "pvp" then
		local e = SG.me()
		local wk, life = SG.pvpCounts(e, cur)
		local gn = SG.weekCounts(e, cur)
		stats[1].value:SetText(wk)
		stats[1].sub:SetText(myRank and ("rank #" .. myRank) or "not ranked yet")
		stats[2].value:SetText(gn)
		stats[3].value:SetText(life)
		for _, s in ipairs(stats) do
			s:Show()
		end
		local company = 0
		for _, p in pairs(SG.db.players) do
			company = company + (SG.pvpCounts(p, cur))
		end
		footL:SetText("Resets in " .. SG.duration(SG.secondsUntilReset()))
		footR:SetText(("Company this week: |cff%s%d|r Alliance"):format(hex(T.ink), company))
	else
		showStrip()
		if mode == "week" then
			local company = 0
			for _, p in pairs(SG.db.players) do
				company = company + (SG.weekCounts(p, cur))
			end
			footL:SetText("Resets in " .. SG.duration(SG.secondsUntilReset()))
			footR:SetText(("Company this week: |cff%s%d|r gnome%s"):format(hex(T.ink), company, company == 1 and "" or "s"))
		else
			local company = 0
			for _, p in pairs(SG.db.players) do
				company = company + (p.total or 0)
			end
			local e = SG.me()
			footL:SetText(myRank and ("Your rank #%d of %d"):format(myRank, #list) or "Not ranked yet")
			footR:SetText(("Company all time: |cff%s%d|r gnome%s"):format(hex(T.ink), company, company == 1 and "" or "s"))
		end
	end
end

local function refreshRecalls()
	local list = ns.Bounty.List()
	local now = SG.now()
	local open = ns.Bounty.OpenCount()
	setHead("CORPORATE SPIES", "red", "First kill collects the reward.",
		open == 1 and "1 at large" or (open .. " at large"))

	-- Most wanted: the open report with the biggest reward.
	local best
	for i, row in ipairs(list) do
		if row.state == "open" and (not best or rewardValue(row.b.reward) > rewardValue(list[best].b.reward)) then
			best = i
		end
	end
	card.cancelTarget, card.tip, card.tipColor = nil, nil, GOLD
	if best then
		local b = list[best].b
		setPortrait(card.portrait, b.target)
		fitText(card.name, b.target, CW - 66 - 70)
		card.detail:SetText(("By %s  ·  %s left"):format(SG.shortName(b.poster), SG.duration(b.expires - now)))
		fitText(card.reward, b.reward, 64)
		card.tip = { b.target, "Reward: " .. b.reward, ("Posted by %s, %s"):format(SG.shortName(b.poster), SG.ago(b.created)),
			"Kill them in the open world to claim it." }
		if b.poster == SG.myName then
			card.cancelTarget = b.target
			card.tip[#card.tip + 1] = "Your report: click × to withdraw it."
		end
		card.x:SetShown(card.cancelTarget ~= nil)
		place(card, 64)
		cursor = cursor + 14
	end

	local cases = {}
	for i, row in ipairs(list) do
		if i ~= best then
			cases[#cases + 1] = row
		end
	end
	if #cases > 0 then
		setHeads({ name = "OTHER CASES", c1 = "REWARD", c1W = 38, c2 = "STATUS", c2W = 60 })
		local off = firstRow(#cases, CASE_ROWS)
		for i = 1, CASE_ROWS do
			local row = cases[off + i]
			if row then
				local r, b, state = rows[i], row.b, row.state
				local mine = state == "open" and b.poster == SG.myName
				setupRow(r, { portrait = true, two = true, pill = 60, c1W = 38, x = mine }, CASE_H)
				setPortrait(r.portrait, b.target)
				setName(r, b.target, ns.Gank and ns.Gank.Seen and ns.Gank.Seen(b.target))
				fitText(r.c1, b.reward, 40)
				r.tipColor = GOLD
				r.tip = { b.target, "Reward: " .. b.reward, ("Posted by %s, %s"):format(SG.shortName(b.poster), SG.ago(b.created)) }
				if state == "open" then
					tint(r.pRing, T.red)
					r.pill:Set("AT LARGE", "red")
					ink(r.c1, "gold")
					r.sub:SetText(("By %s  ·  %s left"):format(SG.shortName(b.poster), SG.duration(b.expires - now)))
					r.tip[#r.tip + 1] = "Kill them in the open world to claim it."
					if b.poster == SG.myName then
						r.cancelTarget = b.target
						r.tip[#r.tip + 1] = "Your report: click × to withdraw it."
					end
				elseif state == "claimed" then
					local c = row.claim
					local where = (c.zone and c.zone ~= "") and ("  ·  " .. c.zone) or ""
					tint(r.pRing, T.accent)
					r.pill:Set("ELIMINATED", "accent")
					ink(r.c1, "accent")
					r.sub:SetText(("by %s%s  ·  %s"):format(c.claimer == SG.myName and "you" or SG.shortName(c.claimer), where, SG.ago(c.t)))
					r.tip[#r.tip + 1] = ("Eliminated by %s%s, %s"):format(SG.shortName(c.claimer), where, SG.ago(c.t))
				else
					tint(r.pRing, T.muted)
					r.pill:Set("EXPIRED", "muted")
					ink(r.c1, "muted")
					r.sub:SetText("Expired, clears after a day")
					r:SetAlpha(0.6)
				end
				place(r)
			end
		end
	end
	if #list == 0 then
		empty:SetText("No corporate spies reported.\n\nWe have a zero tolerance policy for\ncorporate espionage. If you are\nsuspected, it's on sight.")
		empty:Show()
	end

	form:SetShown(SG.IsOfficer(SG.myName) == true)
	local mine = ns.Bounty.CompletedBy(SG.myName)
	footL:SetText(mine > 0 and ("You've eliminated |cff%s%d|r"):format(hex(T.accent), mine) or "Eliminate a spy to collect")
end

local function refreshMine()
	local list = SG.db.recent[SG.myName] or {}
	setHead("LAB LOG", nil, #list > 0 and ("Your last %d harvests."):format(#list) or "Your harvests show up here.")
	if #list > 0 then
		setHeads({ c0 = "WHEN", name = "GNOME", nameX = 40, c2 = "POINTS", c2W = 44 })
		local off = firstRow(#list, PAGE_ROWS)
		for i = 1, PAGE_ROWS do
			local k = list[off + i]
			if k then
				local r = rows[i]
				setupRow(r, { when = true, two = true, c2W = 44 }, ROW2_H)
				r.rank:SetText((SG.ago(k.t):gsub(" ago", "")))
				setName(r, (k.name or "Unknown gnome") .. (k.test and " (test)" or ""))
				local detail = { k.zone or "Unknown zone" }
				local v = not k.test and ns.Ledger.Victim(k.name, k.realm)
				if v and v.n > 1 then
					detail[#detail + 1] = ("smoked %d×"):format(v.n)
					local label = ns.Ledger.Label(v.n)
					if label then
						detail[#detail + 1] = label:lower()
					end
				end
				if k.assist then
					detail[#detail + 1] = "assist"
				elseif k.lvl and k.myLvl and not SG.honorable(k.myLvl, k.lvl) then
					detail[#detail + 1] = "grey"
				end
				r.sub:SetText(table.concat(detail, "  ·  "))
				if k.assist then
					r.c2:SetText("-")
					r:SetAlpha(0.7)
				elseif k.pts then
					ink(r.c2, "accent")
					r.c2:SetText("+" .. SG.points(k.pts))
				end
				r.tip = { k.name or "Unknown gnome", k.zone or "Unknown zone", SG.ago(k.t) }
				if k.pts then
					r.tip[#r.tip + 1] = ("+%s points (level %s vs your %s)"):format(SG.points(k.pts),
						k.lvl and (k.lvl < 0 and "??" or k.lvl) or "unknown", k.myLvl or "?")
				end
				if v and v.n > 1 then
					r.tip[#r.tip + 1] = ("Smoked by the company %d×"):format(v.n)
				end
				place(r)
			end
		end
	end

	-- Your career: only here.
	local c = career()
	careerBox.count:SetText(c.nextTitle and ("%d / %d honorable gnomes"):format(c.honor, c.to) or (c.honor .. " honorable gnomes"))
	careerBox.cur:SetText(c.title)
	careerBox.nxt:SetText(c.nextTitle or "")
	local barW = CW - 20 - math.ceil(careerBox.cur:GetStringWidth()) - math.ceil(careerBox.nxt:GetStringWidth()) - 20
	careerBox.bar:SetValue(c.share, barW)
	careerBox.payNow:SetText(c.pay > 0 and (SG.money(c.pay) .. " a week") or "unpaid")
	careerBox.togo:SetText(c.nextTitle and (c.need .. " more to go") or "top of the ladder")
	local nextPay = ""
	if c.nextTitle then
		nextPay = ("|cff%s%s|r"):format(hex(T.gold), (c.nextPay or 0) > 0 and (SG.money(c.nextPay) .. " a week") or "unpaid")
		if raiseText(c) then
			nextPay = nextPay .. ("  |cff%s+%s|r"):format(hex(T.accent), SG.money(c.nextPay - c.pay))
		end
	end
	careerBox.payNext:SetText(nextPay)
	careerBox:Show()
end

local function refreshPayroll()
	local week, preview = ns.Payroll.ViewWeek()
	local record = not preview and ns.Payroll.Record(week)
	local list, total, percent = ns.Payroll.Compute(week, preview, record and record.percent or nil)
	local sub = preview and "This week so far. No work, no pay." or ("Week ending %s. No work, no pay."):format(ns.Hall.WeekLabel(week))
	if percent < 100 then
		sub = sub .. (" Budget cap: %d%% of full pay."):format(percent)
	end
	setHead("PAYROLL", nil, sub)
	if preview then
		headPill:Set("PREVIEW", "muted")
	elseif record then
		headPill:Set("PAID", "accent")
	else
		headPill:Set("UNPAID", "red")
	end
	headPill:Show()
	actionBtn:SetLabel("DONE")
	actionBtn:Show()

	local myRow
	for i, row in ipairs(list) do
		if row.name == SG.myName then
			myRow = i
		end
	end
	local function fill(r, row)
		setupRow(r, { dot = true, two = true, c1W = 44, c2W = 56 }, ROW2_H)
		setName(r, SG.shortName(row.name), row.e and row.e.class)
		r.sub:SetText(row.title)
		r.c1:SetText(row.honor)
		ink(r.c1, "muted")
		if row.pay > 0 then
			r.c2:SetText(SG.money(row.pay))
			ink(r.c2, "gold")
		else
			r.c2:SetText("unpaid")
			ink(r.c2, "muted")
		end
		r.tipColor = ACCENT
		r.tip = { SG.shortName(row.name), row.title,
			("%d honorable gnome%s %s"):format(row.honor, row.honor == 1 and "" or "s", preview and "this week so far" or "that week") }
		if row.pay > 0 then
			r.tip[#r.tip + 1] = ("Salary: %s%s"):format(SG.money(row.pay), percent < 100 and (" (%d%% of full pay, budget cap)"):format(percent) or "")
		else
			local first = SG.TITLES[3]
			r.tip[#r.tip + 1] = ("No salary yet: %d more honorable gnome%s to %s (%s a week)"):format(
				first[1] - row.lifetime, first[1] - row.lifetime == 1 and "" or "s", first[2], SG.money(first[3]))
		end
		r.me = row.name == SG.myName
		paintRowBg(r)
	end
	if #list == 0 then
		empty:SetText(preview and "No harvests yet this week.\n\nOne honorable gnome puts you\non the payroll."
			or "Nobody worked last week.\n\nNo work, no pay: one honorable\ngnome a week earns your salary.")
		empty:Show()
	else
		setHeads({ name = "EMPLOYEE", c1 = "GNOMES", c1W = 44, c2 = "SALARY", c2W = 56 })
		local off = firstRow(#list, PAGE_ROWS)
		for i = 1, PAGE_ROWS do
			local row = list[off + i]
			if row then
				fill(rows[i], row)
				place(rows[i])
			end
		end
		if myRow and (myRow <= off or myRow > off + PAGE_ROWS) then
			fill(rows[MAX_ROWS], list[myRow])
			place(rows[MAX_ROWS], nil, 6)
		end
	end

	local mine = myRow and list[myRow]
	showStrip(("Your pay  ·  |cff%s%s|r"):format(hex(T.gold), mine and mine.pay > 0 and SG.money(mine.pay) or "none yet"))
	local paid = 0
	for _, row in ipairs(list) do
		if row.pay > 0 then
			paid = paid + 1
		end
	end
	footL:SetText(("%d paid"):format(paid))
	footR:SetText(("Total |cff%s%s|r"):format(hex(T.gold), #list > 0 and SG.money(total) or "-"))
end

---------------------------------------------------------------------------
-- Settings and Commands
---------------------------------------------------------------------------

-- A small control on the page: On/Off switch, value button or stepper button.
local function control(parent, w, label)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, 20)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b.label = ptext(b, 10, nil, "CENTER", NUM)
	b.label:SetPoint("CENTER", 0, 0)
	b.label:SetText(label or "")
	function b:Paint()
		if self.on then
			local a = T.accent
			self:SetBackdropColor(a[1], a[2], a[3], 1)
			self:SetBackdropBorderColor(a[1], a[2], a[3], 1)
			ink(self.label, "paper")
		else
			local c = T.ink
			self:SetBackdropColor(c[1], c[2], c[3], self.hover and 0.16 or 0.06)
			self:SetBackdropBorderColor(c[1], c[2], c[3], 0.3)
			ink(self.label, self.dim and "muted" or "ink")
		end
	end
	b:SetScript("OnEnter", function(self)
		self.hover = true
		self:Paint()
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		self:Paint()
	end)
	themed(function()
		b:Paint()
	end)
	return b
end

local SETTING_H = 32

local function buildSettings()
	settingsPanel = CreateFrame("Frame", nil, paper)
	settingsPanel:SetSize(CW, SETTING_H * 9 + 1)
	local top = rule(settingsPanel, "hard")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	local y = 0
	local updaters = {}

	local function label(title, note, controlW)
		local l = ptext(settingsPanel, 12, "ink")
		l:SetPoint("TOPLEFT", 0, -(y + 5))
		l:SetText(title)
		if note then
			local n = ptext(settingsPanel, 9, "muted", "LEFT", NUM)
			n:SetPoint("TOPLEFT", 0, -(y + 20))
			n:SetWidth(CW - controlW - 8)
			n:SetText(note)
		end
		local line = rule(settingsPanel, "soft")
		line:SetPoint("TOPLEFT", 0, -(y + SETTING_H))
		line:SetPoint("TOPRIGHT", 0, -(y + SETTING_H))
	end

	local function stepper(title, note, get, set, step, min, max, fmt)
		label(title, note, 96)
		local plus = control(settingsPanel, 20, "+")
		plus:SetPoint("TOPRIGHT", 0, -(y + 7))
		local value = ptext(settingsPanel, 11, "ink", "CENTER", NUM)
		value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
		value:SetWidth(44)
		local minus = control(settingsPanel, 20, "-")
		minus:SetPoint("RIGHT", value, "LEFT", -2, 0)
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
		y = y + SETTING_H
	end

	local function toggle(title, note, get, set)
		label(title, note, 52)
		local b = control(settingsPanel, 52)
		b:SetPoint("TOPRIGHT", 0, -(y + 7))
		b:SetScript("OnClick", function()
			set(not get())
			UI.Refresh()
		end)
		updaters[#updaters + 1] = function()
			b.on = get() and true or false
			b.dim = not b.on
			b.label:SetText(b.on and "ON" or "OFF")
			b:Paint()
		end
		y = y + SETTING_H
	end

	local function cycler(title, note, current, step)
		label(title, note, 64)
		local b = control(settingsPanel, 64)
		b:SetPoint("TOPRIGHT", 0, -(y + 7))
		b:SetScript("OnClick", function()
			step()
			UI.Refresh()
		end)
		updaters[#updaters + 1] = function()
			local v = current()
			b.dim = v == "Off"
			b.label:SetText(v:upper())
			b:Paint()
		end
		y = y + SETTING_H
	end

	local s = function() return SG.db.settings end
	local pct = function(v) return math.floor(v * 100 + 0.5) .. "%" end

	stepper("Window size", "This window only (or drag its corner)",
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
	toggle("Guildmates' kills", "Popup when a guildmate harvests one",
		function() return s().guildHarvests == true end, function(v) s().guildHarvests = v end)
	toggle("Login standings", "Top 3 in chat when you log in",
		function() return s().loginStandings ~= false end, function(v) s().loginStandings = v end)
	toggle("Minimap button", "Left-click opens, drag to move",
		function() return not (s().minimap and s().minimap.hide) end, function(v) UI.SetMinimap(v) end)

	settingsPanel.update = function()
		for _, fn in ipairs(updaters) do
			fn()
		end
	end
	settingsPanel:Hide()

	commandsBtn = pageButton(paper, "SLASH COMMANDS  >", "ink")
	commandsBtn:SetPoint("BOTTOMLEFT", PAD, 10)
	commandsBtn:SetScript("OnClick", function()
		UI.ShowView("help", true)
	end)
	commandsBtn:Hide()
end

-- Commands view: the slash commands people actually use, one line each.
local HELP = {
	{ "/gnomes", "Open or close this window" },
	{ "/gnomes stats", "Your numbers in chat" },
	{ "/gnomes status", "Check it's working" },
	{ "/gnomes points", "How points work" },
	{ "/gnomes ranks", "Titles and salaries" },
	{ "/gnomes gank", "Gank mode on or off" },
	{ "/gnomes payroll", "Last week's salaries" },
	{ "/gnomes spies", "List spies in chat" },
	{ "/gnomes spy Name 50g", "Report a spy (officers)" },
	{ "/gnomes spy cancel Name", "Withdraw your report" },
	{ "/gnomes sync", "Refresh from the guild" },
	{ "/gnomes test", "Preview a kill popup" },
}

local function buildHelp()
	helpPanel = CreateFrame("Frame", nil, paper)
	helpPanel:SetSize(CW, #HELP * 26 + 1)
	local top = rule(helpPanel, "hard")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	for i, row in ipairs(HELP) do
		local y = -(i - 1) * 26
		local cmd = ptext(helpPanel, 11, "accent", "LEFT", NARROW)
		cmd:SetPoint("TOPLEFT", 0, y - 8)
		cmd:SetText(row[1])
		local desc = ptext(helpPanel, 11, "muted")
		desc:SetPoint("TOPLEFT", 126, y - 7)
		desc:SetWidth(CW - 126)
		desc:SetText(row[2])
		local line = rule(helpPanel, "soft")
		line:SetPoint("TOPLEFT", 0, y - 26)
		line:SetPoint("TOPRIGHT", 0, y - 26)
	end
	helpPanel:Hide()
end

---------------------------------------------------------------------------
-- Spies: the officer form
---------------------------------------------------------------------------

local function makeInput(parent, width, placeholder, maxLetters)
	local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	eb:SetSize(width, 20)
	eb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	eb:SetFont(NUM, 11, "")
	eb:SetTextInsets(6, 6, 0, 0)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(maxLetters)
	eb.hint = ptext(eb, 10, "muted", "LEFT", NUM)
	eb.hint:SetPoint("LEFT", 6, 0)
	eb.hint:SetText(placeholder)
	local function paint(self)
		local c, e = T.ink, self:HasFocus() and T.accent or T.ink
		self:SetBackdropColor(c[1], c[2], c[3], 0.06)
		self:SetBackdropBorderColor(e[1], e[2], e[3], self:HasFocus() and 1 or 0.3)
		self:SetTextColor(c[1], c[2], c[3])
	end
	eb:SetScript("OnTextChanged", function(self)
		self.hint:SetShown(self:GetText() == "")
	end)
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	eb:SetScript("OnEditFocusGained", paint)
	eb:SetScript("OnEditFocusLost", paint)
	themed(function()
		paint(eb)
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

local function buildForm()
	form = CreateFrame("Frame", nil, paper)
	form:SetSize(CW, 40)
	form:SetPoint("BOTTOMLEFT", PAD, 32)
	local line = rule(form, "soft")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	local l = ptext(form, 9, "muted", "LEFT", NUM)
	l:SetPoint("TOPLEFT", 0, -6)
	l:SetText("REPORT A SPY  ·  OFFICERS ONLY")
	local post = pageButton(form, "REPORT", "red")
	post:SetPoint("BOTTOMRIGHT", 0, 0)
	form.reward = makeInput(form, 70, "Reward", 30)
	form.reward:SetPoint("RIGHT", post, "LEFT", -6, 0)
	form.target = makeInput(form, CW - 70 - 12 - post:GetWidth(), "Name, or blank for target", 40)
	form.target:SetPoint("RIGHT", form.reward, "LEFT", -6, 0)
	post:SetScript("OnEnter", function(self)
		self.hover = true
		self:Paint()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Report a corporate spy", 1, 1, 1)
		GameTooltip:AddLine("Leave the name empty to use your current target.", MUTED[1], MUTED[2], MUTED[3])
		GameTooltip:AddLine("The first employee to take them out collects.", MUTED[1], MUTED[2], MUTED[3])
		GameTooltip:Show()
	end)
	post:SetScript("OnLeave", function(self)
		self.hover = false
		self:Paint()
		GameTooltip:Hide()
	end)
	post:SetScript("OnClick", postFromForm)
	form.target:SetScript("OnEnterPressed", function()
		form.reward:SetFocus()
	end)
	form.target:SetScript("OnTabPressed", function()
		form.reward:SetFocus()
	end)
	form.reward:SetScript("OnEnterPressed", postFromForm)
	form:Hide()
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

-- Square header button on the wood: Payroll, Settings, Close.
local function headerButton(tipTitle, tipText)
	local b = CreateFrame("Button", nil, frame, "BackdropTemplate")
	b:SetSize(22, 22)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	function b:Paint()
		if self.red then
			self:SetBackdropColor(0.431, 0.078, 0.063, 1)
			if self.hover then
				self:SetBackdropBorderColor(1, 0.85, 0.5, 1)
			else
				self:SetBackdropBorderColor(0.60, 0.25, 0.18, 1)
			end
			return
		end
		if self.active then
			self:SetBackdropColor(0.227, 0.173, 0.071, 1)
		else
			self:SetBackdropColor(0.165, 0.125, 0.075, 1)
		end
		if self.active or self.hover then
			self:SetBackdropBorderColor(1, 0.82, 0, 1)
		else
			self:SetBackdropBorderColor(0.33, 0.26, 0.13, 1)
		end
	end
	b:SetScript("OnEnter", function(self)
		self.hover = true
		self:Paint()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tipTitle, 1, 1, 1)
		if tipText then
			GameTooltip:AddLine(tipText, MUTED[1], MUTED[2], MUTED[3])
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		self:Paint()
		GameTooltip:Hide()
	end)
	b:Paint()
	return b
end

local TAB_LIST = { { "Report", "week" }, { "PvP", "pvp" }, { "Spies", "recall" }, { "Lab Log", "mine" } }

local function paintTab(b)
	local on = b.key == mode or (b.key == "week" and mode == "all")
	b.label:SetFont(FONT, on and 12 or 11, "")
	b:SetSize(math.ceil(b.label:GetStringWidth()) + (on and 26 or 20), on and 26 or 22)
	local face, edge, txt
	if on then
		face, edge, txt = T.tabOn, { 0.851, 0.690, 0.290 }, T.tabOnText
	elseif b.hover then
		face, edge, txt = { 0.165, 0.125, 0.075 }, TRIM, { 1.0, 0.94, 0.75 }
	else
		face, edge, txt = { 0.114, 0.086, 0.063 }, { 0.353, 0.275, 0.125 }, { 0.788, 0.706, 0.541 }
	end
	b.shape:SetBackdropColor(face[1], face[2], face[3], 1)
	b.shape:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
	b.label:SetTextColor(txt[1], txt[2], txt[3])
	b.label:SetShadowOffset(1, -1)
end

local TAB_GAP = 2 -- small even gaps: one group

-- The tab row sits centred under the window: the same space on the left and right.
local function layoutTabs()
	local total = TAB_GAP * (#tabs - 1)
	for _, t in ipairs(tabs) do
		total = total + t:GetWidth()
	end
	tabs[1]:ClearAllPoints()
	tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", math.floor((W - total) / 2), 1)
end

local function makeTab(label, key)
	local b = CreateFrame("Button", nil, frame)
	b.key = key
	b:SetClipsChildren(true) -- hides the top of the rounded border: the tab meets the frame
	b.shape = CreateFrame("Frame", nil, b, "BackdropTemplate")
	b.shape:SetPoint("TOPLEFT", 0, 10)
	b.shape:SetPoint("BOTTOMRIGHT", 0, 0)
	b.shape:SetBackdrop({
		bgFile = WHITE,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", -- the tooltip's rounded edge
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	b.label = b.shape:CreateFontString(nil, "OVERLAY")
	b.label:SetFont(FONT, 12, "")
	b.label:SetShadowColor(0, 0, 0, 0.8)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 1) -- centred on the visible tab, not the taller shape
	b.label:SetText(label)
	b:SetScript("OnClick", function()
		mode = key == "week" and boardPeriod or key
		UI.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		self.hover = true
		paintTab(self)
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		paintTab(self)
	end)
	return b
end

-- The frame: wood, trim, crest, title, header buttons, the page and the tabs.
local function buildFrame()
	frame = CreateFrame("Frame", "SmokingGnomesFrame", UIParent, "BackdropTemplate")
	frame:SetSize(W, H)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true) -- comes to the front when clicked
	frame:SetClampedToScreen(true)
	frame:SetClampRectInsets(-14, 0, 14, -32) -- keep the crest and the tabs on screen too
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
	frame:SetBackdropBorderColor(WOOD_EDGE[1], WOOD_EDGE[2], WOOD_EDGE[3], 1)
	frame:Hide()
	tinsert(UISpecialFrames, "SmokingGnomesFrame") -- Escape closes it

	local pos = SG.db.settings.pos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER", 0, 40)
	end

	local trim = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	trim:SetPoint("TOPLEFT", 3, -3)
	trim:SetPoint("BOTTOMRIGHT", -3, 3)
	trim:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	trim:SetBackdropBorderColor(TRIM[1], TRIM[2], TRIM[3], 0.55)

	-- The crest in a gold ring over the top-left corner.
	local ring = CreateFrame("Frame", nil, frame)
	ring:SetSize(48, 48)
	ring:SetPoint("TOPLEFT", -10, 10)
	ring:SetFrameLevel(frame:GetFrameLevel() + 20)
	local outer = disc(ring, 48, "BACKGROUND")
	outer:SetPoint("CENTER")
	outer:SetVertexColor(0.788, 0.651, 0.290)
	local inner = disc(ring, 44, "BORDER")
	inner:SetPoint("CENTER")
	inner:SetVertexColor(0.047, 0.039, 0.031)
	local logo = makeCrest(ring, 44) -- fills the dark disc: the gold ring is its only frame
	logo:SetPoint("CENTER")

	local title = text(frame, 16, TITLE_GOLD)
	title:SetPoint("LEFT", frame, "TOPLEFT", 46, -HEAD_Y)
	title:SetText("Smoking Gnomes Inc.")

	local close = headerButton("Close")
	close.red = true
	close:Paint()
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -HEAD_GAP, -HEAD_GAP)
	close.x = text(close, 15, { 1, 0.85, 0.63 }, "CENTER")
	close.x:SetPoint("CENTER", 0, 1)
	close.x:SetText("×")
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	gear = headerButton("Settings", "Theme, window size and switches.")
	gear:SetPoint("RIGHT", close, "LEFT", -5, 0)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	gear.icon:SetTexture("Interface\\AddOns\\SmokingGnomes\\Media\\gear")
	gear.icon:SetSize(13, 13)
	gear.icon:SetPoint("CENTER")
	gear.icon:SetVertexColor(0.85, 0.77, 0.54)
	gear:SetScript("OnClick", function()
		UI.ShowView("settings", mode ~= "settings")
	end)

	coin = headerButton("Payroll", "Salaries: who earned what last week.")
	coin:SetPoint("RIGHT", gear, "LEFT", -5, 0)
	coin.icon = coin:CreateTexture(nil, "ARTWORK")
	coin.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
	coin.icon:SetSize(12, 12)
	coin.icon:SetPoint("CENTER")
	coin:SetScript("OnClick", function()
		UI.ShowView("payroll", mode ~= "payroll")
	end)

	local headBg = solid(frame, "BORDER")
	headBg:SetPoint("TOPLEFT", 4, -4)
	headBg:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -4, -TITLE_H)
	headBg:SetVertexColor(0, 0, 0, 0.22)

	local div = solid(frame, "ARTWORK")
	div:SetHeight(1)
	div:SetVertexColor(0.227, 0.173, 0.071, 1)
	div:SetPoint("TOPLEFT", INSET, -TITLE_H)
	div:SetPoint("TOPRIGHT", -INSET, -TITLE_H)

	-- The page.
	paper = CreateFrame("Frame", nil, frame)
	paper:SetPoint("TOPLEFT", INSET, -(TITLE_H + 4))
	paper:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	paper.bg = solid(paper, "BACKGROUND")
	paper.bg:SetAllPoints()
	-- Shaded edges: a smooth fade inwards on all four sides.
	local SHADE_W, SHADE_A, BLACK = 22, 0.32, { 0, 0, 0 }
	local top = solid(paper, "BACKGROUND", 1)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(SHADE_W)
	fade(top, "VERTICAL", BLACK, 0, SHADE_A)
	local bottom = solid(paper, "BACKGROUND", 1)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(SHADE_W)
	fade(bottom, "VERTICAL", BLACK, SHADE_A, 0)
	local left = solid(paper, "BACKGROUND", 1)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(SHADE_W)
	fade(left, "HORIZONTAL", BLACK, SHADE_A, 0)
	local right = solid(paper, "BACKGROUND", 1)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(SHADE_W)
	fade(right, "HORIZONTAL", BLACK, 0, SHADE_A)
	paper:EnableMouseWheel(true)
	paper:SetScript("OnMouseWheel", function(_, delta)
		UI.Scroll(-delta)
	end)

	-- Corner grip: drag to change the window size (the same setting as in Settings).
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(paper:GetFrameLevel() + 5)
	grip:SetNormalTexture(386864) -- the chat window's size grabber
	grip:SetPushedTexture(386862)
	grip:SetHighlightTexture(386863)
	local function cursorX()
		return (GetCursorPosition())
	end
	grip:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then
			return
		end
		self.start = { x = cursorX(), scale = SG.db.settings.scale or 1, w = frame:GetWidth() * frame:GetEffectiveScale() }
		self:SetScript("OnUpdate", function()
			local st = self.start
			local v = st.scale * (st.w + cursorX() - st.x) / st.w
			v = math.floor(math.max(0.7, math.min(1.5, v)) * 100 + 0.5) / 100
			if v ~= (SG.db.settings.scale or 1) then
				SG.db.settings.scale = v
				UI.ApplyLook()
			end
		end)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		self.start = nil
		UI.Refresh()
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Drag to resize", 1, 1, 1)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)

	-- Tabs hang below the frame.
	tabs = {}
	for i, t in ipairs(TAB_LIST) do
		local b = makeTab(t[1], t[2])
		if i == 1 then
			b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 1) -- centred by layoutTabs
		else
			b:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", TAB_GAP, 0)
		end
		tabs[i] = b
	end
end

-- Page head (title, status box, note or action, subtitle), the Employee of the Week
-- band, the column header and the rows.
local function buildHead()
	heading = ptext(paper, 18, "accent")
	heading:SetPoint("TOPLEFT", PAD, -16)
	headPill = makePill(paper, 56)
	headPill:SetPoint("LEFT", heading, "RIGHT", 10, 0)
	headRight = ptext(paper, 10, "muted", "RIGHT", NUM)
	headRight:SetPoint("TOPRIGHT", -PAD, -21)
	actionBtn = pageButton(paper, "DONE", "accent")
	actionBtn:SetPoint("TOPRIGHT", -PAD, -16)
	actionBtn:SetScript("OnClick", function()
		if mode == "help" then
			UI.ShowView("settings", true)
		else
			UI.ShowView(mode, false)
		end
	end)
	subtitle = ptext(paper, 11, "muted", "LEFT", NUM)
	subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -5)
	subtitle:SetWidth(CW)
	subtitle:SetWordWrap(true)

	-- Production Report: "This week · All time", plain text. The active one is gold and
	-- underlined, the other muted (lighter on hover).
	periodSwitch = CreateFrame("Frame", nil, paper)
	periodSwitch.buttons = {}
	local prev
	for i, p in ipairs({ { "week", "This week" }, { "all", "All time" } }) do
		local b = CreateFrame("Button", nil, periodSwitch)
		b.key = p[1]
		b.label = ptext(b, 12, nil)
		b.label:SetPoint("LEFT", 0, 1)
		b.label:SetText(p[2])
		b:SetSize(math.ceil(b.label:GetStringWidth()) + 2, 16)
		b.line = solid(b, "ARTWORK")
		b.line:SetHeight(1)
		b.line:SetPoint("BOTTOMLEFT", 0, 0)
		b.line:SetPoint("BOTTOMRIGHT", -2, 0)
		if prev then
			local dot = ptext(periodSwitch, 12, "muted")
			dot:SetPoint("LEFT", prev, "RIGHT", 6, 1)
			dot:SetText("·")
			b:SetPoint("LEFT", dot, "RIGHT", 6, -1)
		else
			b:SetPoint("LEFT", 0, 0)
		end
		b:SetScript("OnClick", function()
			boardPeriod = p[1]
			mode = p[1]
			UI.Refresh()
		end)
		b:SetScript("OnEnter", function(self)
			self.hover = true
			periodSwitch.paint()
		end)
		b:SetScript("OnLeave", function(self)
			self.hover = false
			periodSwitch.paint()
		end)
		periodSwitch.buttons[i] = b
		prev = b
	end
	function periodSwitch.paint()
		for _, b in ipairs(periodSwitch.buttons) do
			local on = b.key == mode
			ink(b.label, on and "gold" or (b.hover and "ink" or "muted"))
			tint(b.line, T.gold)
			b.line:SetShown(on)
		end
	end

	-- Employee of the Week band.
	band = CreateFrame("Frame", nil, paper, "BackdropTemplate")
	band:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	themed(function()
		band:SetBackdropColor(T.bandBg[1], T.bandBg[2], T.bandBg[3], T.bandBg[4])
		band:SetBackdropBorderColor(T.bandEdge[1], T.bandEdge[2], T.bandEdge[3], T.bandEdge[4])
	end)
	band.star = band:CreateTexture(nil, "ARTWORK")
	band.star:SetTexture(STAR_TEX)
	band.star:SetSize(14, 14)
	band.star:SetPoint("LEFT", 8, 0)
	band.label = ptext(band, 11, "muted")
	band.label:SetPoint("LEFT", band.star, "RIGHT", 6, 0)
	band.label:SetText("Employee of the Week")
	band.name = ptext(band, 12, "gold")
	band.name:SetPoint("LEFT", band.label, "RIGHT", 6, 0)
	band.pts = ptext(band, 10, "muted", "RIGHT", NUM)
	band.pts:SetPoint("RIGHT", -10, 0)

	-- Column header.
	heads = CreateFrame("Frame", nil, paper)
	heads.c0 = ptext(heads, 9, "muted", "LEFT", NUM)
	heads.c0:SetPoint("BOTTOMLEFT", 0, 4)
	heads.name = ptext(heads, 9, "muted", "LEFT", NUM)
	heads.c1 = ptext(heads, 9, "muted", "RIGHT", NUM)
	heads.c2 = ptext(heads, 9, "muted", "RIGHT", NUM)
	heads.more = ptext(heads, 9, "muted", "LEFT", NUM)
	heads.more:SetPoint("LEFT", heads.name, "RIGHT", 8, 0)
	heads.line = rule(heads, "hard")
	heads.line:SetPoint("BOTTOMLEFT")
	heads.line:SetPoint("BOTTOMRIGHT")

	rows = {}
	for i = 1, MAX_ROWS do
		rows[i] = makeRow()
	end

	-- The faint dashed line under the top 3.
	dash = CreateFrame("Frame", nil, paper)
	dash:SetHeight(5)
	for i = 0, math.floor(CW / 7) do
		local t = solid(dash, "ARTWORK")
		t:SetSize(4, 1)
		t:SetPoint("LEFT", i * 7, 0)
		themed(function()
			tint(t, T.rule, T.hard * 0.7)
		end)
	end
end

-- The Spies card, the progress strip, the career box, the Field Report boxes, footer.
-- The one-time welcome: what the addon is for, in three steps.
local WELCOME = {
	"Kill Alliance gnomes in the open world. Battlegrounds and arenas don't count.",
	"Every kill scores points on this week's board. The top scorer is Employee of the Week.",
	"Honorable kills (not grey to you) get you promoted. From Test Subject Handler up, your title pays a weekly salary.",
}

local function buildParts()
	-- Welcome page.
	welcome = CreateFrame("Frame", nil, paper)
	welcome.steps = {}
	for i, s in ipairs(WELCOME) do
		local n = ptext(welcome, 13, "gold", "LEFT", NUM)
		n:SetText(i)
		local t = ptext(welcome, 12, "ink")
		t:SetWordWrap(true)
		t:SetWidth(CW - 24)
		t:SetText(s)
		welcome.steps[i] = { n = n, t = t }
	end
	welcome.go = pageButton(welcome, "START HARVESTING", "accent")
	welcome.go:SetScript("OnClick", function()
		mode = "week"
		UI.Refresh()
	end)
	welcome:Hide()

	-- Spies: the most wanted card.
	card = CreateFrame("Frame", nil, paper, "BackdropTemplate")
	card:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	themed(function()
		card:SetBackdropColor(T.red[1], T.red[2], T.red[3], 0.07)
		card:SetBackdropBorderColor(T.red[1], T.red[2], T.red[3], 0.55)
		tint(card.ring, T.red)
	end)
	card.ring = disc(card, 48, "ARTWORK", 0)
	card.ring:SetPoint("LEFT", 9, 0)
	card.portrait = card:CreateTexture(nil, "ARTWORK", nil, 2)
	card.portrait:SetSize(42, 42)
	card.portrait:SetPoint("CENTER", card.ring, "CENTER", 0, 0)
	card.label = ptext(card, 9, "red", "LEFT", NUM)
	card.label:SetPoint("TOPLEFT", 66, -10)
	card.label:SetText("MOST WANTED")
	card.name = ptext(card, 14, "ink")
	card.name:SetPoint("TOPLEFT", 66, -23)
	card.detail = ptext(card, 10, "muted", "LEFT", NUM)
	card.detail:SetPoint("TOPLEFT", 66, -42)
	card.reward = ptext(card, 15, "gold", "RIGHT", NUM)
	card.reward:SetPoint("TOPRIGHT", -10, -20)
	card.rlabel = ptext(card, 8, "muted", "RIGHT", NUM)
	card.rlabel:SetPoint("TOPRIGHT", -10, -40)
	card.x = withdrawButton(card)
	card.x:SetPoint("TOPRIGHT", -2, -2)
	card.rlabel:SetText("REWARD")
	card:EnableMouse(true)
	card:SetScript("OnEnter", rows[1]:GetScript("OnEnter"))
	card:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	card:SetScript("OnMouseUp", rows[1]:GetScript("OnMouseUp"))
	card.bg = solid(card, "BACKGROUND", -1) -- unused by the card, needed by the shared row scripts
	card.bg:Hide()

	-- The progress strip.
	strip = CreateFrame("Frame", nil, paper)
	strip:SetSize(CW, 24)
	strip:SetPoint("BOTTOMLEFT", PAD, 32)
	local stripTop = rule(strip, "soft")
	stripTop:SetPoint("TOPLEFT")
	stripTop:SetPoint("TOPRIGHT")
	strip.left = ptext(strip, 11, "muted")
	strip.left:SetPoint("TOPLEFT", 0, -7)
	strip.right = ptext(strip, 10, "muted", "RIGHT", NARROW)
	strip.right:SetPoint("TOPRIGHT", 0, -8)
	strip.bar = makeBar(strip, 3)
	strip.bar:SetPoint("BOTTOMLEFT")
	strip.bar:SetPoint("BOTTOMRIGHT")
	-- No tooltip here: the full ladder only shows on the Lab Log's "Your career" box.

	-- Lab Log: your career.
	careerBox = CreateFrame("Frame", nil, paper, "BackdropTemplate")
	careerBox:SetSize(CW, 66)
	careerBox:SetPoint("BOTTOMLEFT", PAD, 12)
	careerBox:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	themed(function()
		careerBox:SetBackdropColor(T.ink[1], T.ink[2], T.ink[3], T.wash)
		careerBox:SetBackdropBorderColor(T.rule[1], T.rule[2], T.rule[3], T.soft * 1.8)
	end)
	careerBox.label = ptext(careerBox, 10, "muted")
	careerBox.label:SetPoint("TOPLEFT", 10, -8)
	careerBox.label:SetText("YOUR CAREER")
	careerBox.count = ptext(careerBox, 10, "muted", "RIGHT", NUM)
	careerBox.count:SetPoint("TOPRIGHT", -10, -9)
	careerBox.cur = ptext(careerBox, 12, "accent")
	careerBox.cur:SetPoint("TOPLEFT", 10, -26)
	careerBox.nxt = ptext(careerBox, 12, "ink", "RIGHT")
	careerBox.nxt:SetPoint("TOPRIGHT", -10, -26)
	careerBox.bar = makeBar(careerBox, 6)
	careerBox.bar:SetPoint("LEFT", careerBox.cur, "RIGHT", 10, 0)
	careerBox.bar:SetPoint("RIGHT", careerBox.nxt, "LEFT", -10, 0)
	careerBox.payNow = ptext(careerBox, 10, "muted", "LEFT", NARROW)
	careerBox.payNow:SetPoint("BOTTOMLEFT", 10, 9)
	careerBox.togo = ptext(careerBox, 10, "muted", "CENTER", NARROW)
	careerBox.togo:SetPoint("BOTTOM", 0, 9)
	careerBox.payNext = ptext(careerBox, 10, "muted", "RIGHT", NARROW)
	careerBox.payNext:SetPoint("BOTTOMRIGHT", -10, 9)
	careerBox:EnableMouse(true)
	careerBox:SetScript("OnEnter", ladderTooltip)
	careerBox:SetScript("OnLeave", GameTooltip_Hide)

	-- Field Report: three stat boxes.
	stats = {}
	local boxW = (CW - 16) / 3
	local STAT_LABELS = { { "YOU THIS WEEK", "" }, { "OF THEM GNOMES", "count for points" }, { "YOU LIFETIME", "Alliance" } }
	for i, s in ipairs(STAT_LABELS) do
		local b = CreateFrame("Frame", nil, paper, "BackdropTemplate")
		b:SetSize(boxW, 62)
		b:SetPoint("BOTTOMLEFT", PAD + (i - 1) * (boxW + 8), 34)
		b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		themed(function()
			b:SetBackdropColor(T.ink[1], T.ink[2], T.ink[3], T.wash)
			b:SetBackdropBorderColor(T.rule[1], T.rule[2], T.rule[3], T.soft * 1.8)
		end)
		b.label = ptext(b, 8, "muted", "LEFT", NUM)
		b.label:SetPoint("TOPLEFT", 8, -8)
		b.label:SetText(s[1])
		b.value = ptext(b, 18, i == 2 and "accent" or "ink", "LEFT", NUM)
		b.value:SetPoint("TOPLEFT", 8, -21)
		b.sub = ptext(b, 9, "muted", "LEFT", NUM)
		b.sub:SetPoint("BOTTOMLEFT", 8, 8)
		b.sub:SetText(s[2])
		b:Hide()
		stats[i] = b
	end
	statsNote = ptext(paper, 10, "muted", "LEFT", NUM)
	statsNote:SetPoint("BOTTOMLEFT", PAD, 32)
	statsNote:SetText("Points, titles and salaries still count gnomes only.")

	footL = ptext(paper, 10, "muted", "LEFT", NUM)
	footL:SetPoint("BOTTOMLEFT", PAD, 12)
	footR = ptext(paper, 10, "muted", "RIGHT", NUM)
	footR:SetPoint("BOTTOMRIGHT", -PAD, 12)

	empty = ptext(paper, 12, "muted", "CENTER")
	empty:SetPoint("TOP", 0, -80)
	empty:SetWidth(CW - 20)
	empty:SetWordWrap(true)
end

local function refreshWelcome()
	SG.db.settings.welcomed = true -- shown once; /gnomes welcome brings it back
	setHead("WELCOME ABOARD", nil, "Smoking Gnomes Inc. pays you to harvest gnomes.")
	local y = 0
	for _, step in ipairs(welcome.steps) do
		step.n:ClearAllPoints()
		step.n:SetPoint("TOPLEFT", 0, -y)
		step.t:ClearAllPoints()
		step.t:SetPoint("TOPLEFT", 24, -y - 1)
		y = y + math.ceil(step.t:GetStringHeight()) + 16
	end
	welcome.go:ClearAllPoints()
	welcome.go:SetPoint("TOPLEFT", 24, -(y + 2))
	place(welcome, y + 22)
	footL:SetText("/gnomes welcome shows this again")
end

local function build()
	buildFrame()
	buildHead()
	buildParts()
	buildForm()
	buildSettings()
	buildHelp()
	frame:SetScript("OnShow", function()
		savePosition() -- older saved positions were centred; anchor by the top-left from now on
		UI.Refresh()
	end)
end

---------------------------------------------------------------------------
-- Theme, look and refresh
---------------------------------------------------------------------------

-- Window size and background opacity, for this window and the gank panel.
function UI.ApplyLook()
	if not frame then
		return
	end
	local s = SG.db.settings
	local a = s.opacity or 0.98
	local old, new = frame:GetScale(), s.scale or 1
	if old ~= new then
		local l, t = frame:GetLeft(), frame:GetTop()
		frame:SetScale(new)
		if l and t then
			l, t = l * old / new, t * old / new
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
			s.pos = { "TOPLEFT", "BOTTOMLEFT", l, t }
		end
	end
	frame:SetBackdropColor(WOOD[1], WOOD[2], WOOD[3], a)
	paper.bg:SetVertexColor(T.paper[1], T.paper[2], T.paper[3], a)
	if ns.Gank and ns.Gank.ApplyLook then
		ns.Gank.ApplyLook()
	end
end

-- Paints every themed part (one theme now: the dark page).
function UI.ApplyTheme()
	T = THEMES.dark
	if not frame then
		return
	end
	for _, fn in ipairs(themers) do
		fn()
	end
	UI.ApplyLook()
	UI.Refresh()
end

local function hidePage()
	for _, part in ipairs({ periodSwitch, band, heads, dash, card, strip, careerBox, statsNote, form, settingsPanel, helpPanel, welcome,
		commandsBtn, empty, headPill, headRight, actionBtn }) do
		part:Hide()
	end
	for _, s in ipairs(stats) do
		s:Hide()
	end
	for _, r in ipairs(rows) do
		r:Hide()
	end
	heads.more:Hide()
	footL:SetText("")
	footR:SetText("")
	pageTotal, pageVisible = 0, PAGE_ROWS
end

function UI.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	champion = SG.lastWeekWinner()
	UI.RefreshCrests() -- tabard data can arrive after login
	hidePage()

	coin.active = mode == "payroll"
	coin:Paint()
	gear.active = mode == "settings" or mode == "help"
	gear:Paint()
	for _, t in ipairs(tabs) do
		paintTab(t)
	end
	layoutTabs()

	if mode == "settings" then
		setHead("SETTINGS", nil, "Saved for all your characters.")
		actionBtn:SetLabel("DONE")
		actionBtn:Show()
		settingsPanel.update()
		place(settingsPanel)
		commandsBtn:Show()
		footR:SetText(SG.RELEASE == "dev" and "" or ("v" .. SG.RELEASE))
	elseif mode == "help" then
		setHead("SLASH COMMANDS", nil, "Type these in chat.")
		actionBtn:SetLabel("< SETTINGS")
		actionBtn:Show()
		place(helpPanel)
		footL:SetText("/gnomes help lists everything in chat")
	elseif mode == "recall" then
		refreshRecalls()
	elseif mode == "mine" then
		refreshMine()
	elseif mode == "payroll" then
		refreshPayroll()
	elseif mode == "welcome" then
		refreshWelcome()
	else
		refreshBoard()
	end
	fitHeight()
end

-- /gnomes fonts: every built-in font the game accepts, each showing a sample line.
local FONT_CANDIDATES = {
	{ "Friz Quadrata (now: names, titles)", "Fonts\\FRIZQT__.TTF" },
	{ "Arial Narrow (now: numbers)", "Fonts\\ARIALN.TTF" },
	{ "Morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "Skurri", "Fonts\\skurri.ttf" },
	{ "Nimrod", "Fonts\\NIM_____.ttf" },
	{ "2002", "Fonts\\2002.ttf" },
	{ "2002 Bold", "Fonts\\2002B.ttf" },
	{ "AR Hei", "Fonts\\ARHei.ttf" },
	{ "AR Kai", "Fonts\\ARKai_T.ttf" },
	{ "AR Kai C", "Fonts\\ARKai_C.ttf" },
	{ "Korean page text", "Fonts\\K_Pagetext.TTF" },
	{ "Korean damage", "Fonts\\K_Damage.TTF" },
	{ "blei00d", "Fonts\\blei00d.TTF" },
}
local fontSheet
function UI.FontPreview()
	if fontSheet then
		fontSheet:SetShown(not fontSheet:IsShown())
		return
	end
	fontSheet = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	fontSheet:SetFrameStrata("DIALOG")
	fontSheet:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	fontSheet:SetBackdropColor(0.122, 0.102, 0.078, 0.98)
	fontSheet:SetBackdropBorderColor(TRIM[1], TRIM[2], TRIM[3], 0.8)
	fontSheet:SetPoint("CENTER")
	fontSheet:EnableMouse(true)
	fontSheet:SetScript("OnMouseUp", function(self)
		self:Hide()
	end)
	local y, missing = 14, {}
	for _, f in ipairs(FONT_CANDIDATES) do
		local sample = fontSheet:CreateFontString(nil, "OVERLAY")
		if sample:SetFont(f[2], 15, "") then
			local label = fontSheet:CreateFontString(nil, "OVERLAY")
			label:SetFont(NARROW, 10, "")
			label:SetTextColor(0.659, 0.596, 0.471)
			label:SetPoint("TOPLEFT", 16, -y)
			label:SetText(f[1])
			sample:SetTextColor(0.918, 0.875, 0.784)
			sample:SetPoint("TOPLEFT", 16, -(y + 13))
			sample:SetText("PRODUCTION REPORT   Zazzin Zoldyck   3.25   16 gnomes")
			y = y + 13 + math.ceil(sample:GetStringHeight()) + 12
		else
			sample:Hide()
			missing[#missing + 1] = f[1]
		end
	end
	local foot = fontSheet:CreateFontString(nil, "OVERLAY")
	foot:SetFont(NARROW, 10, "")
	foot:SetTextColor(0.659, 0.596, 0.471)
	foot:SetPoint("TOPLEFT", 16, -y)
	foot:SetText((#missing > 0 and ("Not in this client: " .. table.concat(missing, ", ") .. ".  ") or "") .. "Click to close.")
	fontSheet:SetSize(460, y + 30)
end

function UI.Toggle()
	if not frame then
		return
	end
	frame:SetShown(not frame:IsShown())
end

-- Open the window on the Commands, Settings or Payroll view (show = true), or go back
-- to the last tab.
function UI.ShowView(view, show)
	if not frame then
		return
	end
	if show then
		if mode ~= "help" and mode ~= "settings" and mode ~= "payroll" and mode ~= "welcome" then
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
	toast:SetFrameStrata("DIALOG")
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
	-- Logo and text side by side, centred as one group. The logo sits left of the widest
	-- line, so a long detail line can't run underneath it.
	local LOGO_W, GAP = 36, 10
	local w = math.max(toast.main:GetStringWidth(), toast.sub:GetStringWidth(), toast.note:GetStringWidth())
	local shift = (LOGO_W + GAP) / 2
	toast.main:ClearAllPoints()
	toast.main:SetPoint("TOP", toast, "TOP", shift, 0)
	toast.logo:ClearAllPoints()
	toast.logo:SetPoint("RIGHT", toast, "TOP", shift - w / 2 - GAP, -26)
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
		local _, _, _, pay = SG.jobTitle(SG.myName, SG.honorCount(e))
		note = pay > 0 and ("Salary now %s a week. HR has been notified."):format(SG.money(pay))
			or ("%d honorable gnomes. HR has been notified."):format(SG.honorCount(e))
	elseif info.assist then
		main, color, note = "Gnome assist", "white", "Sample sent to the lab."
	else
		main, color = "Gnome smoked!", "green"
		if info.points then
			parts[#parts + 1] = "+" .. SG.points(info.points) .. " pts"
		end
		parts[#parts + 1] = e.week .. " this week"
		if info.honorable == false then
			note = "Grey gnome: no credit toward promotion."
		else
			note = LAB_NOTES[math.random(#LAB_NOTES)]
		end
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
	-- Every guild member gets the line, addon or not: their title from their numbers if
	-- we have them, else Unpaid Intern (or CEO for the guild master).
	local e = SG.db.players[full]
	local member = e ~= nil or (SG.roster and SG.roster[full] ~= nil)
	if not member and SG.roster then
		for rosterName in pairs(SG.roster) do
			if SG.sameName(rosterName, full) then
				member = true
				break
			end
		end
	end
	if member then
		tt:AddLine(SG.jobTitle(full, SG.honorCount(e)) .. " at Smoking Gnomes Inc.", ACCENT[1], ACCENT[2], ACCENT[3])
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

	-- The standard gold minimap ring, exactly as LibDBIcon draws it, so the button matches
	-- every other addon's. Media\minimap is the logo's white disc and gnome without the
	-- logo's own bronze rim (that showed as a second ring inside this one).
	-- Forever draws the modern ring art: measured against the other addons' buttons in
	-- the same bar, the older "Classic" sizes (53 px ring, icon at 7,-6) came out bigger
	-- and 1-2 px off. These are the sizes the other buttons use, on every client.
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(24, 24)
	bg:SetPoint("CENTER", 0, 1)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\AddOns\\SmokingGnomes\\Media\\minimap")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", 0, 1)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")

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
	local s = SG.db.settings
	-- A bit bigger by default: 105% (once; a bigger size someone chose stays). 115% from
	-- an earlier test build was too big, so that one steps down.
	if not s.sizeV3 then
		if s.sizeV2 and s.scale == 1.15 then
			s.scale = 1.05
		else
			s.scale = math.max(s.scale or 1, 1.05)
		end
		s.sizeV3 = true
	end
	if not s.welcomed then
		mode = "welcome" -- the first time the window opens
	end
	if not frame then
		build()
		hookTooltips()
		buildMinimapButton()
		UI.ApplyTheme()
	end
end

function SmokingGnomes_OnAddonCompartmentClick()
	UI.Toggle()
end

function SmokingGnomes_OnAddonCompartmentEnter(_, button)
	local e = SG.me()
	GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
	GameTooltip:AddLine("Smoking Gnomes Inc.", 1, 1, 1)
	GameTooltip:AddLine(("%s  ·  %d this week (%s pts)"):format(SG.jobTitle(SG.myName, SG.honorCount(e)), e.week, SG.points(e.wp)), ACCENT[1], ACCENT[2], ACCENT[3])
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
