-- Maps a unit token ("player", "party1"..,  "raid1"..) to the visible
-- Blizzard frame representing that unit. Supports default Blizzard UI:
--   - CompactPartyFrameMember1..5  (raid-style party frames)
--   - PartyFrame.MemberFrame1..5   (standard party frames)
--   - CompactRaidFrame1..40        (raid frames, used in 6+ man groups)
-- Returns nil if no matching visible frame is found (e.g. third-party UI
-- like ElvUI / Grid has hidden the defaults). Callers fall back to
-- ns.anchorFrame.

local addonName, ns = ...

local PartyFrames = {}
ns.PartyFrames = PartyFrames

local MAX_PARTY_SLOTS = (MAX_PARTY_MEMBERS or 4) + 1 -- + 1 for player/self
local MAX_RAID_SLOTS  = MAX_RAID_MEMBERS or 40

local function FrameMatchesUnit(frame, unit)
	if not frame or not frame:IsVisible() then return false end
	local frameUnit = frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
	if not frameUnit then return false end
	-- UnitIsUnit handles aliasing ("party1" vs "raid3" vs name-realm).
	return UnitIsUnit(frameUnit, unit)
end

function PartyFrames:Resolve(unit)
	-- Raid frames take precedence: in raids the party frames are hidden
	-- but their .unit attribute is still set, so a stale match would win.
	if IsInRaid() then
		for i = 1, MAX_RAID_SLOTS do
			local f = _G["CompactRaidFrame" .. i]
			if FrameMatchesUnit(f, unit) then return f end
		end
	end

	for i = 1, MAX_PARTY_SLOTS do
		local f = _G["CompactPartyFrameMember" .. i]
		if FrameMatchesUnit(f, unit) then return f end
	end

	if PartyFrame then
		for i = 1, MAX_PARTY_SLOTS do
			local f = PartyFrame["MemberFrame" .. i]
			if FrameMatchesUnit(f, unit) then return f end
		end
	end

	-- Last-resort raid scan: handles the "Raid-style frames for parties"
	-- option, which routes 5-man party members through CompactRaidFrame.
	for i = 1, MAX_RAID_SLOTS do
		local f = _G["CompactRaidFrame" .. i]
		if FrameMatchesUnit(f, unit) then return f end
	end

	return nil
end
