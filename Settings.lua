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

-- ============================================================
-- DISPLAY SECTION (right column, next to the spell list)
-- All controls call ns.SetDisplaySetting which persists + triggers
-- ns.Display:UpdateAll, so every drag of a slider re-lays-out rows.
-- ============================================================

local DISPLAY_COL_WIDTH = 220

local dispTitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dispTitle:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 24, 0)
dispTitle:SetText("Display")

local dispDesc = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dispDesc:SetPoint("TOPLEFT", dispTitle, "BOTTOMLEFT", 0, -4)
dispDesc:SetWidth(DISPLAY_COL_WIDTH)
dispDesc:SetJustifyH("LEFT")
dispDesc:SetText("Live preview — changes apply immediately to every party / raid row.")
dispDesc:SetTextColor(0.7, 0.7, 0.7)

-- Slider factory. Anchors below `previousAnchor` (a frame or fontstring
-- with a TOPLEFT). Returns the slider so subsequent ones can stack.
local function MakeSlider(label, min, max, step, key, formatFn, previousAnchor, topOffset)
	local slider = CreateFrame("Slider", nil, optionsFrame, "OptionsSliderTemplate")
	slider:SetWidth(DISPLAY_COL_WIDTH - 20)
	slider:SetHeight(16)
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:SetPoint("TOPLEFT", previousAnchor, "BOTTOMLEFT", 0, topOffset or -28)

	-- OptionsSliderTemplate auto-creates $parentLow / $parentHigh /
	-- $parentText FontStrings, but only with a name. Our slider is
	-- anonymous, so walk regions and identify by the template's default
	-- text content ("Low" / "High" / "Slider"). Safe because this runs
	-- before any of our SetText calls.
	for _, region in ipairs({ slider:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			local t = region:GetText()
			if t == "Low" then slider.Low = region
			elseif t == "High" then slider.High = region
			else slider.Text = region end
		end
	end

	if slider.Low then slider.Low:SetText(tostring(min)) end
	if slider.High then slider.High:SetText(tostring(max)) end

	local valueLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	valueLabel:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 2)

	local function RefreshLabel()
		local v = ns.GetDisplaySetting(key)
		valueLabel:SetText(string.format("%s: |cffffd100%s|r", label, formatFn and formatFn(v) or tostring(v)))
	end
	RefreshLabel()

	slider:SetValue(ns.GetDisplaySetting(key))
	slider:SetScript("OnValueChanged", function(self, value, isUserInput)
		-- Snap to step (OnValueChanged can fire with sub-step values
		-- during drag). Round to nearest step boundary.
		local snapped = math.floor((value / step) + 0.5) * step
		if snapped ~= ns.GetDisplaySetting(key) then
			ns.SetDisplaySetting(key, snapped)
		end
		RefreshLabel()
	end)

	slider.Refresh = RefreshLabel
	return slider
end

local iconSizeSlider = MakeSlider("Icon size", 12, 64, 1, "iconSize",
	function(v) return v .. " px" end, dispDesc, -36)

local iconGapSlider = MakeSlider("Icon spacing", 0, 16, 1, "iconGap",
	function(v) return v .. " px" end, iconSizeSlider, -28)

-- Grow direction dropdown
local growLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
growLabel:SetPoint("TOPLEFT", iconGapSlider, "BOTTOMLEFT", 0, -22)
growLabel:SetText("Grow direction")

local growDropdown = CreateFrame("Frame", "DzakSharedCDsGrowDropdown", optionsFrame, "UIDropDownMenuTemplate")
growDropdown:SetPoint("TOPLEFT", growLabel, "BOTTOMLEFT", -16, -4)

local function RefreshGrowDropdown()
	local current = ns.GetDisplaySetting("growDirection")
	UIDropDownMenu_SetSelectedValue(growDropdown, current)
	UIDropDownMenu_SetText(growDropdown, current == "LEFT" and "Left" or "Right")
end

UIDropDownMenu_Initialize(growDropdown, function(_, level)
	for _, opt in ipairs({ { v = "RIGHT", label = "Right" }, { v = "LEFT", label = "Left" } }) do
		local entry = UIDropDownMenu_CreateInfo()
		entry.text = opt.label
		entry.value = opt.v
		entry.checked = (ns.GetDisplaySetting("growDirection") == opt.v)
		entry.func = function()
			ns.SetDisplaySetting("growDirection", opt.v)
			RefreshGrowDropdown()
		end
		UIDropDownMenu_AddButton(entry, level)
	end
end)
UIDropDownMenu_SetWidth(growDropdown, DISPLAY_COL_WIDTH - 36)

local offsetXSlider = MakeSlider("Offset X", -100, 100, 1, "offsetX",
	function(v) return v .. " px" end, growDropdown, -28)

local offsetYSlider = MakeSlider("Offset Y", -100, 100, 1, "offsetY",
	function(v) return v .. " px" end, offsetXSlider, -28)

local dispReset = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
dispReset:SetSize(DISPLAY_COL_WIDTH - 20, 22)
dispReset:SetPoint("TOPLEFT", offsetYSlider, "BOTTOMLEFT", 0, -16)
dispReset:SetText("Reset display defaults")
dispReset:SetScript("OnClick", function()
	ns.ResetDisplayDefaults()
	iconSizeSlider:SetValue(ns.GetDisplaySetting("iconSize"))
	iconGapSlider:SetValue(ns.GetDisplaySetting("iconGap"))
	offsetXSlider:SetValue(ns.GetDisplaySetting("offsetX"))
	offsetYSlider:SetValue(ns.GetDisplaySetting("offsetY"))
	iconSizeSlider:Refresh()
	iconGapSlider:Refresh()
	offsetXSlider:Refresh()
	offsetYSlider:Refresh()
	RefreshGrowDropdown()
end)

-- ============================================================
-- SLASH COMMANDS REFERENCE
-- Lives in the panel so users discover commands without having
-- to remember to type `/dscd ?`. Keep in sync with Main.lua's
-- SlashCmdList["DSCD"] body — and with Debug.lua for /dscddebug.
-- ============================================================

local SLASH_HELP = {
	{ "/dscd",            "open this settings panel" },
	{ "/dscd status",     "print state summary (enabled, local spec, group, instance)" },
	{ "/dscd init",       "print the spell list your next INIT broadcast would advertise" },
	{ "/dscd broadcast",  "force an INIT broadcast now (bypasses debounce)" },
	{ "/dscd ping",       "transport delivery test — recipients print a visible chat line" },
	{ "/dscddebug",       "toggle debug tracing on/off (logs every wire send + receive)" },
}

local cmdHeader = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
cmdHeader:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 8, -16)
cmdHeader:SetText("Slash commands")

