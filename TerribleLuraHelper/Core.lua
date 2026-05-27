local addonName, ns = ...

-- Core.lua — namespace, SavedVariables init, event dispatcher.
-- Phase 1: ADDON_LOADED initializes TerribleLuraHelperDB defaults and calls
-- ns:InitMacros (on PLAYER_LOGIN) / ns:InitWindow / ns:InitConfig.
-- See CLAUDE.md for hard taint constraints — this file MUST NOT register chat
-- events, index the msg argument from chat events, or emit chat messages. Those live elsewhere.

-- Per-channel defaults for fresh-install AND backfill (SCAF-13, SCAF-15, SAFE-06).
-- SAY=true is the v1.0.0 default; all other channels off until user opts in.
-- SAFE-06: backfill MUST use `if db.X == nil then db.X = DEFAULT end` — never
-- the `or` shorthand, which silently clobbers intentional `false` values.
-- See .planning/research/PITFALLS.md DB-1 for the full rationale.
local LISTEN_DEFAULTS = {
	SAY = true,
	RAID = false,
	RAID_LEADER = false,
	RAID_WARNING = false,
	INSTANCE_CHAT = false,
	INSTANCE_CHAT_LEADER = false,
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		-- Macro APIs (CreateMacro/EditMacro) are not reliable at
		-- ADDON_LOADED — the macro subsystem isn't fully initialized
		-- yet. PLAYER_LOGIN fires after it is, so macro registration
		-- runs here. Window/Config init can stay on ADDON_LOADED
		-- (frames + SavedVariables only).
		if ns.InitMacros then
			ns:InitMacros()
		end
		self:UnregisterEvent("PLAYER_LOGIN")
		return
	end

	if event == "ADDON_LOADED" then
		local name = ...
		if name ~= addonName then
			return
		end

		if not TerribleLuraHelperDB then
			TerribleLuraHelperDB = {
				listenChannels = {
					SAY = true,
					RAID = false,
					RAID_LEADER = false,
					RAID_WARNING = false,
					INSTANCE_CHAT = false,
					INSTANCE_CHAT_LEADER = false,
				},
				window = {
					scale = 1.00,
					locked = false,
					autoHide = false,
					position = nil,
					alpha = 1.00,
					visible = false,
				},
				macroChannel = "SAY",
				verboseMarkers = false,
			}
		end
		ns.db = TerribleLuraHelperDB

		-- Backfill missing keys for users upgrading from older versions.
		local db = ns.db
		if not db.listenChannels then
			db.listenChannels = {}
		end
		for ch, default in pairs(LISTEN_DEFAULTS) do
			if db.listenChannels[ch] == nil then
				db.listenChannels[ch] = default
			end
		end
		if not db.window then
			db.window = {}
		end
		if db.window.scale == nil then
			db.window.scale = 1.00
		end
		if db.window.locked == nil then
			db.window.locked = false
		end
		if db.window.autoHide == nil then
			db.window.autoHide = false
		end
		-- db.window.position is intentionally NOT backfilled.
		-- nil means "no saved position; use default anchor on first show".
		-- Phase 2 writes to it via OnDragStop; CENTER UIParent CENTER 200 80 is the default.
		if db.window.alpha == nil then
			db.window.alpha = 1.00
		end
		if db.window.visible == nil then
			db.window.visible = false
		end
		if db.macroChannel == nil then
			db.macroChannel = "SAY"
		end
		if db.verboseMarkers == nil then
			db.verboseMarkers = false
		end

		-- Dispatch to per-module init functions (Window + Config; macros
		-- run on PLAYER_LOGIN — see top of this handler).
		if ns.InitWindow then
			ns:InitWindow()
		end
		if ns.InitConfig then
			ns:InitConfig()
		end

		-- Restore visibility from last session. ns:RestoreWindowVisibility
		-- is like ns:ShowWindow but respects soft-hide (if autoHide is on
		-- and the sequence is empty, the window opens at alpha=0 — chat
		-- events register, ready to react, no flash).
		if db.window.visible and ns.RestoreWindowVisibility then
			ns:RestoreWindowVisibility()
		end

		print("|cffaa44ffTerribleLuraHelper|r loaded.")

		self:UnregisterEvent("ADDON_LOADED")
	end
end)

-- ============================================================
-- Phase 8 (WIN-16, WIN-17, SCAF-19, SAFE-07) — Zone-aware auto show/hide.
-- Permanent listener for PLAYER_ENTERING_WORLD + ZONE_CHANGED_NEW_AREA.
-- Re-evaluates on every fire (no state tracking — :Show/:Hide are
-- transition-only at the frame level, so redundant calls are free).
-- ============================================================

-- DEBUG_ZONE_INFO gates a single chat print inside ns:OnZoneChanged that
-- captures the live instanceID / mapID for the v1.1.0 UAT pass. Default
-- OFF; flipped true ONLY for the in-game UAT step that captures the M of Q
-- raid instanceID, then flipped back to false BEFORE the milestone release
-- tag. Must NEVER ship as true.
local DEBUG_ZONE_INFO = false

-- LURA_RAID_INSTANCE_ID is the GetInstanceInfo() instanceID (return
-- position 8) of the March on Quel'Danas raid where L'ura lives. Single
-- scalar is sufficient — instanceID is shared across all 5 raid
-- difficulties (LFR / Story / Normal / Heroic / Mythic); difficulty is a
-- separate axis (difficultyID, return position 3). See RESEARCH.md §Q3.
--
-- Captured via DEBUG_ZONE_INFO during v1.1.0 UAT on 2026-05-16: zoning into
-- LFR March on Quel'Danas produced `inst=2913 map=2534 type=raid`. mapID
-- (2534) tracks per sub-area and is not the right axis for difficulty-
-- agnostic auto-toggle; instanceID (2913) is shared across all 5 raid
-- difficulties and is what we compare against.
local LURA_RAID_INSTANCE_ID = 2913

