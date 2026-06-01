-- Standalone NoobTaco-Config window — NoobTaco's layout system is
-- designed to own its host window (custom themed buttons, sidebar
-- scrollbar, Poppins fonts), so embedding it inside Blizzard's
-- RegisterCanvasLayoutCategory fights the lib's design. We host it in
-- our own draggable popup and open it from /dscd.
--
-- Left column (sidebar): General / Spells / About section buttons.
-- Right column (content): re-rendered every time the user clicks a
-- section. Static sections (General, About) go through NoobTaco-Config's
-- schema renderer; the Spells section's spec dropdown + per-row spell
-- list + override editbox stay imperative because the schema doesn't
-- model "table of dynamic composite rows".
--
-- Icon size / spacing / grow / X/Y offset live in Edit Mode now (see
-- Anchor.lua's plugin panel via FerrozEditModeLib), so the Settings
-- panel no longer owns those controls.

local addonName, ns = ...

local NTC = LibStub("NoobTaco-Config-1.0", true)
local Layout, Renderer, ConfigState
if NTC then
	Layout = NTC.Layout
	Renderer = NTC.Renderer
	ConfigState = NTC.State

	-- NoobTaco-Config's NoobTaco-Config.lua hardcodes the embed media
	-- path as Interface\AddOns\<addon>\Libraries\NoobTaco-Config\Media.
	-- We embed at Libs\, not Libraries\, so Theme.Fonts ends up pointing
	-- at a non-existent .ttf and Theme:CreateThemedButton errors with
	-- "Invalid font file asset". Patch NTC.Media + Theme.Fonts in place
	-- so every downstream Theme:ApplyFont call resolves correctly.
	local realMedia = "Interface\\AddOns\\" .. addonName .. "\\Libs\\NoobTaco-Config\\Media"
	NTC.Media = realMedia
	if NTC.Theme then
		NTC.Theme.Fonts = {
			Normal    = realMedia .. "\\Fonts\\Poppins-Medium.ttf",
			Bold      = realMedia .. "\\Fonts\\Poppins-Bold.ttf",
			ExtraBold = realMedia .. "\\Fonts\\Poppins-ExtraBold.ttf",
		}
	end
end

local UNKNOWN_ICON = 134400
local ROW_HEIGHT = 26
local ROW_GAP = 2
local LIST_INSET = 16

-- ============================================================
-- STANDALONE WINDOW — movable + closable popup, opened from /dscd.
-- NoobTaco-Config's two-column layout attaches inside `body` so
-- the title bar + close button sit outside the lib's layout area.
-- ============================================================

local optionsFrame = CreateFrame("Frame", "DzakSharedCDsOptionsFrame", UIParent, "BackdropTemplate")
optionsFrame:Hide()
optionsFrame:SetSize(720, 600)
optionsFrame:SetPoint("CENTER")
optionsFrame:SetFrameStrata("HIGH")
optionsFrame:SetClampedToScreen(true)
optionsFrame:SetBackdrop({
	bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
	edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
	edgeSize = 16,
	insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
optionsFrame:SetBackdropColor(0, 0, 0, 0.92)

-- Drag-to-move from the title bar area.
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)

local titleBar = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleBar:SetPoint("TOP", optionsFrame, "TOP", 0, -12)
titleBar:SetText("DzakSharedCDs")

local closeBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -4, -4)

-- NoobTaco's Layout:CreateTwoColumnLayout uses SetAllPoints on its
-- container — so we host it inside `body`, which insets to leave room
-- for our title bar and frame border.
local body = CreateFrame("Frame", nil, optionsFrame)
body:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 10, -36)
body:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -10, 10)

local layoutContainer = nil
local currentSpecId = nil
local sectionRenderers = {} -- id -> function(content) builder

