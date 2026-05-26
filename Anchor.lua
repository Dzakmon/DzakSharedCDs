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

	lem:RegisterCallback("layout", function()
		updateLayout(anchor)
	end)

	if ns.Debug then
		ns.Debug:print("anchor", "ready point=", db.point, "x=", db.x, "y=", db.y, "enabled=", db.enabled)
	end
end)
