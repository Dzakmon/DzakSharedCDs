local _, ns = ...

-- Macros.lua — TLH_* macro registration with combat-lockdown deferral.
-- Five named player macros using Blizzard built-in raid-marker FileDataIDs
-- (TLH_T sends the literal letter "T" instead of {rt1}); idempotent on
-- every login; guarded by InCombatLockdown() with a PLAYER_REGEN_ENABLED
-- retry path via the shared regenFrame (SAFE-03 / MACR-03). Macro body is
-- built dynamically from db.macroChannel at registration time so the
-- config-panel dropdown change rebuilds in place. Printed-once "drag to
-- action bar" hint is a Lua local — once per session, not persisted.

-- Raid marker FileDataIDs (Blizzard built-ins, no addon dependency).
-- TLH_T sends the literal letter "T" — that's the L'ura marker the rune
-- represents in-fight; star icon is kept on the macro for action-bar
-- recognizability. Slot 5 (or wherever T lands in arrival order) renders
-- the letter T directly via FontString:SetText.
-- Phase 7 / MACR-06, MACR-07. The four marker rows have BOTH payloadVerbose
-- and payloadRT; RegisterMacros picks one via db.verboseMarkers. TLH_T uses
-- a single `payload` field — its rune is the literal letter T (the 5th
-- L'ura rune), not a marker icon, so no verbose variant exists. The
-- single-vs-dual-field shape per row self-documents this irregularity.
local MACROS = {
	{ name = "TLH_Diamond", payloadVerbose = "{diamond}", payloadRT = "{rt3}", icon = 137003 },
	{ name = "TLH_Triangle", payloadVerbose = "{triangle}", payloadRT = "{rt4}", icon = 137004 },
	{ name = "TLH_Circle", payloadVerbose = "{circle}", payloadRT = "{rt2}", icon = 137002 },
	{ name = "TLH_Cross", payloadVerbose = "{cross}", payloadRT = "{rt7}", icon = 137007 },
	{ name = "TLH_T", payload = "T", icon = 137001 },
}

-- Per D-38: macro body is built dynamically from db.macroChannel at
-- registration time. CHANNEL_PREFIX lookup is constant-string concatenation
-- by addon code — NOT touching `msg` from any chat event. Hard taint
-- constraints (CLAUDE.md) are unaffected.
local CHANNEL_PREFIX = {
	RAID = "/raid",
	RAID_WARNING = "/rw",
	INSTANCE_CHAT = "/i",
	SAY = "/s",
}

-- Once-per-session flag for the "drag macros to your action bar" hint.
local macrosPrintedThisSession = false
-- Set by RegisterMacros when combat blocks the attempt. The shared
-- regenFrame below consumes this on PLAYER_REGEN_ENABLED to retry.
local registrationDeferred = false

-- Re-runnable entry point. Returns true on a successful run (out of
-- combat), false if combat blocked the attempt. Phase 3's "Recreate
-- Macros" button (MACR-04) calls this directly.
function ns:RegisterMacros()
	if InCombatLockdown() then
		registrationDeferred = true
		return false
	end
	-- Per D-38: derive prefix once per registration call from db.macroChannel.
	-- Unknown values fall through to "/raid" — graceful default for any
	-- corrupted SavedVar (covered by threat T-03-10).
	local prefix = CHANNEL_PREFIX[ns.db.macroChannel] or "/raid"
	local created, updated = 0, 0
	for _, m in ipairs(MACROS) do
		local payload = m.payload or (ns.db.verboseMarkers and m.payloadVerbose or m.payloadRT)
		local body = prefix .. " " .. payload
		local idx = GetMacroIndexByName(m.name)
		if idx == 0 then
			if CreateMacro(m.name, m.icon, body, false) then
				created = created + 1
			end
		else
			EditMacro(idx, m.name, m.icon, body)
			updated = updated + 1
		end
	end
	if not macrosPrintedThisSession and (created > 0 or updated > 0) then
		print(
			string.format(
				"|cffaa44ffTLH|r macros: %d created, %d updated. " .. "Open /macro and drag them to your action bar.",
				created,
				updated
			)
		)
		macrosPrintedThisSession = true
	end
	registrationDeferred = false
	return true
end

-- Single shared retry frame. Reused by every code path that needs a
-- "deferred until combat ends" hook (initial load + every dropdown change).
-- Calling armRegenRetry repeatedly is idempotent — RegisterEvent on the
-- same event is a no-op when already registered. The handler always
-- unregisters after firing so the frame stays cold between deferrals.
local regenFrame = CreateFrame("Frame")
regenFrame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if registrationDeferred then
			ns:RegisterMacros()
		end
	end
end)

local function armRegenRetry()
	regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Called by Core.lua's ADDON_LOADED dispatcher (Phase 1 already wires
-- this). First attempt at registration; if combat blocks, the shared
-- regen frame retries.
function ns:InitMacros()
	if not ns:RegisterMacros() then
		armRegenRetry()
	end
end

-- Removes the five TLH_* macros. Combat-blocked (returns nil); caller
-- handles the user-facing notice. Returns the count of macros actually
-- found-and-deleted on success (0 if none existed).
function ns:DeleteMacros()
	if InCombatLockdown() then
		return nil
	end
	local deleted = 0
	for _, m in ipairs(MACROS) do
		if GetMacroIndexByName(m.name) > 0 then
			DeleteMacro(m.name)
			deleted = deleted + 1
		end
	end
	-- Clear the once-per-session hint flag so the next RegisterMacros
	-- (auto on login or via the Recreate button) prints the drag-to-bar
	-- reminder again.
	macrosPrintedThisSession = false
	return deleted
end

-- Phase 3 / CFG-11. The dropdown's SetValueChangedCallback fires this after
-- the framework has already written db.macroChannel = value. We just re-run
-- RegisterMacros, which re-reads db.macroChannel via the CHANNEL_PREFIX
-- lookup. Combat-lockdown deferral routes through the shared regen frame.
function ns:OnMacroChannelChanged(value)
	local prefix = CHANNEL_PREFIX[value] or "/raid"
	if InCombatLockdown() then
		ns:RegisterMacros() -- sets registrationDeferred=true via the early-return
		armRegenRetry()
		print("|cffaa44ffTLH|r: Macro target → " .. prefix .. ". Macros will update when you leave combat.")
	else
		ns:RegisterMacros()
		print("|cffaa44ffTLH|r: Macro target → " .. prefix .. ". Macros updated.")
	end
end

-- Phase 7 / CFG-16. The checkbox's SetValueChangedCallback fires this after
-- the framework has already written db.verboseMarkers = value (Phase 3 /
-- T-03-02 invariant). We just re-run RegisterMacros, which re-reads
-- db.verboseMarkers via the payload-selection conditional in the for-loop.
-- Combat-lockdown deferral routes through the shared regenFrame.
function ns:OnVerboseMarkersChanged(value)
	if InCombatLockdown() then
		ns:RegisterMacros() -- sets registrationDeferred=true via the early-return
		armRegenRetry()
		print(
			string.format(
				"|cffaa44ffTLH|r: Verbose markers %s. Macros will update when you leave combat.",
				value and "on" or "off"
			)
		)
	else
		ns:RegisterMacros()
		print(string.format("|cffaa44ffTLH|r: Verbose markers %s. Macros updated.", value and "on" or "off"))
	end
end
