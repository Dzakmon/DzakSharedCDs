-- Fallback anchor: used when a tracked unit has no resolved Blizzard
-- party / raid frame. Registered with FerrozEditModeLib so it appears
-- in Blizzard's native Edit Mode (alongside the UnitFrames section)
-- with built-in drag / scale / opacity controls, plus a custom plugin
-- panel exposing the icon-row display settings (size, spacing, grow
-- direction, X/Y offset).

local addonName, ns = ...

local Anchor = {}
ns.Anchor = Anchor

-- ============================================================
-- THE FRAME
-- A plain Frame with a backdrop so the user can actually see it
-- when entering Edit Mode (Ferroz only enables drag — it doesn't
-- give the frame a visible representation). Outside Edit Mode the
-- backdrop stays faint so it doesn't clutter the screen; the
-- EditMode.Enter callback below brightens it.
-- ============================================================

local anchor = CreateFrame("FRAME", "DzakSharedCDsAnchor", UIParent, "BackdropTemplate")
anchor:SetClampedToScreen(true)
anchor:SetSize(200, 28)
anchor:SetBackdrop({
	bgFile   = "Interface/Buttons/WHITE8X8",
	edgeFile = "Interface/Buttons/WHITE8X8",
	edgeSize = 1,
	insets   = { left = 1, right = 1, top = 1, bottom = 1 },
})
-- Idle colours: faint, low-contrast — barely visible during gameplay.
anchor:SetBackdropColor(0, 0, 0, 0.15)
anchor:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.4)

-- Identification text. Hidden outside Edit Mode so it doesn't sit on
-- top of fallback-rendered icon rows (Display.lua attaches rows INSIDE
-- the anchor's bounds when no party frame is resolved, which would
-- otherwise overlap a CENTER-anchored label). Surfaces only when the
-- user enters Edit Mode and needs to find the frame.
local anchorLabel = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
anchorLabel:SetPoint("CENTER")
anchorLabel:SetText("DzakSharedCDs")
anchorLabel:SetAlpha(0)

ns.anchorFrame = anchor

-- Brighten the anchor while Edit Mode is active so the user can find
-- and drag it; restore the faint idle look on exit.
local function SetEditModeAppearance(active)
	if active then
		anchor:SetBackdropColor(0.25, 0.45, 1, 0.35)
		anchor:SetBackdropBorderColor(0.6, 0.8, 1, 1)
		anchorLabel:SetAlpha(1)
	else
		anchor:SetBackdropColor(0, 0, 0, 0.15)
		anchor:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.4)
		anchorLabel:SetAlpha(0)
	end
end

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("EditMode.Enter", function() SetEditModeAppearance(true)  end)
	EventRegistry:RegisterCallback("EditMode.Exit",  function() SetEditModeAppearance(false) end)
end

-- ============================================================
-- DB MIGRATION (v0.6.x -> v0.7.0)
-- Old shape: DzakSharedCDsDB.anchor = { point, x, y, enabled }
-- New shape: DzakSharedCDsDB.anchor = { layouts = { <name> = {...} } }
-- (FerrozEditModeLib stores per-Edit-Mode-layout state in `layouts`.)
-- ============================================================

local function MigrateAnchorDb()
	DzakSharedCDsDB = DzakSharedCDsDB or {}
	DzakSharedCDsDB.anchor = DzakSharedCDsDB.anchor or {}
	local db = DzakSharedCDsDB.anchor

	-- Detect the legacy flat shape and port it to a Modern-layout entry.
	-- After the port, the legacy keys are cleared so a future migration
	-- bug can't silently re-prefer them.
	if db.point or db.x or db.y then
		db.layouts = db.layouts or {}
		db.layouts.Modern = db.layouts.Modern or {
			point = db.point or "CENTER",
			relativeFrame = UIParent,
			relativePoint = db.point or "CENTER",
			xOfs = db.x or 0,
			yOfs = db.y or 0,
			scale = 1.0,
			opacity = 1.0,
			height = 28,
			width = 200,
		}
		db.point, db.x, db.y = nil, nil, nil
	end

	db.layouts = db.layouts or {}
end

-- ============================================================
-- PLUGIN PANEL — the custom display controls Ferroz attaches into
-- its config popup when the user clicks our anchor in Edit Mode.
--
-- Ferroz calls anchor:GetOrCreateFrameSpecificControls(socket) and
-- we return (controlsList, pluginFrame). The pluginFrame becomes a
-- child of the socket; we own its layout.
-- ============================================================

local PLUGIN_ROW_H = 28
local PLUGIN_ROWS = 6 -- 5 controls + reset button

