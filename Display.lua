-- Per-unit horizontal icon row. One icon per tracked spell, ordered by
-- spellID. Bright = ready, desaturated + cooldown swipe = on cooldown.
--
-- Rows attach to the unit's Blizzard party / raid frame when one is
-- visible, else to ns.anchorFrame. A 1-second tick re-resolves the
-- frame so toggling between solo/party/raid layouts doesn't strand
-- rows on a hidden anchor target.
--
-- Layout knobs (iconSize / iconGap / growDirection / offsetX / offsetY)
-- live in DzakSharedCDsDB.display and are read fresh on every render —
-- no per-icon mutation when settings change, just call Display:UpdateAll
-- and everything re-lays-out with the new values.

local addonName, ns = ...

local UNKNOWN_ICON = 134400

local Display = {}
ns.Display = Display

-- unit -> { row = Frame, icons = { [spellId] = iconFrame } }
local rows = {}

-- Read the current display config from SavedVariables. Hot-path
-- function — called once per Render*; cheap.
local function GetCfg()
	return {
		iconSize      = ns.GetDisplaySetting("iconSize"),
		iconGap       = ns.GetDisplaySetting("iconGap"),
		growDirection = ns.GetDisplaySetting("growDirection"),
		offsetX       = ns.GetDisplaySetting("offsetX"),
		offsetY       = ns.GetDisplaySetting("offsetY"),
	}
end

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
	-- Size set by RenderRow; we only need a placeholder here.
	f:SetSize(1, 1)

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
	r:SetSize(1, 1) -- size grown dynamically in RenderRow
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

local function AnchorRowToUnit(row, unit, cfg)
	local frame = ns.PartyFrames:Resolve(unit)
	row:ClearAllPoints()
	if frame then
		row:SetParent(frame)
		row:SetFrameStrata(frame:GetFrameStrata())
		row:SetFrameLevel(frame:GetFrameLevel() + 5)
		-- Grow direction picks both the anchor edge and which way icons
		-- fan out. LEFT: row's right anchored to frame's left, icons
		-- laid right-to-left. RIGHT: mirror.
		if cfg.growDirection == "LEFT" then
			row:SetPoint("RIGHT", frame, "LEFT", -cfg.offsetX, cfg.offsetY)
		else
			row:SetPoint("LEFT", frame, "RIGHT", cfg.offsetX, cfg.offsetY)
		end
		row:Show()
	else
		-- Fallback: attach to the LibEditMode anchor. Grow direction picks
		-- which edge of the anchor the row hangs off — same semantics as
		-- the party-frame branch, so the Edit Mode preview lines up with
		-- the in-game layout. Multiple fallback rows stack downward via
		-- stackY so they don't pile on top of each other.
		local anchor = ns.anchorFrame
		if not anchor then row:Hide(); return end
		row:SetParent(anchor)
		row:SetFrameStrata("MEDIUM")
		row:SetFrameLevel(10)
		local idx = 0
		local groupUnits = ns.Tracker:GetGroupUnits()
		for i, u in ipairs(groupUnits) do
			if u == unit then idx = i - 1; break end
		end
		local stackY = -idx * (cfg.iconSize + cfg.iconGap)
		if cfg.growDirection == "LEFT" then
			row:SetPoint("RIGHT", anchor, "LEFT", -cfg.offsetX, cfg.offsetY + stackY)
		else
			row:SetPoint("LEFT", anchor, "RIGHT", cfg.offsetX, cfg.offsetY + stackY)
		end
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

	local cfg = GetCfg()
	AnchorRowToUnit(row, unit, cfg)
	row:SetHeight(cfg.iconSize)
	local unitState = ns.Tracker:GetUnitState(unit) or {}

	-- Lay out icons. For grow=RIGHT, anchor each icon's LEFT to the
	-- row's LEFT at increasing x. For grow=LEFT, anchor each icon's
	-- RIGHT to the row's RIGHT at increasing x (icons cascade leftward
	-- from the row's right edge — which is sitting against the party
	-- frame's left edge — so reading order is right-to-left).
	local x = 0
	for _, spellId in ipairs(tracked) do
		local icon = entry.icons[spellId]
		if not icon then
			icon = CreateIcon(row)
			entry.icons[spellId] = icon
		end
		icon.spellId = spellId
		icon:SetSize(cfg.iconSize, cfg.iconSize)
		icon:ClearAllPoints()
		if cfg.growDirection == "LEFT" then
			icon:SetPoint("RIGHT", row, "RIGHT", -x, 0)
		else
			icon:SetPoint("LEFT", row, "LEFT", x, 0)
		end

		local info = C_Spell.GetSpellInfo(spellId)
		local tex = (info and (info.originalIconID or info.iconID)) or UNKNOWN_ICON
		icon.icon:SetTexture(tex)

		ApplyCooldownVisual(icon, unitState[spellId])
		icon:Show()

		x = x + cfg.iconSize + cfg.iconGap
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

	row:SetWidth(math.max(1, x - cfg.iconGap))
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
		local cfg = GetCfg()
		for _, unit in ipairs(ns.Tracker:GetGroupUnits()) do
			local entry = rows[unit]
			if entry then AnchorRowToUnit(entry.row, unit, cfg) end
		end
	end)
end
