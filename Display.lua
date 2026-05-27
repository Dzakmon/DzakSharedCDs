-- Per-unit horizontal icon row. One icon per tracked spell, ordered by
-- spellID. Bright = ready, desaturated + cooldown swipe = on cooldown.
--
-- Rows attach to the unit's Blizzard party frame when one is visible,
-- else to ns.anchorFrame. A 1-second tick re-resolves the party frame
-- so that toggling between solo/party/raid layouts doesn't strand rows
-- on a hidden anchor target.

local addonName, ns = ...

local ICON_SIZE = 24
local ICON_GAP = 2
local ROW_OFFSET_X = 6 -- gap between party frame's right edge and the row
local ROW_OFFSET_Y = 0

local UNKNOWN_ICON = 134400

local Display = {}
ns.Display = Display

-- unit -> { row = Frame, icons = { [spellId] = iconFrame } }
local rows = {}

local function GetTrackedSortedForUnit(unit)
	-- Two pieces of information are needed before we can render a unit's
	-- row: (1) what spells WE think their spec tracks (from defaults +
	-- our edits in Settings), and (2) what spells THEY actually have
	-- talented (from their INIT broadcast). The intersection is what
	-- we draw.
	--
	-- If we haven't received INIT yet, we hide the row entirely rather
	-- than guess — guessing leads to the "spells that show ready forever
	-- because the sender doesn't actually have them" bug INIT exists to
	-- fix. For the local player, Tracker computes advertised on demand
	-- so there's never a "waiting for our own INIT" gap.
	local specId = ns.SpecCache:GetSpecForUnit(unit)
	if not specId then return nil end
	local tracked = ns.GetTrackedForSpec(specId)
	if not tracked then return nil end

	local adv = ns.Tracker:GetAdvertisedForUnit(unit)
	if not adv then return nil end

	local list = {}
	for id in pairs(tracked) do
		if adv[id] then list[#list + 1] = id end
	end
	table.sort(list)
	return list
end

local function CreateIcon(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(ICON_SIZE, ICON_SIZE)

	f.icon = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cooldown:SetAllPoints()
	f.cooldown:SetDrawEdge(false)
	f.cooldown:SetDrawBling(false)
	f.cooldown:SetHideCountdownNumbers(false)
	f.cooldown:SetSwipeColor(0, 0, 0, 0.8)
	f.cooldown:SetScript("OnCooldownDone", function()
		f.icon:SetDesaturated(false)
	end)

	-- Tooltip on hover so the user can see what each icon represents.
	f:SetScript("OnEnter", function(self)
		if not self.spellId then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(self.spellId)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return f
end

local function CreateRow(unit)
	local r = CreateFrame("Frame", nil, UIParent)
	r:SetSize(1, ICON_SIZE) -- width grown dynamically
	r:SetFrameStrata("MEDIUM")
	r.unit = unit
	r.icons = {}
	return r
end

local function GetOrCreateRow(unit)
	local entry = rows[unit]
	if entry then return entry end
	local row = CreateRow(unit)
	entry = { row = row, icons = {} }
	rows[unit] = entry
	return entry
end

local function ReleaseRow(unit)
	local entry = rows[unit]
	if not entry then return end
	entry.row:Hide()
	entry.row:SetParent(nil)
	entry.row:ClearAllPoints()
	rows[unit] = nil
end

local function AnchorRowToUnit(row, unit)
	local frame = ns.PartyFrames:Resolve(unit)
	row:ClearAllPoints()
	if frame then
		row:SetParent(frame)
		row:SetFrameStrata(frame:GetFrameStrata())
		row:SetFrameLevel(frame:GetFrameLevel() + 5)
		row:SetPoint("LEFT", frame, "RIGHT", ROW_OFFSET_X, ROW_OFFSET_Y)
		row:Show()
	else
		-- Fallback: stack rows under the LibEditMode anchor.
		local anchor = ns.anchorFrame
		if not anchor then row:Hide(); return end
		row:SetParent(anchor)
		row:SetFrameStrata("MEDIUM")
		row:SetFrameLevel(10)
		-- Stagger by unit index so multiple fallback rows don't pile up.
		local idx = 0
		for i = 1, (MAX_PARTY_MEMBERS or 4) + 1 do
			local u = (i == 1) and "player" or ("party" .. (i - 1))
			if u == unit then idx = i - 1; break end
		end
		row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -idx * (ICON_SIZE + ICON_GAP))
		row:Show()
	end
end

local function ApplyCooldownVisual(iconFrame, cdEntry)
	if cdEntry and cdEntry.duration and cdEntry.duration > 0 then
		local now = GetTime()
		local remaining = cdEntry.readyAt - now
		if remaining > 0 then
			iconFrame.cooldown:SetCooldown(cdEntry.startTime, cdEntry.duration)
			iconFrame.cooldown:SetDrawSwipe(true)
			iconFrame.icon:SetDesaturated(true)
			return
		end
	end
	-- Clear alone leaves the swipe overlay drawn; SetDrawSwipe(false) is
	-- required to actually erase it (matches MiniCC's clear path).
	iconFrame.cooldown:Clear()
	iconFrame.cooldown:SetDrawSwipe(false)
	iconFrame.icon:SetDesaturated(false)
end

local function RenderRow(unit)
	local entry = GetOrCreateRow(unit)
	local row = entry.row

	-- nil tracked = either spec is unknown (LibSpecialization handshake
	-- pending) or INIT hasn't arrived. Empty tracked = the sender's
	-- advertised list has no overlap with what we'd render for that
	-- spec. Both cases: hide the row entirely.
	local tracked = GetTrackedSortedForUnit(unit)
	if not tracked or #tracked == 0 then
		row:Hide()
		return
	end

	AnchorRowToUnit(row, unit)
	local unitState = ns.Tracker:GetUnitState(unit) or {}

	-- Lay out icons left-to-right, creating on demand.
	local x = 0
	for i, spellId in ipairs(tracked) do
		local icon = entry.icons[spellId]
		if not icon then
			icon = CreateIcon(row)
			entry.icons[spellId] = icon
		end
		icon.spellId = spellId
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", row, "LEFT", x, 0)

		local info = C_Spell.GetSpellInfo(spellId)
		local tex = (info and (info.originalIconID or info.iconID)) or UNKNOWN_ICON
		icon.icon:SetTexture(tex)

		ApplyCooldownVisual(icon, unitState[spellId])
		icon:Show()

		x = x + ICON_SIZE + ICON_GAP
	end

	-- Hide any leftover icons for spells that are no longer tracked.
	for spellId, icon in pairs(entry.icons) do
		local stillTracked = false
		for _, id in ipairs(tracked) do
			if id == spellId then stillTracked = true; break end
		end
		if not stillTracked then
			icon:Hide()
			icon.spellId = nil
		end
	end

	row:SetWidth(math.max(1, x - ICON_GAP))
end

function Display:UpdateUnit(unit)
	if not ns.IsEnabled() then
		ReleaseRow(unit)
		return
	end
	RenderRow(unit)
end

function Display:UpdateAll()
	if not ns.IsEnabled() then
		for unit in pairs(rows) do ReleaseRow(unit) end
		return
	end

	local alive = {}
	for _, unit in ipairs(ns.Tracker:GetGroupUnits()) do
		alive[unit] = true
		RenderRow(unit)
	end
	for unit in pairs(rows) do
		if not alive[unit] then ReleaseRow(unit) end
	end
end

-- Periodic re-anchor: Blizzard frames shuffle as the roster changes and
-- there's no reliable single event to hook for "the party frame for unit
-- party2 is now visible at a different layout". Cheap polling is fine.
function Display:StartTicker()
	C_Timer.NewTicker(1.0, function()
		if not ns.IsEnabled() then return end
		for _, unit in ipairs(ns.Tracker:GetGroupUnits()) do
			local entry = rows[unit]
			if entry then AnchorRowToUnit(entry.row, unit) end
		end
	end)
end
