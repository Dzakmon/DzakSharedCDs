-- Blizzard Settings canvas:
--   - Title / subtitle.
--   - Master Enabled checkbox.
--   - Slash command reference (above the spec picker so it stays
--     glanceable — the spell list below pushes everything that comes
--     after it off-screen for users with many tracked spells).
--   - Spec dropdown (grouped by class). All edits below act on the
--     currently-selected spec.
--   - Spell list for that spec with its own internal scroll: add by ID,
--     remove via X, edit CD override, Reset This Spec restores
--     ns.DEFAULT_SPELLS_BY_SPEC[currentSpecId].
--
-- Icon display options (size, spacing, grow direction, offsets) live in
-- Edit Mode — select the DzakSharedCDs anchor frame to adjust them.

local addonName, ns = ...

local UNKNOWN_ICON = 134400
local ROW_HEIGHT = 26
local ROW_GAP = 2
local LIST_WIDTH = 540

-- ============================================================
-- ROOT FRAME
-- ============================================================

local optionsFrame = CreateFrame("Frame", "DzakSharedCDsOptionsFrame", UIParent)
optionsFrame:Hide()
-- Explicit fallback size. Blizzard's canvas re-parents and re-anchors
-- this frame when the category is shown, so the in-game appearance
-- comes from the canvas, not these dimensions. But if the canvas
-- pipeline ever fails to size us (race conditions, future Blizzard
-- changes), this keeps the scroll-frame anchors below from collapsing
-- to a 0-height region — which was the "only one spell visible"
-- failure mode before this line existed.
optionsFrame:SetSize(720, 600)

local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("DzakSharedCDs")

local subtitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetWidth(LIST_WIDTH)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Broadcasts your tracked spell cooldowns to party members who run this addon, and renders theirs on their party frames. Icon size / position / grow direction live in |cffffd100Edit Mode|r — select the DzakSharedCDs anchor frame.")
subtitle:SetTextColor(0.7, 0.7, 0.7)

local enableCB = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
enableCB:SetSize(24, 24)
enableCB:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
enableCB.text = enableCB:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
enableCB.text:SetPoint("LEFT", enableCB, "RIGHT", 4, 0)
enableCB.text:SetText("Enabled")
enableCB:SetScript("OnClick", function(self) ns.SetEnabled(self:GetChecked()) end)

-- ============================================================
-- SLASH COMMANDS HELP — placed near the top so it stays visible.
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
cmdHeader:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -16)
cmdHeader:SetText("Slash commands")

-- Two-column layout. Six rows of help in one column ate ~85 px of
-- vertical room and pushed the spell list's scroll-frame down to ~1
-- row tall on smaller Settings canvases. Three rows × two columns
-- halves that without losing any info.
local cmdContainer = CreateFrame("Frame", nil, optionsFrame)
cmdContainer:SetPoint("TOPLEFT", cmdHeader, "BOTTOMLEFT", 0, -6)
cmdContainer:SetSize(LIST_WIDTH, 3 * 14 + 4)

local function MakeHelpColumn(parent, xOffset, entries)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWidth(LIST_WIDTH / 2 - 8)
	local lines = {}
	for i, e in ipairs(entries) do
		lines[i] = string.format("|cff66ddff%s|r  %s", e[1], e[2])
	end
	fs:SetText(table.concat(lines, "\n"))
	return fs
end

MakeHelpColumn(cmdContainer, 0,                  { SLASH_HELP[1], SLASH_HELP[2], SLASH_HELP[3] })
MakeHelpColumn(cmdContainer, LIST_WIDTH / 2 + 4, { SLASH_HELP[4], SLASH_HELP[5], SLASH_HELP[6] })

-- ============================================================
-- SPEC SELECTOR
-- ============================================================

local currentSpecId = nil

local specLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
specLabel:SetPoint("TOPLEFT", cmdContainer, "BOTTOMLEFT", 0, -18)
specLabel:SetText("Spec")

local specDesc = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
specDesc:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -4)
specDesc:SetText("Choose which spec's tracked-spell list to edit.")
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
		-- Blizzard's dropdown framework sets this global to the parent
		-- entry's `value` field right before firing the level-2 init.
		-- rawget bypasses the linter's field check — the global is
		-- real but isn't in the lua-language-server stubs for _G.
		local classToken = rawget(_G, "UIDROPDOWNMENU_MENU_VALUE")
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
-- SPELL LIST — its own ScrollFrame so the row count doesn't push
-- the rest of the panel around.
-- ============================================================

local scroll = CreateFrame("ScrollFrame", nil, optionsFrame, "UIPanelScrollFrameTemplate")
-- Two anchors instead of SetSize: top edge follows idInput, bottom edge
-- pins to the canvas so the scroll auto-fits whatever vertical space is
-- left. Avoids the previous bug where a fixed 320 px height pushed the
-- scroll (and its scrollbar) below the Blizzard settings canvas viewport.
scroll:SetPoint("TOPLEFT", idInput, "BOTTOMLEFT", -8, -10)
scroll:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -32, 16)

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
		-- Color args (1,1,1,1) match the default SetText() white-on-tooltip
		-- look; passed explicitly because the linter's type stub treats
		-- them as required even though the runtime defaults them.
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
			ns.SetCooldownOverride(id, n)
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
