-- Per-unit horizontal icon row. One icon per tracked spell, ordered by
-- spellID. Bright = ready, desaturated + cooldown swipe = on cooldown.
--
-- Rows attach to the unit's on-screen party / raid frame via the
-- multi-provider resolver in PartyFrames.lua (ElvUI / Cell / Grid2 /
-- SUF / Danders / EnhanceQoL / Mich's / Blizzard). When the resolver
-- returns nil (no UI addon is currently showing that unit) the row
-- hides — there is no longer a fallback anchor. A 1-second tick
-- re-resolves the frame so toggling between solo/party/raid layouts
-- picks up the new frame target automatically.
--
-- All layout / visual knobs live in DzakSharedCDsDB.display and are
-- read fresh on every render, so dragging a slider in Settings just
-- needs to call Display:UpdateAll for the new value to take effect.

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
		iconSize       = ns.GetDisplaySetting("iconSize"),
		iconGap        = ns.GetDisplaySetting("iconGap"),
		growDirection  = ns.GetDisplaySetting("growDirection"),
		offsetX        = ns.GetDisplaySetting("offsetX"),
		offsetY        = ns.GetDisplaySetting("offsetY"),
		borderSize     = ns.GetDisplaySetting("borderSize"),
		borderColorR   = ns.GetDisplaySetting("borderColorR"),
		borderColorG   = ns.GetDisplaySetting("borderColorG"),
		borderColorB   = ns.GetDisplaySetting("borderColorB"),
		borderColorA   = ns.GetDisplaySetting("borderColorA"),
		cdGrayout      = ns.GetDisplaySetting("cdGrayout"),
		cdShowMinutes  = ns.GetDisplaySetting("cdShowMinutes"),
		cdTextFontSize = ns.GetDisplaySetting("cdTextFontSize"),
	}
end

-- Round-up integer countdown, with "5m" shorthand once we cross 60s and
-- the user has enabled minutes formatting. Matches BliZzi's style.
local function FormatRemaining(rem, showMinutes)
	if rem <= 0 then return "" end
	if rem >= 60 and showMinutes then
		return string.format("%dm", math.floor(rem / 60 + 0.5))
	end
	return tostring(math.ceil(rem))
end

