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
			{ type = "description", text = "Broadcasts your tracked spell cooldowns to addon-using party members. Icon size, position, and grow direction live in Blizzard's |cffffd100Edit Mode|r — press Esc -> Edit Mode and click the DzakSharedCDs anchor." },
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

local function MakeSpellRow(parent, rowWidth)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(rowWidth - 24, ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.remove:SetSize(28, 22)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetText("X")

	row.cdInput = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.cdInput:SetSize(40, 18)
	row.cdInput:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
	row.cdInput:SetAutoFocus(false)
	row.cdInput:SetNumeric(true)
	row.cdInput:SetMaxLetters(4)
	row.cdInput:SetTextInsets(4, 4, 0, 0)
	row.cdInput:SetFontObject("GameFontHighlight")
	row.cdInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	row.cdInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	row.cdInput:SetScript("OnEnter", function(self)
		if not self.spellId then return end
		local override = ns.GetCooldownOverride(self.spellId)
		local apiMs = C_Spell.GetSpellBaseCooldown and C_Spell.GetSpellBaseCooldown(self.spellId)
		local apiSecs = apiMs and apiMs >= 1000 and (apiMs / 1000) or nil
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Cooldown override (sec)", 1, 1, 1, 1)
		GameTooltip:AddLine("Blank = use API value.", 0.7, 0.7, 0.7, true)
		if apiSecs then
			GameTooltip:AddLine(string.format("|cffaaaaaaAPI reports:|r %.0fs", apiSecs))
		else
			GameTooltip:AddLine("|cffaaaaaaAPI reports:|r (none)")
		end
		if override then
			GameTooltip:AddLine(string.format("|cff66ff66Active override:|r %ds", override))
		end
		GameTooltip:Show()
	end)
	row.cdInput:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row.cdInput, "LEFT", -6, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	return row
end

local function BuildSpellsSection(content)
	-- Clean slate inside the content area. The renderer's ReleaseChildren
	-- only clears schema-managed frames; ours are orphaned plain Frames
	-- so we wipe them by name-prefixed lookup.
	for _, child in ipairs({ content:GetChildren() }) do
		if child._dscdSpellsSection then
			child:Hide()
			child:SetParent(nil)
		end
	end

	local section = CreateFrame("Frame", nil, content)
	section._dscdSpellsSection = true
	section:SetPoint("TOPLEFT", content, "TOPLEFT", LIST_INSET, -LIST_INSET)
	section:SetPoint("TOPRIGHT", content, "TOPRIGHT", -LIST_INSET, -LIST_INSET)
	section:SetHeight(1) -- grows as content expands

	-- Section header.
	local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
	header:SetText("Tracked spells")

	-- Spec dropdown (flat list).
	local specLabel = section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	specLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
	specLabel:SetText("Spec:")

	local specDropdown = CreateFrame("Frame", "DzakSharedCDsSpecDropdown", section, "UIDropDownMenuTemplate")
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
			info.text = opt.label
			info.value = opt.value
			info.checked = (opt.value == currentSpecId)
			info.func = function() OnSpecSelected(opt.value) end
			UIDropDownMenu_AddButton(info)
		end
	end)
	UIDropDownMenu_SetWidth(specDropdown, 220)

	-- Add input + buttons row.
	local idInput = CreateFrame("EditBox", nil, section, "InputBoxTemplate")
	idInput:SetSize(120, 22)
	idInput:SetPoint("TOPLEFT", specDropdown, "BOTTOMLEFT", 16, -10)
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

	-- Scroll for the row list.
	local scroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", idInput, "BOTTOMLEFT", -8, -10)
	scroll:SetPoint("TOPRIGHT", section, "TOPRIGHT", -28, 0) -- room for scrollbar
	scroll:SetHeight(360)

	local listBg = scroll:CreateTexture(nil, "BACKGROUND")
	listBg:SetAllPoints()
	listBg:SetColorTexture(0, 0, 0, 0.3)

	local listChild = CreateFrame("Frame", nil, scroll)
	listChild:SetSize(scroll:GetWidth() - 20, 1)
	scroll:SetScrollChild(listChild)

	local rowPool = {}

	RebuildList = function()
		for _, r in ipairs(rowPool) do r:Hide() end
		if not currentSpecId then
			listChild:SetHeight(1)
			return
		end

		local tracked = ns.GetTrackedForSpec(currentSpecId) or {}
		local sorted = {}
		for id in pairs(tracked) do sorted[#sorted + 1] = id end
		table.sort(sorted)

		for i, id in ipairs(sorted) do
			local row = rowPool[i]
			if not row then
				row = MakeSpellRow(listChild, listChild:GetWidth())
				rowPool[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_GAP))
			row:Show()

			local text, iconID = FormatLine(id)
			row.icon:SetTexture(iconID)
			row.label:SetText(text)
			local specForCallback = currentSpecId
			row.remove:SetScript("OnClick", function()
				ns.RemoveTracked(specForCallback, id)
				RebuildList()
			end)

			row.cdInput.spellId = id
			local override = ns.GetCooldownOverride(id)
			row.cdInput:SetText(override and tostring(override) or "")
			row.cdInput:SetScript("OnEditFocusLost", function(self)
				local n = tonumber(self:GetText() or "")
				ns.SetCooldownOverride(id, n)
				local saved = ns.GetCooldownOverride(id)
				self:SetText(saved and tostring(saved) or "")
			end)
		end

		listChild:SetHeight(math.max(1, #sorted * (ROW_HEIGHT + ROW_GAP)))
	end

	-- Add/Reset handlers.
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

	-- Initial selection: local player's spec if known, else first.
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
		Renderer:Clear(layoutContainer)
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
