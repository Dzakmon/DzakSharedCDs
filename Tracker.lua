-- Cooldown state + three flows that mutate it:
--   1. Local cast: player cast a tracked spell -> record + broadcast
--      USED, then schedule a READY broadcast after the cooldown ends.
--   2. Remote message: a party member's USED/READY arrived -> resolve
--      sender -> unit, update that unit's state, refresh display.
--   3. INIT handshake: on ready check / login / spec swap / talent
--      change / roster change, each client broadcasts the intersection
--      of (their spec's tracked list) ∩ (spells they actually know).
--      Receivers cache this and use it to filter what gets drawn for
--      that sender's row, so spells the sender isn't talented into
--      don't render as "ready" forever.
--
-- Sender identity: CHAT_MSG_ADDON's sender field is globally unique
-- (Name-Realm for cross-realm, Name otherwise — names are unique per
-- realm). We resolve sender -> unit by comparing UnitName() of every
-- group unit, so two paladins or two of the same spec in the group are
-- distinguished by name, never by class. As an additional safeguard,
-- PruneRoster tracks each unit's GUID and clears state when a slot's
-- GUID changes (e.g., one party member leaves, another takes their
-- party1 slot before we got a GROUP_ROSTER_UPDATE).

local addonName, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local MAX_PARTY = MAX_PARTY_MEMBERS or 4
local MAX_RAID  = MAX_RAID_MEMBERS or 40
-- INIT broadcasts are debounced so a burst of triggers (e.g.,
-- GROUP_ROSTER_UPDATE firing several times during a roster cascade)
-- generates one wire message, not many.
local INIT_DEBOUNCE_SECONDS = 2.5
local INIT_MIN_INTERVAL = 3

-- unit -> { [spellId] = { startTime, duration, readyAt } }
local state = {}
-- unit -> { [spellId] = true }; what each sender said they have. nil
-- means "INIT not yet received from this unit".
local advertised = {}
-- unit -> GUID; lets PruneRoster detect a slot whose player changed.
local unitGuid = {}
-- spellId -> outstanding C_Timer ticket; cancelled if we cast again
-- before the previous READY fires (avoids stale "ready" broadcasts).
local pendingReadyTimers = {}
-- spellId -> base cooldown in seconds. Primed from GetSpellBaseCooldown
-- whenever the local advertised set is built, so OnLocalCast can read a
-- known duration without racing UNIT_SPELLCAST_SUCCEEDED against the
-- engine committing the cooldown. Wiped on talent / spec change.
local baseCooldownByspell = {}

local pendingInitTimer = nil
local lastInitSent = 0

local function GetTrackedSetForLocalSpec()
	local specId = ns.SpecCache:GetLocalSpec()
	if not specId then return nil end
	return ns.GetTrackedForSpec(specId)
end

-- Player first so self always renders at a stable position. In raids
-- the partyN tokens are empty — Blizzard switches to raidN — so we have
-- to branch. UnitIsUnit skips the raid slot the player occupies, to
-- avoid double-rendering self.
local function IterateGroupUnits()
	local units = { "player" }
	if IsInRaid() then
		for i = 1, MAX_RAID do
			local u = "raid" .. i
			if UnitExists(u) and not UnitIsUnit(u, "player") then
				units[#units + 1] = u
			end
		end
	elseif IsInGroup() then
		for i = 1, MAX_PARTY do
			local u = "party" .. i
			if UnitExists(u) then
				units[#units + 1] = u
			end
		end
	end
	return units
end

function Tracker:GetGroupUnits()
	return IterateGroupUnits()
end

function Tracker:GetUnitState(unit)
	return state[unit]
end

function Tracker:GetAdvertisedForUnit(unit)
	if unit == "player" or (UnitExists(unit) and UnitIsUnit(unit, "player")) then
		-- Local advertised list is computed on demand from current spec
		-- ∩ IsPlayerSpell; no need to wait for our own INIT to round-trip.
		return Tracker:BuildLocalAdvertisedSet()
	end
	return advertised[unit]
end

local function EnsureUnitTable(unit)
	state[unit] = state[unit] or {}
	return state[unit]
end

local function RecordUsed(unit, spellId, duration)
	local t = EnsureUnitTable(unit)
	local now = GetTime()
	t[spellId] = {
		startTime = now,
		duration  = duration,
		readyAt   = now + duration,
	}
end

local function RecordReady(unit, spellId)
	if state[unit] then state[unit][spellId] = nil end
end

local function NotifyDisplay(unit)
	if ns.Display then ns.Display:UpdateUnit(unit) end
end

local function NotifyDisplayAll()
	if ns.Display then ns.Display:UpdateAll() end
end

-- Match a normalized sender name ("Bob" or "Bob-Realm") to a unit token
-- in our current group.
local function ResolveSenderUnit(sender)
	if not sender then return nil end
	for _, unit in ipairs(IterateGroupUnits()) do
		local name, realm = UnitName(unit)
		if name then
			local full = realm and realm ~= "" and (name .. "-" .. realm) or name
			if sender == name or sender == full then
				return unit
			end
		end
	end
	return nil
end

-- Best-effort instant CD lookup for the local-cast path.
-- C_Spell.GetSpellBaseCooldown returns the spell's static base CD in
-- milliseconds, available even when the spell isn't on cooldown. It
-- ignores talent CDR — but it's only used for the "instant local row
-- dim" before the 0.1s-deferred broadcast computes the authoritative
-- post-cast CD via C_Spell.GetSpellCooldown.
local QueryBaseCooldownMs = (C_Spell and C_Spell.GetSpellBaseCooldown) or _G.GetSpellBaseCooldown

local function GetBaseCooldownSeconds(spellId)
	if not QueryBaseCooldownMs then return nil end
	local ms = QueryBaseCooldownMs(spellId)
	if ms and ms >= 2000 then return ms / 1000 end
	return nil
end

-- ============================================================
-- INIT FLOW: announce what we have, consume others' announcements
-- ============================================================

-- C_SpellBook.IsSpellKnown is the modern (12.0+) replacement for the
-- deprecated IsPlayerSpell. Returns true if the local player currently
-- has the spell available — covers class/spec baseline AND talent
-- choices, including talent replacements (e.g., choosing Crusade
-- removes the base Avenging Wrath from the known set). Local alias so
-- the per-spell loop below avoids the table lookup on the hot path.
local IsSpellKnownByPlayer = C_SpellBook.IsSpellKnown

function Tracker:BuildLocalAdvertisedSet()
	local tracked = GetTrackedSetForLocalSpec()
	if not tracked then return nil end
	local set = {}
	for spellId in pairs(tracked) do
		if IsSpellKnownByPlayer(spellId) then
			set[spellId] = true
		end
	end
	return set
end

local function ActuallySendInit()
	pendingInitTimer = nil
	if not ns.IsEnabled() then return end
	local now = GetTime()
	if now - lastInitSent < INIT_MIN_INTERVAL then return end

	local set = Tracker:BuildLocalAdvertisedSet()
	if not set then return end

	-- Build comma-separated CSV. Empty payload is meaningful too —
	-- "I'm running the addon but tracking nothing right now."
	local ids = {}
	for spellId in pairs(set) do ids[#ids + 1] = spellId end
	table.sort(ids)
	local csv = table.concat(ids, ",")
	if csv == "" then csv = "0" end -- sentinel; "INIT:0" parses cleanly

	lastInitSent = now
	ns.Chat:Send("INIT", csv)
	if ns.Debug then ns.Debug:print("init-send", #ids, "spells") end
end

function Tracker:ScheduleInitBroadcast(delaySeconds)
	if pendingInitTimer then return end
	pendingInitTimer = C_Timer.NewTimer(delaySeconds or INIT_DEBOUNCE_SECONDS, ActuallySendInit)
end

function Tracker:OnRemoteInit(unit, payload)
	local set = {}
	if payload ~= "0" then
		for idStr in payload:gmatch("(%d+)") do
			local id = tonumber(idStr)
			if id and id > 0 then set[id] = true end
		end
	end
	advertised[unit] = set
	-- An INIT may have changed the visible list; also drop any cooldown
	-- state for spells the sender no longer advertises (they respec'd
	-- out of it, etc.) so stale "on cooldown" doesn't linger.
	if state[unit] then
		for spellId in pairs(state[unit]) do
			if not set[spellId] then state[unit][spellId] = nil end
		end
	end
	if ns.Debug then
		local n = 0; for _ in pairs(set) do n = n + 1 end
		ns.Debug:print("init-recv", unit, n, "spells")
	end
	NotifyDisplay(unit)
end

-- ============================================================
-- LOCAL FLOW: player cast a tracked spell
-- ============================================================

local function ScheduleReadyBroadcast(spellId, duration)
	local prev = pendingReadyTimers[spellId]
	if prev and prev.Cancel then prev:Cancel() end

	pendingReadyTimers[spellId] = C_Timer.NewTimer(duration, function()
		pendingReadyTimers[spellId] = nil
		RecordReady("player", spellId)
		NotifyDisplay("player")
		ns.Chat:Send("READY", spellId)
		if ns.Debug then ns.Debug:print("local-ready", spellId) end
	end)
end

-- Read the authoritative post-cast cooldown for the local player. Must
-- be called AFTER the engine has committed the new CD (which it hasn't
-- yet at UNIT_SPELLCAST_SUCCEEDED — at that exact moment GetSpellCooldown
-- returns 0 or just the GCD). We defer 0.1s in OnLocalCast for this
-- reason; by then C_Spell.GetSpellCooldown.duration is the true value
-- including talent/proc CDR.
local function ReadAuthoritativeCooldown(spellId)
	local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellId)
	if cd and cd.duration and cd.duration > 1.6 then
		return cd.duration
	end
	return nil
end

function Tracker:OnLocalCast(spellId)
	if not ns.IsEnabled() then return end
	local tracked = GetTrackedSetForLocalSpec()
	if not tracked or not tracked[spellId] then return end

	-- Instant local feedback with base CD (engine hasn't committed the
	-- real CD yet). This is a guess; if a talent shortens this spell's
	-- CD, the deferred-broadcast block below will overwrite with the
	-- authoritative value 0.1s later.
	local guess = GetBaseCooldownSeconds(spellId)
	if not guess then return end
	RecordUsed("player", spellId, guess)
	NotifyDisplay("player")

	-- Defer the broadcast + final local-state commit until the engine has
	-- committed the post-cast CD (one tick + change is enough). This is
	-- the pattern BliZzi's interrupt tracker uses for the same reason —
	-- it lets us send the AUTHORITATIVE duration on the wire, so
	-- receivers don't need a CD-override mechanism on their end.
	C_Timer.After(0.1, function()
		local duration = ReadAuthoritativeCooldown(spellId) or guess
		RecordUsed("player", spellId, duration)
		NotifyDisplay("player")
		ns.Chat:Send("USED", spellId, duration)
		ScheduleReadyBroadcast(spellId, duration)
		if ns.Debug then ns.Debug:print("local-used", spellId, "dur=", duration) end
	end)
end

-- ============================================================
-- REMOTE FLOW: dispatch incoming messages by verb
-- ============================================================

-- Chat.lua delivers (sender, verb, args) where args is the parsed
-- semicolon-split tail of the wire format. INIT: args[1] is a CSV of
-- spell IDs. USED: args[1] is spellID, args[2] is the authoritative
-- post-cast duration (seconds) the sender computed. READY: args[1] is
-- spellID.
function Tracker:OnRemoteMessage(sender, verb, args)
	-- Skip echoes of our own outgoing addon messages; the local flow
	-- already recorded USEDs with accurate timing.
	if sender and UnitIsUnit(sender, "player") then return end

	local unit = ResolveSenderUnit(sender)
	if not unit then
		if ns.Debug then ns.Debug:print("remote", "unknown sender", sender) end
		return
	end

	if verb == "INIT" then
		self:OnRemoteInit(unit, args[1] or "")
		return
	end

	local spellId = tonumber(args[1])
	if not spellId then
		if ns.Debug then ns.Debug:print("remote", "bad spellId payload", verb, args[1]) end
		return
	end

	-- Guard: ignore USED/READY for spells the sender didn't advertise.
	-- Silently drops events from a buggy / old / incompatible client and
	-- keeps each unit's rendered icon set stable.
	local adv = advertised[unit]
	if adv and not adv[spellId] then
		if ns.Debug then ns.Debug:print("remote", "drop unadvertised", unit, spellId) end
		return
	end

	if verb == "USED" then
		-- Trust the sender's authoritative duration. Falls back to our
		-- local base-CD lookup if the sender's payload doesn't carry one
		-- (pre-v0.11 clients), or 60s last-resort if even that fails.
		local duration = tonumber(args[2])
		if not duration or duration < 2 then
			duration = GetBaseCooldownSeconds(spellId) or 60
		end
		RecordUsed(unit, spellId, duration)
	elseif verb == "READY" then
		RecordReady(unit, spellId)
	end

	NotifyDisplay(unit)
end

-- ============================================================
-- ROSTER MAINTENANCE
-- ============================================================

function Tracker:PruneRoster()
	local newGuid = {}
	for _, u in ipairs(IterateGroupUnits()) do
		newGuid[u] = UnitGUID(u)
	end

	-- Detect a slot whose GUID changed: same unit token, different
	-- player. Clear that unit's state so the new occupant starts fresh.
	for u, prev in pairs(unitGuid) do
		if newGuid[u] and newGuid[u] ~= prev then
			state[u] = nil
			advertised[u] = nil
			if ns.Debug then ns.Debug:print("roster", "slot", u, "changed player") end
		end
	end

	-- Drop state for units no longer in the group.
	for u in pairs(state) do
		if not newGuid[u] then state[u] = nil end
	end
	for u in pairs(advertised) do
		if not newGuid[u] then advertised[u] = nil end
	end

	unitGuid = newGuid
end

function Tracker:Reset()
	state = {}
	advertised = {}
	unitGuid = {}
	for _, t in pairs(pendingReadyTimers) do
		if t and t.Cancel then t:Cancel() end
	end
	pendingReadyTimers = {}
	wipe(baseCooldownByspell)
	if pendingInitTimer then pendingInitTimer:Cancel(); pendingInitTimer = nil end
	lastInitSent = 0
end

-- ============================================================
-- WIRING
-- ============================================================

function Tracker:Init()
	ns.Chat:SetReceiveHandler(function(sender, verb, payload)
		self:OnRemoteMessage(sender, verb, payload)
	end)

	local f = CreateFrame("Frame")
	f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	f:RegisterEvent("READY_CHECK")
	f:RegisterEvent("TRAIT_CONFIG_UPDATED")
	f:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
	f:SetScript("OnEvent", function(_, event, ...)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			local _, _, spellId = ...
			self:OnLocalCast(spellId)
		elseif event == "READY_CHECK" then
			-- On ready check, invalidate every remote advertised list
			-- so any stale data is cleared. Each client (us included)
			-- also broadcasts a fresh INIT; as those arrive, rows
			-- repopulate. The brief "blank then refill" is intentional
			-- — it signals the listing refreshed.
			for u in pairs(advertised) do advertised[u] = nil end
			NotifyDisplayAll()
			-- Send our INIT immediately (debounce bypassed inside).
			self:ScheduleInitBroadcast(0.1)
		elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
			-- Talent change: our advertised set may have shifted, so
			-- re-broadcast (debounced — these events can fire in bursts).
			-- Wipe the CD cache too; talents rarely move base CDs but a
			-- rebuild on next BuildLocalAdvertisedSet is cheap insurance.
			wipe(baseCooldownByspell)
			self:ScheduleInitBroadcast()
		end
	end)
end
