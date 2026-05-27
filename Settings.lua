-- Blizzard Settings canvas — single scrollable column:
--   - Master Enabled checkbox.
--   - Spec dropdown (grouped by class). All edits below act on the
--     currently-selected spec.
--   - Spell list for that spec: add by ID, remove via X, edit CD override,
--     Reset This Spec restores ns.DEFAULT_SPELLS_BY_SPEC[currentSpecId].
--   - Slash command reference.
--
-- Icon display options (size, spacing, grow direction, offsets) live in
-- Edit Mode now — select the DzakSharedCDs anchor frame in Edit Mode to
-- adjust them. See Anchor.lua's lem:AddFrameSettings call.
--
-- All content is parented to a master ScrollFrame so the panel scrolls
-- vertically when a spec's spell list is long or the viewport is small.

local addonName, ns = ...

local UNKNOWN_ICON = 134400
local ROW_HEIGHT = 26
local ROW_GAP = 2
local CONTENT_WIDTH = 540

-- ============================================================
-- ROOT FRAME + MASTER SCROLL
-- ============================================================

local optionsFrame = CreateFrame("Frame", "DzakSharedCDsOptionsFrame", UIParent)
optionsFrame:Hide()

local masterScroll = CreateFrame("ScrollFrame", nil, optionsFrame, "UIPanelScrollFrameTemplate")
masterScroll:SetPoint("TOPLEFT", 16, -16)
masterScroll:SetPoint("BOTTOMRIGHT", -32, 16) -- right inset leaves room for the scrollbar

local content = CreateFrame("Frame", nil, masterScroll)
content:SetSize(CONTENT_WIDTH, 1) -- height grown dynamically at the end of layout
masterScroll:SetScrollChild(content)

-- ============================================================
-- HEADER
-- ============================================================

local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 0, 0)
title:SetText("DzakSharedCDs")

local subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetWidth(CONTENT_WIDTH)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Broadcasts your tracked spell cooldowns to party members who run this addon, and renders theirs on their party frames. Icon size / position / grow direction live in |cffffd100Edit Mode|r — select the DzakSharedCDs anchor frame.")
subtitle:SetTextColor(0.7, 0.7, 0.7)

local enableCB = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
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

local specLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
specLabel:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -20)
specLabel:SetText("Spec")

local specDesc = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
specDesc:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -4)
specDesc:SetText("Choose which spec's tracked-spell list to edit.")
specDesc:SetTextColor(0.7, 0.7, 0.7)

local specDropdown = CreateFrame("Frame", "DzakSharedCDsSpecDropdown", content, "UIDropDownMenuTemplate")
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

local idInput = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
idInput:SetSize(120, 22)
idInput:SetPoint("TOPLEFT", specDropdown, "BOTTOMLEFT", 20, -16)
idInput:SetAutoFocus(false)
idInput:SetNumeric(true)
idInput:SetMaxLetters(8)
idInput:SetTextInsets(4, 4, 0, 0)

local idLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
idLabel:SetPoint("BOTTOMLEFT", idInput, "TOPLEFT", -4, 2)
idLabel:SetText("Spell ID")

local addBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
addBtn:SetSize(70, 22)
addBtn:SetPoint("LEFT", idInput, "RIGHT", 8, 0)
addBtn:SetText("Add")

local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 22)
resetBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
resetBtn:SetText("Reset This Spec")

-- ============================================================
-- SPELL LIST
-- The list itself isn't a separate ScrollFrame anymore — rows are
-- laid out directly inside `content` and the master scroll handles
-- overflow when a spec has many spells. listAnchor is an invisible
-- frame that gives us a stable TOP edge to position rows beneath
-- while letting us compute the list's total height later.
-- ============================================================

local listAnchor = CreateFrame("Frame", nil, content)
listAnchor:SetSize(CONTENT_WIDTH, 1)
listAnchor:SetPoint("TOPLEFT", idInput, "BOTTOMLEFT", -8, -16)

local function FormatLine(id)
	local info = C_Spell.GetSpellInfo(id)
	local name = info and info.name or "(unknown)"
	return string.format("|cffffff00%d|r  %s", id, name), info and info.iconID or UNKNOWN_ICON
