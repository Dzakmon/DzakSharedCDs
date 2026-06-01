local addonName, ns = ...

-- ============================================================
-- DB SEEDING
-- Per-spec storage. A spec's tracked-set is seeded from
-- ns.DEFAULT_SPELLS_BY_SPEC the first time the spec is observed
-- (locally or via LibSpecialization). After that, edits stick:
-- explicitly clearing all spells for a spec will NOT re-seed.
-- ============================================================

-- Defaults for the global display block. Single source of truth: both
-- the seeder below and Settings.lua's "Reset to defaults" path read it.
--
-- v0.11.0 split the old `growDirection` (which mixed "which frame edge
-- to attach to" with "which way icons grow"). The two are now
-- independent:
--   anchorSide     — which edge of the party frame the row attaches to
--   growDirection  — absolute direction the icons fan out from there
-- So e.g. anchorSide=RIGHT + growDirection=RIGHT puts icons OUTSIDE
-- the frame, growing rightward away from it.
ns.DEFAULT_DISPLAY = {
	iconSize       = 24,
	iconGap        = 2,
	anchorSide     = "RIGHT", -- "LEFT" or "RIGHT" — which edge of the party frame
	growDirection  = "RIGHT", -- "LEFT" or "RIGHT" — which way icons fan out
	offsetX        = 6,
	offsetY        = 0,
	-- BliZzi-style icon polish.
	borderSize     = 1,       -- 0 disables the outward border
	borderColorR   = 0,
	borderColorG   = 0,
	borderColorB   = 0,
	borderColorA   = 1,
	cdGrayout      = true,    -- desaturate icon while on cooldown
	cdShowMinutes  = true,    -- "5m" instead of "300" when rem >= 60
	cdTextFontSize = 14,
}

local function SeedSchema()
	DzakSharedCDsDB = DzakSharedCDsDB or {}
	if DzakSharedCDsDB.enabled == nil then DzakSharedCDsDB.enabled = true end

	-- v0.1.0 stored a flat trackedSpells set. Drop it; v0.2.0 storage
	-- is per-spec and the migration target (the user's old spec) is
	-- unknowable without ambiguity.
	DzakSharedCDsDB.trackedSpells = nil

	DzakSharedCDsDB.trackedSpellsBySpec = DzakSharedCDsDB.trackedSpellsBySpec or {}

	DzakSharedCDsDB.display = DzakSharedCDsDB.display or {}

	-- v0.11.0: split growDirection into anchorSide + growDirection. Migrate
	-- old saves so existing visual stays the same. Old growDirection had two
	-- valid values; each picks the matching {anchorSide, new growDirection}
	-- pair that produces the same visual (icons growing INTO the frame from
	-- the anchored edge):
	--   old "LEFT"  → row anchored to frame's LEFT, icons grow RIGHT
	--   old "RIGHT" → row anchored to frame's RIGHT, icons grow LEFT
	if DzakSharedCDsDB.display.anchorSide == nil and DzakSharedCDsDB.display.growDirection then
		local oldGrow = DzakSharedCDsDB.display.growDirection
		DzakSharedCDsDB.display.anchorSide = oldGrow
		DzakSharedCDsDB.display.growDirection = (oldGrow == "LEFT") and "RIGHT" or "LEFT"
	end

	-- Per-key backfill so new defaults land in existing saves without
	-- clobbering user-tuned values. Using `if nil then` (not `or`) so an
	-- intentional zero or false isn't overwritten.
	for k, v in pairs(ns.DEFAULT_DISPLAY) do
		if DzakSharedCDsDB.display[k] == nil then
			DzakSharedCDsDB.display[k] = v
		end
	end

	-- v0.11.0: cooldownOverrides removed. The sender now broadcasts the
	-- authoritative post-cast CD as part of USED, so receivers don't
	-- need per-spell overrides. Drop the key if present.
	DzakSharedCDsDB.cooldownOverrides = nil
end
SeedSchema()

function ns.EnsureSpecSeeded(specId)
	if not specId then return end
	if DzakSharedCDsDB.trackedSpellsBySpec[specId] then return end
	local defaults = ns.DEFAULT_SPELLS_BY_SPEC[specId]
	local t = {}
	if defaults then
		for id in pairs(defaults) do t[id] = true end
	end
	DzakSharedCDsDB.trackedSpellsBySpec[specId] = t
	if ns.Debug then ns.Debug:print("seed", "spec", specId, "with", t and (function() local n=0; for _ in pairs(t) do n=n+1 end; return n end)() or 0, "spells") end
end

function ns.GetTrackedForSpec(specId)
	if not specId then return nil end
	return DzakSharedCDsDB.trackedSpellsBySpec[specId]
end

-- ============================================================
-- PUBLIC HELPERS (consumed by Settings.lua and other modules)
-- ============================================================

function ns.IsEnabled()
	return DzakSharedCDsDB.enabled ~= false
end

function ns.SetEnabled(value)
	DzakSharedCDsDB.enabled = value and true or false
	ns.Debug:print("settings", "enabled=", DzakSharedCDsDB.enabled)
	if ns.Display then ns.Display:UpdateAll() end
end

function ns.ResetSpecToDefaults(specId)
	if not specId then return end
	local defaults = ns.DEFAULT_SPELLS_BY_SPEC[specId]
	local t = {}
	if defaults then
		for id in pairs(defaults) do t[id] = true end
	end
	DzakSharedCDsDB.trackedSpellsBySpec[specId] = t
	ns.Debug:print("settings", "reset spec", specId)
	if ns.Display then ns.Display:UpdateAll() end
end

function ns.AddTracked(specId, spellId)
	if not specId then return end
	ns.EnsureSpecSeeded(specId)
	DzakSharedCDsDB.trackedSpellsBySpec[specId][spellId] = true
	ns.Debug:print("settings", "added", spellId, "to spec", specId)
	if ns.Display then ns.Display:UpdateAll() end
end

function ns.RemoveTracked(specId, spellId)
	if not specId then return end
	local t = DzakSharedCDsDB.trackedSpellsBySpec[specId]
	if not t then return end
	t[spellId] = nil
	ns.Debug:print("settings", "removed", spellId, "from spec", specId)
	if ns.Display then ns.Display:UpdateAll() end
end

-- Display settings: thin getters/setters with a re-render on write.
-- All callers read live values from the DB, so a slider's OnValueChanged
-- handler just calls SetDisplaySetting and trusts UpdateAll to repaint.
function ns.GetDisplaySetting(key)
	local v = DzakSharedCDsDB.display and DzakSharedCDsDB.display[key]
	if v == nil then return ns.DEFAULT_DISPLAY[key] end
	return v
end

function ns.SetDisplaySetting(key, value)
	DzakSharedCDsDB.display = DzakSharedCDsDB.display or {}
	DzakSharedCDsDB.display[key] = value
	if ns.Display then ns.Display:UpdateAll() end
end

function ns.ResetDisplayDefaults()
	DzakSharedCDsDB.display = {}
	for k, v in pairs(ns.DEFAULT_DISPLAY) do
		DzakSharedCDsDB.display[k] = v
	end
	if ns.Display then ns.Display:UpdateAll() end
end

-- ============================================================
-- EVENT HOOKUP
-- ============================================================

local booted = false

local function OnSpecChange(playerShortName, specId)
	-- Spec became known for someone (could be us or a party member).
	-- Seed their spec's default list and trigger a display refresh.
	ns.EnsureSpecSeeded(specId)
	if ns.Display then ns.Display:UpdateAll() end
	-- Critical: re-broadcast our INIT. The PLAYER_ENTERING_WORLD
	-- triggered INIT may have fired BEFORE our own spec was known
	-- (LibSpecialization's callback for us doesn't always land in
	-- time), in which case BuildLocalAdvertisedSet returned nil and
	-- no INIT went out. Re-scheduling here covers both the "our spec
	-- finally landed" and "a party member's spec landed, send so they
	-- catch up" cases. The 2.5s debounce coalesces bursts.
	if ns.Tracker then ns.Tracker:ScheduleInitBroadcast() end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		if not booted then
			booted = true
			ns.SpecCache:Init()
			ns.SpecCache:SetChangeHandler(OnSpecChange)
			ns.Tracker:Init()
			ns.Display:StartTicker()
			ns.Debug:print("boot", "ready")
		end
		-- Seed our current spec on first sight so the default icons show
		-- up even before LibSpecialization's callback lands.
		local mySpec = ns.SpecCache:GetLocalSpec()
		if mySpec then ns.EnsureSpecSeeded(mySpec) end
		ns.Tracker:PruneRoster()
		ns.Display:UpdateAll()
		-- Initial INIT broadcast on login/reload. Debounced so back-to-
		-- back PLAYER_ENTERING_WORLDs (zone changes) don't spam.
		ns.Tracker:ScheduleInitBroadcast()
	elseif event == "GROUP_ROSTER_UPDATE" then
		ns.Tracker:PruneRoster()
		ns.Display:UpdateAll()
		-- A newcomer needs our INIT, and we may want theirs. Debounced.
		ns.Tracker:ScheduleInitBroadcast()
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		local mySpec = ns.SpecCache:GetLocalSpec()
		if mySpec then ns.EnsureSpecSeeded(mySpec) end
		if ns.Display then ns.Display:UpdateAll() end
		ns.Tracker:ScheduleInitBroadcast()
	end
end)

-- ============================================================
-- SLASH COMMAND
-- ============================================================

SLASH_DSCD1 = "/dscd"
SlashCmdList["DSCD"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if msg == "" then
		if ns.OpenSettings then
			ns.OpenSettings()
		else
			print("|cffff5555DzakSharedCDs:|r settings panel not loaded")
		end
	elseif msg == "status" then
		print("|cff00ff00DzakSharedCDs:|r status")
		print("  enabled: " .. tostring(ns.IsEnabled()))
		local mySpec = ns.SpecCache:GetLocalSpec()
		print("  local spec: " .. (mySpec and ns.FormatSpecLabel(mySpec) or "?"))
		local specCount = 0
		for _ in pairs(DzakSharedCDsDB.trackedSpellsBySpec) do specCount = specCount + 1 end
		print("  specs configured: " .. specCount)
		print("  in group: " .. tostring(IsInGroup()))
		print("  in instance: " .. tostring(IsInInstance()))
	elseif msg == "init" then
		-- Print what our next INIT broadcast would announce. Useful for
		-- verifying which talented-AND-tracked spells the addon thinks
		-- you have.
		local set = ns.Tracker:BuildLocalAdvertisedSet()
		if not set then
			print("|cffff5555DzakSharedCDs:|r no spec detected yet")
			return
		end
		local ids = {}
		for id in pairs(set) do ids[#ids + 1] = id end
		table.sort(ids)
		print(string.format("|cff00ff00DzakSharedCDs:|r INIT would advertise %d spells:", #ids))
		for _, id in ipairs(ids) do
			local info = C_Spell.GetSpellInfo(id)
			print(string.format("  |cffffff00%d|r  %s", id, info and info.name or "(unknown)"))
		end
	elseif msg == "broadcast" then
		ns.Tracker:ScheduleInitBroadcast(0.1)
		print("|cff00ff00DzakSharedCDs:|r INIT scheduled")
	elseif msg == "ping" then
		-- Delivery parity test. Sends a PING and prints whether it left
		-- the wire; receivers print a visible chat line when it arrives.
		-- Bypasses Tracker / spec / talent logic so a failure is purely
		-- a transport issue.
		ns.Chat:SendPing()
	else
		print("|cff00ff00DzakSharedCDs:|r commands:")
		print("  /dscd            - open settings panel")
		print("  /dscd status     - print state summary")
		print("  /dscd init       - print what your next INIT would advertise")
		print("  /dscd broadcast  - force an INIT broadcast now")
		print("  /dscd ping       - send a delivery test (visible to recipients)")
		print("  /dscddebug       - toggle debug tracing")
	end
end