-- WIN-16 / WIN-17 / SCAF-19 / SAFE-07. The handler is idempotent: it
-- queries world state via untainted Blizzard getters (IsInInstance,
-- GetInstanceInfo) and dispatches to the existing ns:ShowWindow /
-- ns:HideWindow primitives — the SAME code paths used by /lura show and
-- /lura hide. Routing through these primitives preserves the AMEND-01
-- chat-event registration invariant on the zone-leave side: ns:HideWindow
-- calls win:Hide() which fires OnHide which unregisters CHAT_MSG_* and
-- wipes the in-memory sequence. NEVER substitute SetAlpha(0) here —
-- would silently break the invariant. See CLAUDE.md hard constraints.
function ns:OnZoneChanged()
	local inInstance, instanceType = IsInInstance()
	if not inInstance or instanceType ~= "raid" then
		ns:HideWindow()
		return
	end
	local instanceID = select(8, GetInstanceInfo())
	if DEBUG_ZONE_INFO then
		local mapID = C_Map.GetBestMapForUnit("player") or "(nil)"
		print(
			string.format(
				"|cffaa44ffTLH-DEBUG|r zone: inst=%s map=%s type=%s",
				tostring(instanceID),
				tostring(mapID),
				instanceType
			)
		)
	end
	if instanceID == LURA_RAID_INSTANCE_ID then
		ns:ShowWindow()
	else
		ns:HideWindow()
	end
end

-- Permanent listener. Registered once at file scope, never unregisters.
-- Both events route to the same handler — OnZoneChanged is idempotent
-- and the negative case (IsInInstance == false) early-returns to
-- ns:HideWindow() within a couple of Lua ops, so the per-fire cost on
-- outdoor zone changes is negligible. PLAYER_ENTERING_WORLD covers the
-- loading-screen cases (initial login, /reload, raid entry/exit) and
-- ZONE_CHANGED_NEW_AREA covers walk-across-zone-border cases that don't
-- trigger a loading screen.
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneFrame:SetScript("OnEvent", function()
	ns:OnZoneChanged()
end)

-- ============================================================
-- State machine — window visibility IS the on/off switch.
-- Show = process chat, Hide = silent + slots wiped (handled by
-- the window's OnShow/OnHide scripts in Window.lua).
-- ============================================================

function ns:PrintHelp()
	print("|cffaa44ffTerribleLuraHelper|r commands:")
	-- Single source of truth (D-28): ns.SLASH_HELP is set by Config.lua's
	-- top-level chunk. Format: two-space indent, gold command, seven-space
	-- gap, plain description — matches UI-SPEC §Copywriting Contract.
	if ns.SLASH_HELP then
		for _, c in ipairs(ns.SLASH_HELP) do
			print(string.format("  |cffffd700%s|r       %s", c[1], c[2]))
		end
	else
		-- Defensive fallback — should never trigger because Config.lua's
		-- ns:InitConfig (called from ADDON_LOADED in this same file) sets
		-- ns.SLASH_HELP synchronously before any user can type a slash command.
		print("  (slash help not yet loaded — try again in a moment)")
	end
end

-- ============================================================
-- Slash command parser/dispatcher (8 commands per UI-SPEC §5.2).
-- /lura show       → ShowWindow (OnShow registers chat events)
-- /lura hide       → HideWindow (OnHide unregisters + wipes)
-- /lura lock       → LockWindow (sets db.window.locked=true)
-- /lura unlock     → UnlockWindow (sets db.window.locked=false)
-- /lura config     → Settings.OpenToCategory(ns.settingsCategoryID)
-- /lura help       → PrintHelp (consumes ns.SLASH_HELP)
-- /lura            → toggle window visibility
-- unrecognized     → print warning
-- /tlh             → full alias for /lura
-- ============================================================
function ns:HandleSlashCommand(rawArg)
	local cmd = (rawArg or ""):lower():match("^%s*(%S*)") or ""
	if cmd == "show" then
		ns:ShowWindow()
	elseif cmd == "hide" then
		ns:HideWindow()
	elseif cmd == "lock" then
		ns:LockWindow()
	elseif cmd == "unlock" then
		ns:UnlockWindow()
	elseif cmd == "help" then
		ns:PrintHelp()
	elseif cmd == "config" then
		-- Pass the numeric category ID, NEVER the name (footgun §6).
		if ns.settingsCategoryID then
			Settings.OpenToCategory(ns.settingsCategoryID)
		else
			-- Defensive: should never trigger (Config.lua's
			-- ContinueOnAddOnLoaded runs synchronously w/r/t ADDON_LOADED).
			print("|cffaa44ffTLH|r: settings not yet ready, try again in a moment.")
		end
	elseif cmd == "" then
		if ns:IsWindowShown() then
			ns:HideWindow()
		else
			ns:ShowWindow()
		end
	else
		print("|cffaa44ffTLH|r: unrecognized command. Try |cffffd700/lura help|r.")
	end
end

-- /lura primary, /tlh full alias. Both route to the same handler.
SLASH_LURA1 = "/lura"
SLASH_TLH1 = "/tlh"
SlashCmdList["LURA"] = function(arg)
	ns:HandleSlashCommand(arg)
end
SlashCmdList["TLH"] = function(arg)
	ns:HandleSlashCommand(arg)
end
