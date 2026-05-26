-- Maps a unit token ("player", "party1"..) to the visible Blizzard frame
-- representing that unit. Supports only the default Blizzard UI for v1:
--   - CompactPartyFrameMember1..5 (raid-style party frames)
--   - PartyFrame.MemberFrame1..5  (standard party frames)
-- Returns nil if neither is visible (e.g. third-party UI like ElvUI / Grid
-- has hidden the defaults). Callers fall back to ns.anchorFrame.

local addonName, ns = ...

local PartyFrames = {}
ns.PartyFrames = PartyFrames

local MAX_SLOTS = (MAX_PARTY_MEMBERS or 4) + 1 -- + 1 for player/self

local function FrameMatchesUnit(frame, unit)
	if not frame or not frame:IsVisible() then return false end
	local frameUnit = frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
	if not frameUnit then return false end
	-- UnitIsUnit handles aliasing ("party1" vs "raid3" vs name-realm).
	return UnitIsUnit(frameUnit, unit)
end

function PartyFrames:Resolve(unit)
	for i = 1, MAX_SLOTS do
		local f = _G["CompactPartyFrameMember" .. i]
		if FrameMatchesUnit(f, unit) then return f end
	end

	if PartyFrame then
		for i = 1, MAX_SLOTS do
			local f = PartyFrame["MemberFrame" .. i]
			if FrameMatchesUnit(f, unit) then return f end
		end
	end

	return nil
end
