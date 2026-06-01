-- Shared unit-frame resolver. Given a unit token (player, party1..4,
-- raid1..40) returns the on-screen frame currently displaying that
-- unit, picking between Blizzard frames and the most common third-party
-- party addons (ElvUI, Cell, Grid2, ShadowedUnitFrames, Danders / D4,
-- EnhanceQoL, Mich's RaidFrames).
--
-- Adapted from BliZzi_Interrupts/Core/UnitFrames.lua — same provider
-- list and AUTO precedence. Two adjustments for our addon:
--   - Namespaced under ns.PartyFrames so the rest of the codebase
--     keeps its existing ns.PartyFrames:Resolve(unit) call site.
--   - Drop the per-feature provider-override settings (BliZzi exposes
--     a dropdown so different features can use different providers;
--     we only have one renderer, so AUTO is fine).
--
-- Provider precedence in AUTO (first match wins):
--   ElvUI → Danders → Cell → Grid2 → EnhanceQoL → SUF → Mich's → Blizzard
-- This order tries the most opinionated / replacement-style addons
-- first because users running those almost always want them as the
-- anchor target, with Blizzard as the always-present fallback.

local addonName, ns = ...

local PartyFrames = {}
ns.PartyFrames = PartyFrames

------------------------------------------------------------
-- Provider activation probes
--
-- Each function returns true when the corresponding party-frame addon
-- has loaded AND created its top-level container global. We check the
-- FRAME globals (not just IsAddOnLoaded) because some addons can be
-- present in the addon list but not actually displaying party frames
-- yet (e.g. before the first PLAYER_LOGIN tick after a /reload).
------------------------------------------------------------
local function IsElvUIActive()
	return _G["ElvUI"] ~= nil or _G["ElvUF_PartyGroup1"] ~= nil
end

local function IsDandersActive()
	return _G["DandersPartyHeader"] ~= nil
end

local function IsGrid2Active()
	return _G["Grid2LayoutFrame"] ~= nil
end

local function IsCellActive()
	return _G["Cell"] ~= nil
end

local function IsEnhanceQOLActive()
	if _G["EQOLUFPartyHeader"] ~= nil then return true end
	if _G["EQOLUFPartyHeaderUnitButton1"] ~= nil then return true end
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EnhanceQoL") then
		return true
	end
	return false
end

local function IsSUFActive()
	-- ShadowedUnitFrames creates SUFHeaderparty as the party header and
	-- SUFUnitplayer as the standalone player frame.
	return _G["SUFHeaderparty"] ~= nil or _G["SUFUnitplayer"] ~= nil
end

local function IsMichsActive()
	if _G["MRF_PartyHeader"] ~= nil then return true end
	for i = 1, 8 do
		if _G["MRF_RaidHeader" .. i] ~= nil then return true end
	end
	return false
end

------------------------------------------------------------
-- Frame helpers
------------------------------------------------------------

-- A frame that isn't visible right now isn't a valid anchor target even
-- if its unit attribute matches (ElvUI keeps both party and raid headers
-- alive simultaneously, only one is on-screen at a time).
local function visible(f) return f and f:IsVisible() end

-- Read a frame's bound unit. Secure-header children set their unit via
-- SetAttribute("unit", ...); we prefer that over the .unit table field
-- because the attribute survives child recycling on roster changes. The
-- pcall is needed because GetAttribute can throw on tainted handlers in
-- 12.0.5 secure-frame edge cases.
local function GetFrameUnit(btn)
	if not btn then return nil end
	local u
	if btn.GetAttribute then
		local ok, val = pcall(btn.GetAttribute, btn, "unit")
		if ok then u = val end
	end
	if (not u or u == "") and btn.unit then u = btn.unit end
	if type(u) ~= "string" or u == "" then return nil end
	return u
end

-- Generic numbered-button scan. Iterates "<prefix>1" through "<prefix>N"
-- and returns the first child whose unit matches.
-- 12.0.5 note: we compare unit strings directly instead of calling
-- UnitIsUnit() — in Midnight that API can return a tainted boolean when
-- one side is a secret value, which throws as soon as the bool is
-- evaluated in an `if`. Direct string compare side-steps the issue,
-- and since each header child is bound to a single fixed unit slot the
-- alias resolution UnitIsUnit() would do isn't needed here.
local function ScanUnitButtons(prefix, unit, maxSlots)
	for i = 1, maxSlots do
		local btn = _G[prefix .. i]
		if btn and GetFrameUnit(btn) == unit then return btn end
	end
end

local function ScanGrid2(unit)
	for h = 1, 8 do
		local f = ScanUnitButtons("Grid2LayoutHeader" .. h .. "UnitButton", unit, 40)
		if f then return f end
	end
end

------------------------------------------------------------
-- Provider-specific finders
------------------------------------------------------------

local function FindElvUI(unit)
	if not IsElvUIActive() then return nil end
	local group = _G["ElvUF_PartyGroup1"]
	if group then
		for i = 1, group:GetNumChildren() do
			local child = select(i, group:GetChildren())
			if visible(child) and GetFrameUnit(child) == unit then
				return child
			end
		end
	end
	if unit == "player" then
		local pf = _G["ElvUF_Player"]
		if visible(pf) then return pf end
	end
	local f = ScanUnitButtons("ElvUF_PartyGroup1UnitButton", unit, 5)
	if visible(f) then return f end
end

local function FindDanders(unit)
	if not IsDandersActive() then return nil end
	local f = ScanUnitButtons("DandersPartyHeaderUnitButton", unit, 5)
	if visible(f) then return f end
	if unit == "player" then
		local playerBtn = _G["DandersPartyHeaderUnitButton0"] or _G["DandersPlayerFrame"]
		if visible(playerBtn) then return playerBtn end
	end
end

local function FindGrid2(unit)
	if not IsGrid2Active() then return nil end
	local f = ScanGrid2(unit)
	if visible(f) then return f end
end

local function FindEnhanceQOL(unit)
	if not IsEnhanceQOLActive() then return nil end
	local f = ScanUnitButtons("EQOLUFPartyHeaderUnitButton", unit, 5)
	if visible(f) then return f end
	if unit == "player" then
		local pf = _G["EQOLUFPlayerFrame"] or _G["EQOLUFPartyHeaderUnitButton0"]
		if visible(pf) then return pf end
	end
end

local function FindSUF(unit)
	if not IsSUFActive() then return nil end
	local f = ScanUnitButtons("SUFHeaderpartyUnitButton", unit, 5)
	if visible(f) then return f end
	if unit == "player" then
		local pf = _G["SUFUnitplayer"]
		if visible(pf) then return pf end
	end
end

-- Mich's uses SecureGroupHeaderTemplate. Children get their .unit via
-- OnAttributeChanged when the header binds them. We iterate header
-- children rather than scanning a numbered global because SecureGroup-
-- Header names children dynamically.
local function FindMichs(unit)
	if not IsMichsActive() then return nil end
	local partyHeader = _G["MRF_PartyHeader"]
	if partyHeader and visible(partyHeader) then
		for i = 1, partyHeader:GetNumChildren() do
			local child = select(i, partyHeader:GetChildren())
			if visible(child) and GetFrameUnit(child) == unit then
				return child
			end
		end
	end
	for g = 1, 8 do
		local raidHeader = _G["MRF_RaidHeader" .. g]
		if raidHeader and visible(raidHeader) then
			for i = 1, raidHeader:GetNumChildren() do
				local child = select(i, raidHeader:GetChildren())
				if visible(child) and GetFrameUnit(child) == unit then
					return child
				end
			end
		end
	end
end

local function FindCell(unit)
	if not IsCellActive() then return nil end
	local header = _G["CellPartyFrameHeader"]
	if header and header:IsVisible() then
		local f = ScanUnitButtons("CellPartyFrameHeaderUnitButton", unit, 5)
		if visible(f) then return f end
	end
	if unit == "player" then
		local solo = _G["CellSoloFramePlayer"]
		if visible(solo) then return solo end
	end
end

local function FindBlizzard(unit)
	-- Newer "PartyFrame" container (Edit Mode classic party layout).
	local pf = _G["PartyFrame"]
	if pf then
		for i = 1, 4 do
			local f = pf["MemberFrame" .. i]
			if visible(f) and GetFrameUnit(f) == unit then return f end
		end
	end
	-- Compact party (raid-style toggle off).
	for i = 1, 5 do
		local f = _G["CompactPartyFrameMember" .. i]
		if visible(f) and GetFrameUnit(f) == unit then return f end
	end
	-- Compact raid container — when raid-style is on, party frames live
	-- inside the raid container as CompactRaidFrame1..N.
	for i = 1, 40 do
		local f = _G["CompactRaidFrame" .. i]
		if visible(f) and GetFrameUnit(f) == unit then return f end
	end
	-- Standalone player frame fallback (works in both layouts).
	if unit == "player" then
		local bf = _G["PlayerFrame"]
		if visible(bf) then return bf end
	end
end

------------------------------------------------------------
-- AUTO detection — ordered priority
------------------------------------------------------------
local function FindAuto(unit)
	return FindElvUI(unit)
		or FindDanders(unit)
		or FindCell(unit)
		or FindGrid2(unit)
		or FindEnhanceQOL(unit)
		or FindSUF(unit)
		or FindMichs(unit)
		or FindBlizzard(unit)
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function PartyFrames:Resolve(unit)
	if not unit then return nil end
	return FindAuto(unit)
end

-- Diagnostic: list of providers currently loaded. Useful in a future
-- "which UI addon do you use?" first-run prompt.
function PartyFrames:GetActiveProviders()
	local list = {}
	if IsElvUIActive()      then list[#list + 1] = "ElvUI"      end
	if IsDandersActive()    then list[#list + 1] = "D4/Danders" end
	if IsCellActive()       then list[#list + 1] = "Cell"       end
	if IsGrid2Active()      then list[#list + 1] = "Grid2"      end
	if IsEnhanceQOLActive() then list[#list + 1] = "EnhanceQoL" end
	if IsSUFActive()        then list[#list + 1] = "ShadowedUF" end
	if IsMichsActive()      then list[#list + 1] = "Mich's"     end
	list[#list + 1] = "Blizzard"
	return list
end