-- ============================================================
-- SCHEMAS (consumed by NoobTaco-Config's Renderer)
-- ============================================================

local SLASH_HELP_LINES = {
	"|cff66ddff/dscd|r — open this settings panel",
	"|cff66ddff/dscd status|r — print state summary",
	"|cff66ddff/dscd init|r — print what your next INIT broadcasts",
	"|cff66ddff/dscd broadcast|r — force an INIT now",
	"|cff66ddff/dscd ping|r — transport delivery test",
	"|cff66ddff/dscddebug|r — toggle debug tracing",
}

local function GeneralSchema()
	return {
		type = "group",
		children = {
			{ type = "header",      label = "General" },
			{ type = "description", text = "Broadcasts your tracked spell cooldowns to addon-using party members and renders theirs on the party / raid frames. Use the |cffffd100Display|r tab to configure icon size, spacing, and visual style; the |cffffd100Spells|r tab to edit per-spec tracked spells and per-spell CD overrides." },
			{ type = "checkbox",
			  id = "DzakSharedCDsDB.enabled",
			  label = "Enabled",
			  default = true,
			  onChange = function(v) ns.SetEnabled(v) end,
			},
			{ type = "header",      label = "Slash commands" },
			{ type = "description", text = table.concat(SLASH_HELP_LINES, "\n") },
		},
	}
end

-- Shared onChange factory: forwards the new value into ns.SetDisplaySetting
-- under the matching key, which writes the DB and triggers Display:UpdateAll
-- for live-preview behaviour. We intentionally bypass NoobTaco-Config's
-- State (TempConfig/Commit) on these because we want every slider drag to
-- repaint the icons immediately, not wait for a Commit step.
local function dispOnChange(key)
	return function(value) ns.SetDisplaySetting(key, value) end
end

local function DisplaySchema()
	return {
		type = "group",
		children = {
			{ type = "header",      label = "Layout" },
			{ type = "slider",
			  id = "DzakSharedCDsDB.display.iconSize",
			  label = "Icon size",
			  min = 12, max = 64, step = 1,
			  default = ns.DEFAULT_DISPLAY.iconSize,
			  onChange = dispOnChange("iconSize") },
			{ type = "slider",
			  id = "DzakSharedCDsDB.display.iconGap",
			  label = "Icon spacing",
			  min = 0, max = 16, step = 1,
			  default = ns.DEFAULT_DISPLAY.iconGap,
			  onChange = dispOnChange("iconGap") },
			-- anchorSide picks which edge of the party frame the row
			-- attaches to. growDirection picks which way icons grow
			-- from there. Combining them gives all four outside/inside
			-- × left/right layouts.
			{ type = "dropdown",
			  id = "DzakSharedCDsDB.display.anchorSide",
			  label = "Anchor side",
			  default = ns.DEFAULT_DISPLAY.anchorSide,
			  options = {
				{ value = "RIGHT", label = "Right edge of party frame" },
				{ value = "LEFT",  label = "Left edge of party frame" },
			  },
			  onChange = dispOnChange("anchorSide") },
			{ type = "dropdown",
			  id = "DzakSharedCDsDB.display.growDirection",
			  label = "Grow direction",
			  default = ns.DEFAULT_DISPLAY.growDirection,
			  options = {
				{ value = "RIGHT", label = "Right (icons fan out rightward)" },
				{ value = "LEFT",  label = "Left (icons fan out leftward)" },
			  },
			  onChange = dispOnChange("growDirection") },
			{ type = "slider",
			  id = "DzakSharedCDsDB.display.offsetX",
			  label = "Offset X (positive = into frame)",
			  min = -100, max = 100, step = 1,
			  default = ns.DEFAULT_DISPLAY.offsetX,
			  onChange = dispOnChange("offsetX") },
			{ type = "slider",
			  id = "DzakSharedCDsDB.display.offsetY",
			  label = "Offset Y",
			  min = -100, max = 100, step = 1,
			  default = ns.DEFAULT_DISPLAY.offsetY,
			  onChange = dispOnChange("offsetY") },

			{ type = "header",      label = "Visual" },
			{ type = "slider",
			  id = "DzakSharedCDsDB.display.borderSize",
			  label = "Border thickness",
			  min = 0, max = 4, step = 1,
			  default = ns.DEFAULT_DISPLAY.borderSize,
			  onChange = dispOnChange("borderSize") },
			{ type = "description", text = "|cff888888Border color is currently black — edit DzakSharedCDsDB.display.borderColorR/G/B/A manually for custom colors (NoobTaco-Config's colorpicker is a stub in this version).|r" },
			{ type = "checkbox",
			  id = "DzakSharedCDsDB.display.cdGrayout",
			  label = "Gray out icons while on cooldown",
			  default = ns.DEFAULT_DISPLAY.cdGrayout,
			  onChange = dispOnChange("cdGrayout") },
			{ type = "checkbox",
			  id = "DzakSharedCDsDB.display.cdShowMinutes",
			  label = "Show minutes (\"5m\") when cooldown >= 60s",
			  default = ns.DEFAULT_DISPLAY.cdShowMinutes,
			  onChange = dispOnChange("cdShowMinutes") },
			{ type = "slider",
			  id = "DzakSharedCDsDB.display.cdTextFontSize",
			  label = "Cooldown text font size",
			  min = 8, max = 24, step = 1,
			  default = ns.DEFAULT_DISPLAY.cdTextFontSize,
			  onChange = dispOnChange("cdTextFontSize") },

			{ type = "header",      label = "Reset" },
			{ type = "button",
			  label = "Reset display defaults",
			  onClick = function()
				ns.ResetDisplayDefaults()
				-- Re-render the Display section so the live slider values
				-- snap back to defaults too.
				if sectionRenderers.display and layoutContainer then
					sectionRenderers.display(layoutContainer.ContentChild)
				end
			  end },
		},
	}
end

local function AboutSchema()
	local version = C_AddOns and C_AddOns.GetAddOnMetadata
		and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
	return {
		type = "group",
		children = {
			{ type = "header",      label = "DzakSharedCDs " .. version },
			{ type = "description", text = "A small party-cooldown tracker that broadcasts your tracked spells to addon-using party members and shows theirs back. Hidden CHAT_MSG_ADDON prefix \"DSCD\", per-spec defaults, INIT handshake for talent filtering." },
			{ type = "header",      label = "Reference projects" },
			{ type = "description", text = "MiniCC (visual reference) · DzakTools (skeleton template) · LuraMemorySync (comm pattern reference)" },
		},
	}
end

-- ============================================================
-- SPELLS SECTION — built imperatively because NoobTaco-Config's
-- schema doesn't model dynamic per-row composite widgets (icon +
-- label + override editbox + remove button per spell).
-- ============================================================

