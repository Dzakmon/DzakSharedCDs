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

-- Row layout: checkbox + icon + label. The checkbox toggles tracking
-- (Add/RemoveTracked) for the spell in the current spec. No add/remove
-- via spell ID input anymore — users just toggle the default set.
local function MakeSpellRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_HEIGHT)

	row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.cb:SetSize(22, 22)
	row.cb:SetPoint("LEFT", row, "LEFT", 2, 0)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	return row
end

-- v0.12 simplification: ditch the spell-ID input. The Spells tab now
-- just lists every spell in the current spec's default set, each with a
-- checkbox controlling whether it's tracked. "Reset This Spec" puts the
-- DB back in sync with ns.DEFAULT_SPELLS_BY_SPEC.
--
-- Layout strategy: every internal frame uses TOPLEFT + TOPRIGHT anchors
-- at the SAME Y. Past blank-tab bugs came from mismatched Y values on
-- TOPLEFT vs TOPRIGHT pushing frames behind each other. Y positions
-- below are tracked by a running `cursorY` so the chain stays consistent.
local CHROME_HEADER     = 0
local CHROME_SUBTITLE_Y = 28
local CHROME_DROPDOWN_Y = 78
local CHROME_LIST_Y     = 116 -- top of the spell list

local function BuildSpellsSection(content)
	-- Tear down any prior spells section so re-entering the tab gets a
	-- fresh tree.
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
	-- Section height set at end of RebuildList.

	-- ── Header ─────────────────────────────────────────────────────────
	local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -CHROME_HEADER)
	header:SetText("Tracked spells")

	-- ── Subtitle ───────────────────────────────────────────────────────
	local subtitle = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	subtitle:SetPoint("TOPLEFT",  section, "TOPLEFT",  0, -CHROME_SUBTITLE_Y)
	subtitle:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -CHROME_SUBTITLE_Y)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetWordWrap(true)
	subtitle:SetText("Toggle which of your spec's default cooldowns to broadcast. Disabled spells stop appearing in your next INIT and on other players' frames.")
	subtitle:SetTextColor(0.7, 0.7, 0.7)

	-- ── Spec dropdown + Reset button ──────────────────────────────────
	local specLabel = section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	specLabel:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -CHROME_DROPDOWN_Y)
	specLabel:SetText("Spec:")

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

	local resetBtn = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
	resetBtn:SetSize(140, 22)
	resetBtn:SetPoint("LEFT", specDropdown, "RIGHT", 8, 2)
	resetBtn:SetText("Reset This Spec")

	-- ── Spell list container ───────────────────────────────────────────
	-- Both anchors at the same Y so the top edge is unambiguous; width
	-- = section width.
	local listFrame = CreateFrame("Frame", nil, section)
	listFrame:SetPoint("TOPLEFT",  section, "TOPLEFT",  0, -CHROME_LIST_Y)
	listFrame:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -CHROME_LIST_Y)
	listFrame:SetHeight(1) -- grown in RebuildList

	local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
	listBg:SetAllPoints()
	listBg:SetColorTexture(0, 0, 0, 0.3)

	local rowPool = {}

	RebuildList = function()
		for _, r in ipairs(rowPool) do r:Hide() end
		if not currentSpecId then
			listFrame:SetHeight(1)
			content:SetSize(content:GetWidth(), CHROME_LIST_Y + 1 + LIST_INSET)
			return
		end

		-- Union of the spec's defaults + anything the user previously
		-- added (preserves manual additions after the old add-by-ID flow).
		-- Default-set spells appear regardless of whether they're tracked
		-- so the checkbox can opt them in/out.
		local defaults = ns.DEFAULT_SPELLS_BY_SPEC[currentSpecId] or {}
		local tracked  = ns.GetTrackedForSpec(currentSpecId) or {}
		local seen, ids = {}, {}
		for id in pairs(defaults) do
			if not seen[id] then seen[id] = true; ids[#ids+1] = id end
		end
		for id in pairs(tracked) do
			if not seen[id] then seen[id] = true; ids[#ids+1] = id end
		end
		table.sort(ids)

		for i, id in ipairs(ids) do
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
			row.cb:SetChecked(tracked[id] and true or false)

			-- Close over (specId, id) so the handler keeps targeting the
			-- right pair even after re-renders reuse this pooled row.
			local specForCallback, idForCallback = currentSpecId, id
			row.cb:SetScript("OnClick", function(self)
				if self:GetChecked() then
					ns.AddTracked(specForCallback, idForCallback)
				else
					ns.RemoveTracked(specForCallback, idForCallback)
				end
			end)
		end

		local listHeight = math.max(4, #ids * (ROW_HEIGHT + ROW_GAP) + 4)
		listFrame:SetHeight(listHeight)
		content:SetSize(content:GetWidth(), CHROME_LIST_Y + listHeight + LIST_INSET)
	end

	-- ── Handlers ───────────────────────────────────────────────────────
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