local cmdBody = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
cmdBody:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
cmdBody:SetJustifyH("LEFT")
cmdBody:SetWidth(LIST_WIDTH)
do
	local lines = {}
	for i, entry in ipairs(SLASH_HELP) do
		-- Cyan command, light-grey hyphen, white description.
		lines[i] = string.format("|cff66ddff%-18s|r  |cff999999—|r  %s", entry[1], entry[2])
	end
	cmdBody:SetText(table.concat(lines, "\n"))
end

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

	row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.remove:SetSize(28, 22)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetText("X")

	-- Manual CD override: blank = use API lookup, number = force that
	-- many seconds. Tooltip on hover shows the API-reported value so
	-- the user can compare against what they're typing.
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
		GameTooltip:SetText("Cooldown override (sec)")
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

		-- Override field: show current value (or blank). Save on focus
		-- loss so users can tab/click away without an explicit submit.
		row.cdInput.spellId = id
		local override = ns.GetCooldownOverride(id)
		row.cdInput:SetText(override and tostring(override) or "")
		row.cdInput:SetScript("OnEditFocusLost", function(self)
			local raw = self:GetText() or ""
			local n = tonumber(raw)
			-- Empty input or 0 = clear the override (SetCooldownOverride
			-- treats <=0 as clear). Don't store back the API value when
			-- the user blanks the field — we want "use API" sticky.
			ns.SetCooldownOverride(id, n)
			-- Re-read to confirm what got persisted (covers the
			-- clear-on-0 case) and re-display normalized.
			local saved = ns.GetCooldownOverride(id)
			self:SetText(saved and tostring(saved) or "")
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

	-- Pull current display values back into the controls. Sliders are
	-- silent about external changes; we re-seed them on every open.
	iconSizeSlider:SetValue(ns.GetDisplaySetting("iconSize"))
	iconGapSlider:SetValue(ns.GetDisplaySetting("iconGap"))
	offsetXSlider:SetValue(ns.GetDisplaySetting("offsetX"))
	offsetYSlider:SetValue(ns.GetDisplaySetting("offsetY"))
	iconSizeSlider:Refresh()
	iconGapSlider:Refresh()
	offsetXSlider:Refresh()
	offsetYSlider:Refresh()
	RefreshGrowDropdown()
end)

-- ============================================================
-- BLIZZARD SETTINGS REGISTRATION
-- ============================================================

local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "DzakSharedCDs")
Settings.RegisterAddOnCategory(category)

ns.OpenSettings = function()
	Settings.OpenToCategory(category:GetID())
end