local function FormatLine(id)
	local info = C_Spell.GetSpellInfo(id)
	local name = info and info.name or "(unknown)"
	return string.format("|cffffff00%d|r  %s", id, name), info and info.iconID or UNKNOWN_ICON
end

-- Flat list of every spec for the dropdown, sorted by className then
-- specName. We drop the original 2-level (class -> spec) submenu pattern
-- because NoobTaco-Config's dropdown is flat anyway and a single sorted
-- list is fine at 39 entries.
local function FlatSpecOptions()
	local out = {}
	for _, info in ipairs(ns.ALL_SPECS) do
		out[#out + 1] = {
			value = info.specId,
			label = info.className .. " - " .. info.specName,
		}
	end
	return out
end

-- Row layout post-v0.11: just icon + label + remove button. The CD
-- override editbox is gone — senders now broadcast the authoritative
-- post-cast duration on the wire (Tracker.OnLocalCast / Chat USED
-- format), so receivers don't need a per-spell override mechanism.
-- The row anchors LEFT+RIGHT to its parent in RebuildList so width
-- auto-tracks the list frame even if Blizzard's layout hasn't passed.
local function MakeSpellRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.remove:SetSize(28, 22)
	row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.remove:SetText("X")

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	return row
end

-- v0.11.0 rewrite. Key change: drop the inner UIPanelScrollFrame entirely
-- and let rows stack directly inside `section`. The previous nested-scroll
-- layout was fragile — the inner scroll's `GetWidth() - 20` returned 0 at
-- build time (its anchors hadn't resolved yet inside a 1-pixel section),
-- so listChild ended up with negative width and rows rendered invisibly.
-- Now: `section` grows as rows are added, and NoobTaco-Config's outer
-- ScrollFrame (its `Content` ScrollFrame around `ContentChild`) handles
-- overflow. We tell it about our total height by setting content's size
-- at the end of RebuildList.
local function BuildSpellsSection(content)
	-- Tear down any prior spells section so re-entering the tab gets a
	-- fresh tree (the schema-managed frames are released by the caller
	-- before we run; we only need to clean OUR `_dscdSpellsSection`).
	for _, child in ipairs({ content:GetChildren() }) do
		if child._dscdSpellsSection then
			child:Hide()
			child:SetParent(nil)
		end
	end

	local section = CreateFrame("Frame", nil, content)
	section._dscdSpellsSection = true
	section:SetPoint("TOPLEFT",  content, "TOPLEFT",  LIST_INSET, -LIST_INSET)
	section:SetPoint("TOPRIGHT", content, "TOPRIGHT", -LIST_INSET, -LIST_INSET)
	-- Section's height is set in RebuildList once we know the row count.

	-- ── Section header ─────────────────────────────────────────────────
	local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
	header:SetText("Tracked spells")

	-- ── Spec dropdown (flat list) ──────────────────────────────────────
	local specLabel = section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	specLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
	specLabel:SetText("Spec:")

	-- Anonymous dropdown to avoid the global-name collision on re-entry
	-- (the previous "DzakSharedCDsSpecDropdown" was registered on every
	-- BuildSpellsSection call, with the old frame leaking into _G).
	local specDropdown = CreateFrame("Frame", nil, section, "UIDropDownMenuTemplate")
	specDropdown:SetPoint("LEFT", specLabel, "RIGHT", -8, -2)

	local RebuildList -- forward decl
	local function OnSpecSelected(specId)
		currentSpecId = specId
		ns.EnsureSpecSeeded(specId)
		UIDropDownMenu_SetSelectedValue(specDropdown, specId)
		UIDropDownMenu_SetText(specDropdown, ns.FormatSpecLabel(specId))
		if RebuildList then RebuildList() end
	end

	UIDropDownMenu_Initialize(specDropdown, function()
		for _, opt in ipairs(FlatSpecOptions()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text    = opt.label
			info.value   = opt.value
			info.checked = (opt.value == currentSpecId)
			info.func    = function() OnSpecSelected(opt.value) end
			UIDropDownMenu_AddButton(info)
		end
	end)
	UIDropDownMenu_SetWidth(specDropdown, 220)

	-- ── Add input + buttons ────────────────────────────────────────────
	local idInput = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
	idInput:SetSize(120, 22)
	idInput:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 16, -22)
	idInput:SetAutoFocus(false)
	idInput:SetNumeric(true)
	idInput:SetMaxLetters(8)
	idInput:SetTextInsets(4, 4, 0, 0)

	local idLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	idLabel:SetPoint("BOTTOMLEFT", idInput, "TOPLEFT", -4, 2)
	idLabel:SetText("Spell ID")

	local addBtn = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
	addBtn:SetSize(70, 22)
	addBtn:SetPoint("LEFT", idInput, "RIGHT", 8, 0)
	addBtn:SetText("Add")

	local resetBtn = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
	resetBtn:SetSize(140, 22)
	resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
	resetBtn:SetText("Reset This Spec")

	-- ── Row list container ─────────────────────────────────────────────
	-- Plain Frame (no ScrollFrame). Rows attach to its TOPLEFT/TOPRIGHT
	-- so width tracks the list. Height grows with row count.
	local listFrame = CreateFrame("Frame", nil, section)
	listFrame:SetPoint("TOPLEFT",  idInput, "BOTTOMLEFT", -8, -12)
	listFrame:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
	listFrame:SetHeight(1)

	local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
	listBg:SetAllPoints()
	listBg:SetColorTexture(0, 0, 0, 0.3)

	-- Height of all the chrome (header + dropdown + add-input row +
	-- listFrame gap). Used to size `content` at the bottom of RebuildList.
	local CHROME_HEIGHT = 24  -- header
	                  + 10  -- gap
	                  + 22  -- dropdown
	                  + 24  -- idInput row
	                  + 12  -- gap
	                  + LIST_INSET * 2

	local rowPool = {}

	RebuildList = function()
		for _, r in ipairs(rowPool) do r:Hide() end
		if not currentSpecId then
			listFrame:SetHeight(1)
			content:SetSize(content:GetWidth(), CHROME_HEIGHT + 1)
			return
		end

		local tracked = ns.GetTrackedForSpec(currentSpecId) or {}
		local sorted = {}
		for id in pairs(tracked) do sorted[#sorted + 1] = id end
		table.sort(sorted)

		for i, id in ipairs(sorted) do
			local row = rowPool[i]
			if not row then
				row = MakeSpellRow(listFrame)
				rowPool[i] = row
			end
			local yOff = -(i - 1) * (ROW_HEIGHT + ROW_GAP) - 2
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT",  listFrame, "TOPLEFT",  4, yOff)
			row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -4, yOff)
			row:Show()

			local text, iconID = FormatLine(id)
			row.icon:SetTexture(iconID)
			row.label:SetText(text)

			local specForCallback = currentSpecId
			row.remove:SetScript("OnClick", function()
				ns.RemoveTracked(specForCallback, id)
				RebuildList()
			end)
		end

		local listHeight = math.max(4, #sorted * (ROW_HEIGHT + ROW_GAP) + 4)
		listFrame:SetHeight(listHeight)

		-- Grow NoobTaco-Config's ContentChild so the outer ScrollFrame's
		-- range covers our whole section. content's width is preserved.
		content:SetSize(content:GetWidth(), CHROME_HEIGHT + listHeight)
	end

	-- ── Handlers ───────────────────────────────────────────────────────
	local function AddFromInput()
		if not currentSpecId then
			print("|cffff5555DzakSharedCDs:|r pick a spec first")
			return
		end
		local id = tonumber(idInput:GetText())
		if not id or id <= 0 then
			print("|cffff5555DzakSharedCDs:|r invalid spell ID")
			return
		end
		ns.AddTracked(currentSpecId, id)
		idInput:SetText("")
		idInput:ClearFocus()
		RebuildList()
	end

	addBtn:SetScript("OnClick", AddFromInput)
	idInput:SetScript("OnEnterPressed", AddFromInput)
	idInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	resetBtn:SetScript("OnClick", function()
		if not currentSpecId then return end
		ns.ResetSpecToDefaults(currentSpecId)
		RebuildList()
	end)

	-- ── Initial selection ─────────────────────────────────────────────
	if not currentSpecId then
		currentSpecId = ns.SpecCache:GetLocalSpec() or ns.ALL_SPECS[1].specId
	end
	ns.EnsureSpecSeeded(currentSpecId)
	UIDropDownMenu_SetSelectedValue(specDropdown, currentSpecId)
	UIDropDownMenu_SetText(specDropdown, ns.FormatSpecLabel(currentSpecId))
	RebuildList()
end

-- ============================================================
-- SECTION DISPATCH
-- ============================================================

sectionRenderers.general = function(content)
	for _, child in ipairs({ content:GetChildren() }) do
		if child._dscdSpellsSection then
			child:Hide()
			child:SetParent(nil)
		end
	end
	if Renderer and layoutContainer then
		Renderer:Render(GeneralSchema(), layoutContainer)
	end
end

sectionRenderers.spells = function(content)
	if Renderer and layoutContainer then
		-- Releases schema-managed frames AND resets ContentChild to 1x1.
		Renderer:Clear(layoutContainer)
	end
	-- Resolve content's WIDTH now so BuildSpellsSection's anchors land in
	-- a non-1px region. Its RebuildList will set the HEIGHT dynamically
	-- once it knows the row count (replaces the old fixed-520 estimate).
	if layoutContainer and layoutContainer.Content then
		layoutContainer:GetRect()
		layoutContainer.Content:GetRect()
		local width = layoutContainer.Content:GetWidth()
		if width < 200 then
			local parentWidth = layoutContainer:GetWidth()
			width = (parentWidth > 200) and (parentWidth - 250) or 550
		end
		content:SetSize(width, 1)
	end
	BuildSpellsSection(content)
end

sectionRenderers.about = function(content)
	for _, child in ipairs({ content:GetChildren() }) do
		if child._dscdSpellsSection then
			child:Hide()
			child:SetParent(nil)
		end
	end
	if Renderer and layoutContainer then
		Renderer:Render(AboutSchema(), layoutContainer)
	end
end

sectionRenderers.display = function(content)
	for _, child in ipairs({ content:GetChildren() }) do
		if child._dscdSpellsSection then
			child:Hide()
			child:SetParent(nil)
		end
	end
	if Renderer and layoutContainer then
		Renderer:Render(DisplaySchema(), layoutContainer)
	end
end

-- ============================================================
-- BUILD THE LAYOUT ON FIRST SHOW
-- ============================================================

local function EnsureLayout()
	if layoutContainer then return end
	if not Layout then
		-- NoobTaco-Config didn't load — emit a stub message.
		local fs = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("CENTER")
		fs:SetText("NoobTaco-Config missing — Settings UI not available.\nUse /dscd commands.")
		return
	end

	-- NoobTaco-Config's State is bound to the addon's DB so its schema
	-- widgets read/write through dotted paths like "DzakSharedCDsDB.enabled".
	if ConfigState and DzakSharedCDsDB then
		ConfigState:Initialize(DzakSharedCDsDB)
	end

	layoutContainer = Layout:CreateTwoColumnLayout(body)

	Layout:AddSidebarButton(layoutContainer, "general", "General", function()
		sectionRenderers.general(layoutContainer.ContentChild)
	end)
	Layout:AddSidebarButton(layoutContainer, "display", "Display", function()
		sectionRenderers.display(layoutContainer.ContentChild)
	end)
	Layout:AddSidebarButton(layoutContainer, "spells", "Spells", function()
		sectionRenderers.spells(layoutContainer.ContentChild)
	end)
	Layout:AddSidebarButton(layoutContainer, "about", "About", function()
		sectionRenderers.about(layoutContainer.ContentChild)
	end)

	-- Default section.
	Layout:SelectSidebarButton(layoutContainer, "general")
	sectionRenderers.general(layoutContainer.ContentChild)
end

optionsFrame:SetScript("OnShow", EnsureLayout)

-- ============================================================
-- /dscd ENTRY POINT
-- /dscd → toggle the window. NoobTaco's Layout is built lazily on
-- first show; subsequent opens just :Show() the existing frame.
-- ============================================================

ns.OpenSettings = function()
	if optionsFrame:IsShown() then
		optionsFrame:Hide()
	else
		optionsFrame:Show()
	end
end