local function BuildPluginPanel(parent)
	local panel = CreateFrame("Frame", "DzakSharedCDsAnchorPlugin", parent)
	panel:SetHeight(PLUGIN_ROW_H * PLUGIN_ROWS + 12)

	local controls = {}

	-- Slider builder shared with all 4 sliders below.
	local function makeSlider(yIndex, label, key, minV, maxV, step)
		local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
		slider:SetWidth(160)
		slider:SetHeight(16)
		slider:SetMinMaxValues(minV, maxV)
		slider:SetValueStep(step)
		slider:SetObeyStepOnDrag(true)
		slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(yIndex * PLUGIN_ROW_H + 4))

		-- Identify Low/High/Text font strings on the anonymous slider
		-- (same pattern as Settings.lua's slider helper). The @cast
		-- narrows the region's type post-check so the GetText/SetText
		-- calls below don't trip the linter's Region type stub.
		for _, region in ipairs({ slider:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				---@cast region FontString
				local t = region:GetText()
				if t == "Low" then slider.Low = region
				elseif t == "High" then slider.High = region
				else slider.Text = region end
			end
		end
		if slider.Low then slider.Low:SetText(tostring(minV)) end
		if slider.High then slider.High:SetText(tostring(maxV)) end

		local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		heading:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 2)

		local function refresh()
			local v = ns.GetDisplaySetting(key)
			heading:SetText(string.format("%s: |cffffd100%d|r", label, v))
			slider:SetValue(v)
		end
		refresh()

		slider:SetScript("OnValueChanged", function(_, value)
			local snapped = math.floor((value / step) + 0.5) * step
			if snapped ~= ns.GetDisplaySetting(key) then
				ns.SetDisplaySetting(key, snapped)
			end
			heading:SetText(string.format("%s: |cffffd100%d|r", label, snapped))
		end)

		slider.Refresh = refresh
		table.insert(controls, slider)
		return slider
	end

	makeSlider(0, "Icon size",    "iconSize", 12, 64, 1)
	makeSlider(1, "Icon spacing", "iconGap",   0, 16, 1)

	-- Grow direction dropdown (Right / Left).
	local growLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	growLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(2 * PLUGIN_ROW_H + 4))

	local growDropdown = CreateFrame("Frame", "DzakSharedCDsAnchorGrowDD", panel, "UIDropDownMenuTemplate")
	growDropdown:SetPoint("TOPLEFT", growLabel, "BOTTOMLEFT", -16, -4)

	local function refreshGrow()
		local v = ns.GetDisplaySetting("growDirection")
		growLabel:SetText(string.format("Grow direction: |cffffd100%s|r", v == "LEFT" and "Left" or "Right"))
		UIDropDownMenu_SetSelectedValue(growDropdown, v)
		UIDropDownMenu_SetText(growDropdown, v == "LEFT" and "Left" or "Right")
	end

	UIDropDownMenu_Initialize(growDropdown, function(_, level)
		for _, opt in ipairs({ { v = "RIGHT", l = "Right" }, { v = "LEFT", l = "Left" } }) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = opt.l
			info.value = opt.v
			info.checked = (ns.GetDisplaySetting("growDirection") == opt.v)
			info.func = function()
				ns.SetDisplaySetting("growDirection", opt.v)
				refreshGrow()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	UIDropDownMenu_SetWidth(growDropdown, 140)
	refreshGrow()
	growDropdown.Refresh = refreshGrow
	table.insert(controls, growDropdown)

	makeSlider(3, "Offset X", "offsetX", -100, 100, 1)
	makeSlider(4, "Offset Y", "offsetY", -100, 100, 1)

	local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetBtn:SetSize(160, 22)
	resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -(5 * PLUGIN_ROW_H + 4))
	resetBtn:SetText("Reset display defaults")
	resetBtn:SetScript("OnClick", function()
		ns.ResetDisplayDefaults()
		for _, c in ipairs(controls) do
			if c.Refresh then c:Refresh() end
		end
	end)

	return controls, panel
end

-- Ferroz checks for this method on the frame and calls it when the
-- user opens Edit Mode and selects our anchor. Return a list of
-- controls (for snapshot/commit hooks Ferroz may iterate) and the
-- single plugin frame that hosts them.
function anchor:GetOrCreateFrameSpecificControls(socket)
	if self._pluginControls then
		return self._pluginControls, self._pluginFrame
	end
	local controls, panel = BuildPluginPanel(socket)
	self._pluginControls = controls
	self._pluginFrame = panel
	return controls, panel
end

-- ============================================================
-- REGISTER WITH FERROZ
-- Done on the next frame so DzakSharedCDsDB is guaranteed loaded
-- (matches the original deferred-registration pattern).
-- ============================================================

C_Timer.After(0, function()
	MigrateAnchorDb()
	local lib = LibStub("FerrozEditModeLib-1.0", true)
	if not lib then
		if ns.Debug then ns.Debug:print("anchor", "FerrozEditModeLib missing — anchor will not be Edit-Mode-movable") end
		anchor:SetPoint("CENTER")
		anchor:Show()
		return
	end

	lib:Register(anchor, DzakSharedCDsDB.anchor, { height = 28, width = 200 })

	-- Ferroz's Register doesn't call :Show() — it only applies layout
	-- state. Without an explicit Show, the anchor stays hidden outside
	-- Edit Mode, which strands fallback-attached icon rows (Display.lua's
	-- AnchorRowToUnit branch that runs when no party frame is resolved).
	anchor:Show()

	if ns.Debug then ns.Debug:print("anchor", "registered with FerrozEditModeLib") end
end)