end

local function MakeRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(CONTENT_WIDTH, ROW_HEIGHT)

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

-- ============================================================
-- SLASH COMMANDS HELP
-- Anchored below the spell list. Position relative to listAnchor
-- + the dynamic row count so this section flows down as the list
-- grows / shrinks per spec.
-- ============================================================

local cmdHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
cmdHeader:SetText("Slash commands")

local cmdBody = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
cmdBody:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
cmdBody:SetJustifyH("LEFT")
cmdBody:SetWidth(CONTENT_WIDTH)

local SLASH_HELP = {
	{ "/dscd",            "open this settings panel" },
	{ "/dscd status",     "print state summary (enabled, local spec, group, instance)" },
	{ "/dscd init",       "print the spell list your next INIT broadcast would advertise" },
	{ "/dscd broadcast",  "force an INIT broadcast now (bypasses debounce)" },
	{ "/dscd ping",       "transport delivery test — recipients print a visible chat line" },
	{ "/dscddebug",       "toggle debug tracing on/off (logs every wire send + receive)" },
}
do
	local lines = {}
	for i, entry in ipairs(SLASH_HELP) do
		lines[i] = string.format("|cff66ddff%-18s|r  |cff999999—|r  %s", entry[1], entry[2])
	end
	cmdBody:SetText(table.concat(lines, "\n"))
end

-- ============================================================
-- LIST RENDER
-- ============================================================

RebuildList = function()
	for _, row in ipairs(rowPool) do row:Hide() end
	local rowCount = 0

	if currentSpecId then
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
			row:SetPoint("TOPLEFT", listAnchor, "TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + ROW_GAP))
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
				ns.SetCooldownOverride(id, n)
				local saved = ns.GetCooldownOverride(id)
				self:SetText(saved and tostring(saved) or "")
			end)
		end
		rowCount = #sorted
	end

	-- Reflow elements below the list and recompute total content height
	-- so the master scrollbar knows how far it can scroll.
	local listHeight = rowCount * (ROW_HEIGHT + ROW_GAP)
	cmdHeader:ClearAllPoints()
	cmdHeader:SetPoint("TOPLEFT", listAnchor, "TOPLEFT", 8, -(listHeight + 20))

	-- Direct height calculation — sum of (above-list) + (list) + (below).
	-- We can't use GetTop / GetBottom: content starts at height 1 and the
	-- ScrollFrame clips children to the scroll child's bounds, so the
	-- defer-by-one-frame approach left rows invisible. FontString heights
	-- (variable due to wrapping) are queried directly; fixed-size widgets
	-- use the same constants their SetSize uses above.
	local aboveList =
		24                                            -- title
		+ 4 + (subtitle:GetStringHeight() or 36)      -- subtitle (wraps)
		+ 10 + 24                                     -- enable checkbox
		+ 20 + 24                                     -- spec label
		+ 4 + 18                                      -- spec desc
		+ 4 + 30                                      -- spec dropdown
		+ 16 + 22                                     -- id input row
		+ 16                                          -- gap to list
	local belowList =
		20                                            -- gap above cmdHeader
		+ (cmdHeader:GetStringHeight() or 22)
		+ 6
		+ (cmdBody:GetStringHeight() or 100)
		+ 16                                          -- bottom padding
	content:SetHeight(aboveList + listHeight + belowList)
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
	if not currentSpecId then
		currentSpecId = ns.SpecCache:GetLocalSpec() or ns.ALL_SPECS[1].specId
	end
	ns.EnsureSpecSeeded(currentSpecId)
	UIDropDownMenu_SetSelectedValue(specDropdown, currentSpecId)
	UIDropDownMenu_SetText(specDropdown, ns.FormatSpecLabel(currentSpecId))
	RebuildList()
	-- Reset scroll to top on every open so users don't land mid-list
	-- after a previous session.
	masterScroll:SetVerticalScroll(0)
end)

-- ============================================================
-- BLIZZARD SETTINGS REGISTRATION
-- ============================================================

local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "DzakSharedCDs")
Settings.RegisterAddOnCategory(category)

ns.OpenSettings = function()
	Settings.OpenToCategory(category:GetID())
end
