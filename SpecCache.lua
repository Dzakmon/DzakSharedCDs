-- Caches each known player's spec ID, sourced from LibSpecialization
-- (which broadcasts specs between addons on its own hidden channel).
--
-- Public:
--   ns.SpecCache:GetSpecForUnit(unit) -> specId or nil
--   ns.SpecCache:GetLocalSpec()       -> specId or nil

local addonName, ns = ...

local SpecCache = {}
ns.SpecCache = SpecCache

-- short name -> specId. Cross-realm collisions in the same group are rare
-- enough to ignore for v1.
local byName = {}

local function NormalizeName(name)
	if not name then return nil end
	return Ambiguate(name, "none")
end

function SpecCache:GetLocalSpec()
	local idx = GetSpecialization and GetSpecialization()
	if not idx then return nil end
	local id = GetSpecializationInfo and GetSpecializationInfo(idx)
	return id
end

function SpecCache:GetSpecForUnit(unit)
	if not unit or not UnitExists(unit) then return nil end
	if UnitIsUnit(unit, "player") then
		return self:GetLocalSpec()
	end
	local short = NormalizeName(UnitName(unit))
	return short and byName[short] or nil
end

-- Called when a (re)render is due because somebody's spec became known
-- or changed. Defined by Main during boot to avoid load-order issues.
local onChange = nil
function SpecCache:SetChangeHandler(fn) onChange = fn end

local function OnSpecCallback(specId, role, position, playerName)
	if not specId or not playerName then return end
	local short = NormalizeName(playerName)
	if not short then return end
	local prev = byName[short]
	byName[short] = specId
	if prev ~= specId and onChange then
		onChange(short, specId)
	end
end

function SpecCache:Init()
	local LS = LibStub("LibSpecialization", true)
	if not LS then
		if ns.Debug then ns.Debug:print("speccache", "LibSpecialization missing") end
		return
	end
	LS.RegisterGroup(self, OnSpecCallback)

	-- LibSpecialization's PLAYER_LOGIN-triggered broadcast fires BEFORE
	-- we register here (we boot on PLAYER_ENTERING_WORLD which comes
	-- later), so our callback wouldn't otherwise fire for our OWN spec
	-- until the next ACTIVE_COMBAT_CONFIG_CHANGED / GROUP_ROSTER_UPDATE.
	-- Force-poke it now so the local player's spec lands immediately and
	-- our first INIT can include real data.
	if LS.RequestGroupSpecialization then
		LS.RequestGroupSpecialization()
	end
end