local function GetTrackedSortedForUnit(unit)
	-- Render policy:
	--   1. Spec unknown                 -> hide (no useful default to draw)
	--   2. Spec known, no INIT received -> draw the full tracked-for-spec
	--      list. Some icons may never light up (sender doesn't actually
	--      have them), but "blank row until handshake" is worse UX than
	--      "row shrinks when handshake lands".
	--   3. Spec known, INIT received    -> filter to advertised only.
	local specId = ns.SpecCache:GetSpecForUnit(unit)
	if not specId then return nil end
	local tracked = ns.GetTrackedForSpec(specId)
	if not tracked then return nil end

	local adv = ns.Tracker:GetAdvertisedForUnit(unit)

	local list = {}
	if adv then
		for id in pairs(tracked) do
			if adv[id] then list[#list + 1] = id end
		end
	else
		for id in pairs(tracked) do
			list[#list + 1] = id
		end
	end
	table.sort(list)
	return list
end

local function CreateIcon(parent)
	local f = CreateFrame("Frame", nil, parent)
	-- Size set by RenderRow; placeholder until then.
	f:SetSize(1, 1)

	f.icon = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- Blizzard cooldown swipe — we draw our own countdown text on top
	-- (HideCountdownNumbers below) so the look stays consistent without
	-- depending on OmniCC. The swipe + bling are still Blizzard's.
	f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cooldown:SetAllPoints()
	f.cooldown:SetDrawEdge(false)
	f.cooldown:SetDrawBling(false)
	f.cooldown:SetHideCountdownNumbers(true)
	f.cooldown:SetSwipeColor(0, 0, 0, 0.8)
	f.cooldown:SetScript("OnCooldownDone", function()
		f.icon:SetDesaturated(false)
		if f.text then f.text:SetText("") end
	end)

	-- Outward-drawn border overlay (BliZzi pattern): a sibling Frame
	-- sized SLIGHTLY LARGER than the icon so the backdrop edgeFile —
	-- which Blizzard renders inward from the frame's edges — ends up
	-- sitting OUTSIDE the icon area instead of eating into the texture.
	-- ApplyIconBorder() resizes + restyles it from current cfg.
	f.borderOverlay = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.borderOverlay:SetAllPoints(f)
	f.borderOverlay:EnableMouse(false)

	-- Countdown text overlay. Lives on a higher-frame-level sibling so
	-- it always renders above the cooldown swipe and the border. Font
	-- + size assigned in ApplyIconText() so live size changes take
	-- effect without rebuilding the icon.
	local cdOverlay = CreateFrame("Frame", nil, f)
	cdOverlay:SetAllPoints(f)
	cdOverlay:SetFrameLevel(f:GetFrameLevel() + 30)
	f.text = cdOverlay:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER", cdOverlay, "CENTER", 0, 0)
	f.text:SetJustifyH("CENTER")
	f.text:SetTextColor(1, 1, 1)

	-- Per-icon tick: refresh the countdown text while a CD is running.
	-- One OnUpdate per visible icon is fine at our scale (~25 icons
	-- max), avoids the global-walker complexity, and naturally stops
	-- when the icon is hidden (Blizzard suspends OnUpdate on hidden
	-- frames). Throttled to ~10Hz which is plenty for whole-second
	-- digits.
	f._tickAccum = 0
	f:SetScript("OnUpdate", function(self, elapsed)
		self._tickAccum = (self._tickAccum or 0) + elapsed
		if self._tickAccum < 0.1 then return end
		self._tickAccum = 0
		if not self._cdExpiry or not self.text then return end
		local rem = self._cdExpiry - GetTime()
		if rem <= 0 then
			self.text:SetText("")
			self._cdExpiry = nil
		else
			self.text:SetText(FormatRemaining(rem, self._cdShowMinutes))
		end
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

-- Apply / refresh the outward border per current cfg. Border size 0
-- collapses the overlay to the icon bounds and clears the backdrop —
-- effectively disabling the border without leaking frame memory.
local function ApplyIconBorder(icon, cfg)
	local bo = icon.borderOverlay
	if not bo then return end
	local sz = cfg.borderSize or 0
	bo:ClearAllPoints()
	if sz > 0 then
		bo:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -sz,  sz)
		bo:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  sz, -sz)
		bo:SetBackdrop({
			edgeFile = "Interface\\BUTTONS\\WHITE8X8",
			edgeSize = sz,
			insets   = { left = 0, right = 0, top = 0, bottom = 0 },
		})
		bo:SetBackdropBorderColor(
			cfg.borderColorR or 0,
			cfg.borderColorG or 0,
			cfg.borderColorB or 0,
			cfg.borderColorA or 1)
		bo:Show()
	else
		bo:SetAllPoints(icon)
		bo:SetBackdrop(nil)
	end
end

-- Apply font + size to the countdown text. Cheap to call on every
-- render — FontString:SetFont is a no-op when the args don't change.
local function ApplyIconText(icon, cfg)
	if not icon.text then return end
	icon.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
		cfg.cdTextFontSize or 14, "OUTLINE")
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
	if not frame then
		-- No on-screen frame for this unit right now (between roster
		-- changes, or the user's UI addon is hiding its party header).
		-- Hide the row entirely — without a fallback anchor there's
		-- nowhere sensible to put it.
		row:Hide()
		return
	end

	row:ClearAllPoints()
	row:SetParent(frame)
	row:SetFrameStrata(frame:GetFrameStrata())
	row:SetFrameLevel(frame:GetFrameLevel() + 5)

	-- Grow direction = which edge of the party frame the row's matching
	-- edge sits against. Icons then extend INWARD across the frame's
	-- interior. LEFT: row's left aligns to the frame's left, icons grow
	-- rightward into the frame. RIGHT: mirror. Use a negative offsetX
	-- to push the row outside the frame entirely.
	if cfg.growDirection == "LEFT" then
		row:SetPoint("LEFT", frame, "LEFT", cfg.offsetX, cfg.offsetY)
	else
		row:SetPoint("RIGHT", frame, "RIGHT", -cfg.offsetX, cfg.offsetY)
	end
	row:Show()
end

local function ApplyCooldownVisual(iconFrame, cdEntry, cfg)
	-- Stash the cfg bits the per-icon OnUpdate needs so the tick doesn't
	-- have to re-read SavedVariables on every fire.
	iconFrame._cdShowMinutes = cfg.cdShowMinutes
	if cdEntry and cdEntry.duration and cdEntry.duration > 0 then
		local now = GetTime()
		local remaining = cdEntry.readyAt - now
		if remaining > 0 then
			iconFrame.cooldown:SetCooldown(cdEntry.startTime, cdEntry.duration)
			iconFrame.cooldown:SetDrawSwipe(true)
			iconFrame.icon:SetDesaturated(cfg.cdGrayout ~= false)
			iconFrame._cdExpiry = cdEntry.readyAt
			if iconFrame.text then
				iconFrame.text:SetText(FormatRemaining(remaining, cfg.cdShowMinutes))
			end
			return
		end
	end
	iconFrame._cdExpiry = nil
	if iconFrame.text then iconFrame.text:SetText("") end
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

	-- Icons grow INWARD from the row's anchored edge. grow=LEFT: row's
	-- left sits against the frame's left, so icon 1 hugs the left edge
	-- and 2..N extend rightward into the frame. grow=RIGHT: icon 1 hugs
	-- the right edge, 2..N extend leftward.
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
			icon:SetPoint("LEFT", row, "LEFT", x, 0)
		else
			icon:SetPoint("RIGHT", row, "RIGHT", -x, 0)
		end

		local info = C_Spell.GetSpellInfo(spellId)
		local tex = (info and (info.originalIconID or info.iconID)) or UNKNOWN_ICON
		icon.icon:SetTexture(tex)

		-- BliZzi-style polish: outward border + outlined countdown text.
		-- Both are cfg-driven so the user can disable border via size=0
		-- or change font size live from Settings.
		ApplyIconBorder(icon, cfg)
		ApplyIconText(icon, cfg)
		ApplyCooldownVisual(icon, unitState[spellId], cfg)
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
