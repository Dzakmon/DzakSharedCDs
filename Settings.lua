-- Blizzard Settings canvas:
--   - Master Enabled checkbox.
--   - Spec dropdown (grouped by class). All edits below act on the
--     currently-selected spec.
--   - Scrollable spell list for that spec: add by ID, remove via X,
--     Reset Defaults restores ns.DEFAULT_SPELLS_BY_SPEC[currentSpecId].

local addonName, ns = ...

local UNKNOWN_ICON = 134400
local ROW_HEIGHT = 26
local ROW_GAP = 2
local LIST_WIDTH = 540
local LIST_HEIGHT = 320

-- ============================================================
-- ROOT FRAME
-- ============================================================

local optionsFrame = CreateFrame("Frame", "DzakSharedCDsOptionsFrame", UIParent)
optionsFrame:Hide()

local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("DzakSharedCDs")

local subtitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetText("Broadcasts your tracked spell cooldowns to party members who run this addon, and renders theirs on their party frames.")
subtitle:SetTextColor(0.7, 0.7, 0.7)

local enableCB = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
enableCB:SetSize(24, 24)
enableCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
enableCB.text = enableCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
enableCB.text:SetPoint("LEFT", enableCB, "RIGHT", 4, 0)
enableCB.text:SetText("Enabled")
enableCB:SetScript("OnClick", function(self) ns.SetEnabled(self:GetChecked()) end)

-- ============================================================
-- SPEC SELECTOR
-- ============================================================

local currentSpecId = nil

local specLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
specLabel:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -20)
specLabel:SetText("Spec")

local specDesc = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
specDesc:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -4)
specDesc:SetText("Choose which spec's tracked-spell list to edit. The list below applies to that spec only.")
specDesc:SetTextColor(0.7, 0.7, 0.7)

local specDropdown = CreateFrame("Frame", "DzakSharedCDsSpecDropdown", optionsFrame, "UIDropDownMenuTemplate")
specDropdown:SetPoint("TOPLEFT", specDesc, "BOTTOMLEFT", -16, -4)

local RebuildList -- forward decl

local function OnSpecSelected(_, specId)
	currentSpecId = specId
	ns.EnsureSpecSeeded(specId)
	UIDropDownMenu_SetSelectedValue(specDropdown, specId)
	UIDropDownMenu_SetText(specDropdown, ns.FormatSpecLabel(specId))
	if RebuildList then RebuildList() end
end

local function InitSpecDropdown(self, level)
	level = level or 1

	if level == 1 then
		-- Group entries by class. Use UIDROPDOWNMENU_MENU_VALUE on level
		-- 2 to know which class submenu we're opening.
		local seen = {}
		for _, info in ipairs(ns.ALL_SPECS) do
			if not seen[info.classToken] then
				seen[info.classToken] = true
				local entry = UIDropDownMenu_CreateInfo()
				entry.text = info.className
				entry.value = info.classToken
				entry.hasArrow = true
				entry.notCheckable = true
				UIDropDownMenu_AddButton(entry, level)
			end
		end
	elseif level == 2 then
		local classToken = UIDROPDOWNMENU_MENU_VALUE
		for _, info in ipairs(ns.ALL_SPECS) do
			if info.classToken == classToken then
				local entry = UIDropDownMenu_CreateInfo()
				entry.text = info.specName
				entry.value = info.specId
				entry.arg1 = nil
				entry.arg2 = info.specId
				entry.func = function(btn, _, specId) OnSpecSelected(btn, specId or info.specId) end
				entry.checked = (currentSpecId == info.specId)
				UIDropDownMenu_AddButton(entry, level)
			end
		end
	end
end

UIDropDownMenu_Initialize(specDropdown, InitSpecDropdown)
UIDropDownMenu_SetWidth(specDropdown, 220)

-- ============================================================
-- ADD / RESET CONTROLS
-- ============================================================

local idInput = CreateFrame("EditBox", nil, optionsFrame, "InputBoxTemplate")
idInput:SetSize(120, 22)
idInput:SetPoint("TOPLEFT", specDropdown, "BOTTOMLEFT", 20, -16)
idInput:SetAutoFocus(false)
idInput:SetNumeric(true)
idInput:SetMaxLetters(8)
idInput:SetTextInsets(4, 4, 0, 0)

local idLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
idLabel:SetPoint("BOTTOMLEFT", idInput, "TOPLEFT", -4, 2)
idLabel:SetText("Spell ID")

local addBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
addBtn:SetSize(70, 22)
addBtn:SetPoint("LEFT", idInput, "RIGHT", 8, 0)
addBtn:SetText("Add")

local resetBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 22)
resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
resetBtn:SetText("Reset This Spec")

-- ============================================================
-- LIST
-- ============================================================

local scroll = CreateFrame("ScrollFrame", nil, optionsFrame, "UIPanelScrollFrameTemplate")
scroll:SetSize(LIST_WIDTH, LIST_HEIGHT)
scroll:SetPoint("TOPLEFT", idInput, "BOTTOMLEFT", -8, -10)

local scrollBg = scroll:CreateTexture(nil, "BACKGROUND")
scrollBg:SetAllPoints()
scrollBg:SetColorTexture(0, 0, 0, 0.3)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(LIST_WIDTH - 20, 1)
scroll:SetScrollChild(content)

local function FormatLine(id)
	local info = C_Spell.GetSpellInfo(id)
	local name = info and info.name or "(unknown)"
	return string.format("|cffffff00%d|r  %s", id, name), info and info.iconID or UNKNOWN_ICON
end

local function MakeRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(LIST_WIDTH - 24, ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", -36, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.remove:SetSize(28, 22)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetText("X")

	return row
end

local rowPool = {}

RebuildList = function()
	for _, row in ipairs(rowPool) do row:Hide() end
	if not currentSpecId then
		content:SetHeight(1)
		return
	end

	local tracked = ns.GetTrackedForSpec(currentSpecId) or {}
	local sorted = {}
	for id in pairs(tracked) do table.insert(sorted, id) end
	table.sort(sorted)

	for i, id in ipairs(sorted) do
		local row = rowPool[i]
		if not row then
			row = MakeRow(content)
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
	end

	content:SetHeight(math.max(1, #sorted * (ROW_HEIGHT + ROW_GAP)))
end

-- ============================================================
-- HANDLERS
-- ============================================================

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

optionsFrame:SetScript("OnShow", function()
	enableCB:SetChecked(ns.IsEnabled())
	-- Default to the player's current spec; fall back to first in list
	-- if not detected yet (rare — would mean SpecCache not booted).
	if not currentSpecId then
		currentSpecId = ns.SpecCache:GetLocalSpec() or ns.ALL_SPECS[1].specId
	end
	ns.EnsureSpecSeeded(currentSpecId)
	UIDropDownMenu_SetSelectedValue(specDropdown, currentSpecId)
	UIDropDownMenu_SetText(specDropdown, ns.FormatSpecLabel(currentSpecId))
	RebuildList()
end)

-- ============================================================
-- BLIZZARD SETTINGS REGISTRATION
-- ============================================================

local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "DzakSharedCDs")
Settings.RegisterAddOnCategory(category)

ns.OpenSettings = function()
	Settings.OpenToCategory(category:GetID())
end
