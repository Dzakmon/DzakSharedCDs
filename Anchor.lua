-- Fallback anchor: used when a tracked unit has no resolved party frame
-- (e.g. solo testing, or a UI addon we don't yet support). When a party
-- frame IS found, the unit's icon row attaches to it directly and ignores
-- this anchor.

local addonName, ns = ...

local Anchor = {}
ns.Anchor = Anchor

local anchor = CreateFrame("FRAME", "DzakSharedCDsAnchor", UIParent)
anchor.editModeName = "DzakSharedCDs Anchor"
anchor:SetClampedToScreen(true)
anchor:SetSize(200, 28)
ns.anchorFrame = anchor


local function refresh()
	if anchor.db and anchor.db.enabled == false then
		anchor:Hide()
	else
		anchor:Show()
	end
end

Anchor.refresh = refresh


local function onPositionChanged(self, layoutName, point, x, y)
	self.db.point = point
	self.db.x = x
	self.db.y = y
end


local function updateLayout(self)
	self:ClearAllPoints()
	self:SetPoint(self.db.point, self.db.x, self.db.y)
end


C_Timer.After(0, function()
	DzakSharedCDsDB = DzakSharedCDsDB or {}
	DzakSharedCDsDB.anchor = DzakSharedCDsDB.anchor or {}
	anchor.db = DzakSharedCDsDB.anchor
	local db = anchor.db
	if db.enabled == nil then db.enabled = true end
	db.point = db.point or "CENTER"
	db.x = db.x or 0
	db.y = db.y or 0

	updateLayout(anchor)
	refresh()

	local lem = LibStub("LibEditMode")
	lem:AddFrame(anchor, onPositionChanged, {
		point = "CENTER",
		x = 0,
		y = 0,
	})

	-- Icon display controls live in Edit Mode rather than the Settings
	-- canvas: they're a visual / layout concern, edited in context with
	-- the moveable anchor, and out of the way of the spell-list panel.
	-- Both get / set route through ns.* so the SavedVariables shape is
	-- unchanged — this is purely a UI relocation.
	local iconPx = function(v) return v .. " px" end
	lem:AddFrameSettings(anchor, {
		{
			kind = lem.SettingType.Slider,
			name = "Icon size",
			desc = "Width and height of each cooldown icon.",
			minValue = 12, maxValue = 64, valueStep = 1,
			formatter = iconPx,
			default = ns.DEFAULT_DISPLAY.iconSize,
			get = function() return ns.GetDisplaySetting("iconSize") end,
			set = function(_, value) ns.SetDisplaySetting("iconSize", value) end,
		},
		{
			kind = lem.SettingType.Slider,
			name = "Icon spacing",
			desc = "Pixels between adjacent icons in the row.",
			minValue = 0, maxValue = 16, valueStep = 1,
			formatter = iconPx,
			default = ns.DEFAULT_DISPLAY.iconGap,
			get = function() return ns.GetDisplaySetting("iconGap") end,
			set = function(_, value) ns.SetDisplaySetting("iconGap", value) end,
		},
		{
			kind = lem.SettingType.Dropdown,
			name = "Grow direction",
			desc = "Which side of the party frame the icon row extends to.",
			default = ns.DEFAULT_DISPLAY.growDirection,
			values = {
				{ text = "Right", value = "RIGHT" },
				{ text = "Left",  value = "LEFT"  },
			},
			get = function() return ns.GetDisplaySetting("growDirection") end,
			set = function(_, value) ns.SetDisplaySetting("growDirection", value) end,
		},
		{
			kind = lem.SettingType.Slider,
			name = "Offset X",
			desc = "Horizontal offset from the party frame edge.",
			minValue = -100, maxValue = 100, valueStep = 1,
			formatter = iconPx,
			default = ns.DEFAULT_DISPLAY.offsetX,
			get = function() return ns.GetDisplaySetting("offsetX") end,
			set = function(_, value) ns.SetDisplaySetting("offsetX", value) end,
		},
		{
			kind = lem.SettingType.Slider,
			name = "Offset Y",
			desc = "Vertical offset.",
			minValue = -100, maxValue = 100, valueStep = 1,
			formatter = iconPx,
			default = ns.DEFAULT_DISPLAY.offsetY,
			get = function() return ns.GetDisplaySetting("offsetY") end,
			set = function(_, value) ns.SetDisplaySetting("offsetY", value) end,
		},
	})

	lem:AddFrameSettingsButtons(anchor, {
		{
			text = "Reset display defaults",
			click = function() ns.ResetDisplayDefaults() end,
		},
	})

	lem:RegisterCallback("layout", function()
		updateLayout(anchor)
	end)

	if ns.Debug then
		ns.Debug:print("anchor", "ready point=", db.point, "x=", db.x, "y=", db.y, "enabled=", db.enabled)
	end
end)
