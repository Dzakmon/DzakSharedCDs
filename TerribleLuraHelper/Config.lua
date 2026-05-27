local addonName, ns = ...

-- Config.lua — Options > AddOns > TerribleLuraHelper panel via the modern
-- Settings.* API. Phase 3 ships four sections in vertical-layout order:
--   1. Chat channels — six listen-channel checkboxes (CFG-02, CFG-03)
--   2. Window        — scale slider, opacity slider, auto-hide checkbox,
--                      Lock/Unlock button (CFG-04, CFG-05, CFG-07, CFG-10,
--                      WIN-08, WIN-10)
--   3. Macros        — target-channel dropdown, recreate/update button
--                      (CFG-06, CFG-11)
--   4. Slash commands — eight help entries; canonical with ns:PrintHelp via
--                       the shared ns.SLASH_HELP table (CFG-08, CMD-05).
--
-- All Settings.* calls are deferred inside EventUtil.ContinueOnAddOnLoaded
-- (D-02 / SETTINGS_API.md footgun §5). Setting bindings use
-- Settings.RegisterAddOnSetting (NOT proxy) so the framework auto-writes
-- TerribleLuraHelperDB on every change — change callbacks here only call
-- Window.lua/Macros.lua exports to apply the new value live, never write
-- the DB themselves (D-04 / threat T-03-02).
--
-- See .planning/research/SETTINGS_API.md for verified code patterns and
-- .planning/phases/03-config-panel-integration/03-UI-SPEC.md for verbatim
-- copy contract (every label, tooltip, button text, notice string).

-- ============================================================
-- Channel toggle table (UI-SPEC §2.2)
-- DB key names match the existing schema: SAY / RAID / RAID_LEADER /
-- RAID_WARNING / INSTANCE_CHAT / INSTANCE_CHAT_LEADER (CONTEXT.md D-10/D-33).
-- ============================================================
local CHANNELS = {
	{ key = "SAY", label = "Listen on /say", tooltip = "Watch /say messages for raid markers." },
	{ key = "RAID", label = "Listen on /raid", tooltip = "Watch /raid messages for raid markers." },
	{
		key = "RAID_LEADER",
		label = "Listen on /raid (leader)",
		tooltip = "Watch raid-leader messages for raid markers.",
	},
	{ key = "RAID_WARNING", label = "Listen on /rw", tooltip = "Watch /rw raid-warning messages for raid markers." },
	{ key = "INSTANCE_CHAT", label = "Listen on /instance", tooltip = "Watch /instance messages for raid markers." },
	{
		key = "INSTANCE_CHAT_LEADER",
		label = "Listen on /instance (leader)",
		tooltip = "Watch instance-leader messages for raid markers.",
	},
}

-- ============================================================
-- Slash help block (UI-SPEC §5.2 — canonical for both this panel section
-- and ns:PrintHelp in Core.lua per CONTEXT.md D-28). Single source of
-- truth: changing one of the 8 entries here changes the chat-printed
-- help block too. Exposed on ns below.
-- ============================================================
local SLASH_HELP = {
	{ "/lura", "Toggles the helper window between shown and hidden." },
	{ "/lura show", "Shows the helper window and starts watching chat." },
	{ "/lura hide", "Hides the helper window, clears the runes, and stops watching chat." },
	{ "/lura lock", "Locks the helper window so it can't be dragged." },
	{ "/lura unlock", "Unlocks the helper window so you can drag it to a new position." },
	{ "/lura config", "Opens this settings panel." },
	{ "/lura help", "Prints the slash command list to chat." },
	{ "/tlh", "Alias for /lura — accepts every subcommand above." },
}
ns.SLASH_HELP = SLASH_HELP

-- ============================================================
-- 0. Reference image — rune symbol cheat-sheet at top of panel (CFG-12, SCAF-16,
-- SCAF-17). Anchors above all sections so new users see the rune→raid-marker
-- mapping before scrolling controls. Texture file is reference.tga at the addon
-- root, native 319x143 (non-POT per CONTEXT D-04 / D-07; if SCAF-17 in-game
-- testing reveals solid-green silent-failure mode per PITFALLS.md TX-3, fall
-- back to a 512x256-padded TGA + SetTexCoord letterbox per CONTEXT D-08).
-- Texture path is a hardcoded literal (D-02) — NOT a SavedVariables key, so the
-- function signature takes (category, layout) only, no db arg. Settings list
-- vertical-layout positions elements by AddInitializer call order (D-03), so
-- this gets called FIRST in ns:InitConfig below.
-- ============================================================
local function RegisterReferenceImage(_, layout)
	local data = { texturePath = "Interface\\AddOns\\TerribleLuraHelper\\reference.tga" }
	local initializer = Settings.CreateElementInitializer("TLHSymbolReferenceTemplate", data)
	layout:AddInitializer(initializer)
end

-- ============================================================
-- 1. Chat channels — 6 listen-channel checkboxes
-- ============================================================
local function RegisterChannelToggles(category, layout, db)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Chat channels"))
	if db.listenChannels == nil then
		db.listenChannels = {}
	end
	for _, ch in ipairs(CHANNELS) do
		local variable = "TLH_CHANNEL_" .. ch.key
		local setting = Settings.RegisterAddOnSetting(
			category,
			variable,
			ch.key,
			db.listenChannels,
			Settings.VarType.Boolean,
			ch.label,
			true
		)
		-- Per D-12: channel-toggle change is a no-op for chat-event registration.
		-- Filtering happens at message time in Window.lua via
		-- db.listenChannels[event:sub(10)] — the framework writes the new
		-- boolean and the next incoming message reads it. No reload required.
		Settings.CreateCheckbox(category, setting, ch.tooltip)
	end
end

-- ============================================================
-- 2. Window — scale slider + opacity slider + auto-hide checkbox + Lock/Unlock button
-- Per D-39, the Lock/Unlock button lives here (moved up from the retired
-- "Actions" section).
-- ============================================================
local function RegisterWindowControls(category, layout, db)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Window"))

	-- (2a) Scale slider — UI-SPEC §3.2
	do
		local setting = Settings.RegisterAddOnSetting(
			category,
			"TLH_WINDOW_SCALE",
			"scale",
			db.window,
			Settings.VarType.Number,
			"Window scale",
			1.00
		)
		setting:SetValueChangedCallback(function(_, value)
			ns:SetWindowScale(value)
		end)
		local options = Settings.CreateSliderOptions(0.50, 2.00, 0.05)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, FormatPercentage)
		Settings.CreateSlider(category, setting, options, "Resizes the helper window. Drag to preview live.")
	end

	-- (2b) Opacity slider — UI-SPEC §3.3
	do
		local setting = Settings.RegisterAddOnSetting(
			category,
			"TLH_WINDOW_ALPHA",
			"alpha",
			db.window,
			Settings.VarType.Number,
			"Window opacity",
			1.00
		)
		setting:SetValueChangedCallback(function(_, value)
			ns:SetWindowAlpha(value)
		end)
		local options = Settings.CreateSliderOptions(0.20, 1.00, 0.05)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, FormatPercentage)
		Settings.CreateSlider(
			category,
			setting,
			options,
			"Adjusts the helper window's transparency. Has no effect while auto-hide has hidden the window."
		)
	end

	-- (2c) Auto-hide checkbox — UI-SPEC §3.4
	do
		local setting = Settings.RegisterAddOnSetting(
			category,
			"TLH_AUTO_HIDE",
			"autoHide",
			db.window,
			Settings.VarType.Boolean,
			"Auto-hide",
			false
		)
		setting:SetValueChangedCallback(function(_, value)
			ns:OnAutoHideChanged(value)
		end)
		Settings.CreateCheckbox(
			category,
			setting,
			"When on, the helper window stays visible while you're out of combat so you remember the toggle is on. In combat, it hides while the rune sequence is empty and reappears automatically when the next marker arrives."
		)
	end

	-- (2d) Lock/Unlock button — UI-SPEC §4.3, moved here per D-39.
	-- buttonText closure re-evaluates db.window.locked. Live refresh on
	-- state change happens via the same hooksecurefunc-on-Init pattern as
	-- the Show/Hide button below — see ns:RefreshLockButton + sentinel.
	do
		local function OnClick()
			ns:ToggleLocked()
		end
		local function buttonText()
			if ns.db.window.locked then
				return "Unlock window"
			else
				return "Lock window"
			end
		end
		local initializer = CreateSettingsButtonInitializer(
			"Window",
			buttonText,
			OnClick,
			"Toggles whether the helper window can be dragged.",
			true
		)
		-- Post-v1.0.0-polish sentinel: ns:RefreshLockButton captures this
		-- specific button frame via hooksecurefunc(SettingsButtonControlMixin, "Init")
		-- and calls SetText directly when lock state changes, so the label
		-- flips live (mirror of the Show/Hide button's _tlhShowHideButton flag).
		initializer.data._tlhLockButton = true
		layout:AddInitializer(initializer)
	end

	-- (2e) Show/Hide window button. Mirrors the /lura no-arg toggle.
	-- Same EvaluateName Init-only caveat as the Lock button (label
	-- refreshes when the panel reopens, not on click). Left-side label
	-- omitted — keeps it visually paired with the Lock button above.
	do
		local function OnClick()
			if ns:IsWindowShown() then
				ns:HideWindow()
			else
				ns:ShowWindow()
			end
		end
		local function buttonText()
			if ns:IsWindowShown() then
				return "Hide window"
			else
				return "Show window"
			end
		end
		local initializer = CreateSettingsButtonInitializer(
			"",
			buttonText,
			OnClick,
			"Toggles the helper window between shown and hidden — same as typing /lura.",
			true
		)
		-- Phase 6 / CFG-13 sentinel: ns.RefreshShowHideButton uses this flag
		-- (via a hooksecurefunc on SettingsButtonControlMixin:Init) to
		-- identify which rendered button frame belongs to this initializer
		-- so it can call SetText directly without rebuilding the panel —
		-- avoids the scroll-position reset that DisplayCategory would cause.
		initializer.data._tlhShowHideButton = true
		layout:AddInitializer(initializer)
	end
end

-- Phase 6 / CFG-13: live label refresh for the Show/Hide window button.
--
-- The button uses CreateSettingsButtonInitializer with a buttonText closure;
-- the closure is evaluated only inside SettingsButtonControlMixin:Init() —
-- which fires when the rendered frame is bound to the initializer from the
-- pool. To refresh the label without rebuilding the panel (which resets
-- scroll position), we hook Init to capture the frame reference, then call
-- frame.Button:SetText(frame:EvaluateName()) from the notify hook.
--
-- The sentinel `data._tlhShowHideButton` distinguishes our button from any
-- other CreateSettingsButtonInitializer in the panel (e.g., the Lock/Unlock
-- button above) so we don't accidentally cache the wrong frame.
--
-- Why hooksecurefunc on a Blizzard mixin is safe here:
--   1. SettingsButtonControlMixin is a public Blizzard table loaded by
--      Blizzard_Settings_Shared (a default-loaded addon), so it is
--      guaranteed to exist when this file-scope code runs.
--   2. hooksecurefunc preserves Blizzard's taint state for the original
--      function and only appends our callback; it cannot modify return
--      values or break secure call chains.
--   3. The hook fires on EVERY button-control Init across the entire
--      Settings panel — we filter to our specific initializer via the
--      sentinel flag, so other addons' buttons are unaffected.
--
-- Lifecycle of cachedShowHideFrame:
--   - Initially nil — until the user opens the panel for the first time,
--     the frame doesn't exist (it's pulled from the pool on first display).
--   - Captured when Init fires on a sentinel-tagged initializer.
--   - The frame is pooled by Blizzard's ScrollBox — it may be re-bound to
--     a DIFFERENT initializer if the user scrolls far enough to release
--     the visible element. The IsVisible() guard in RefreshShowHideButton
--     short-circuits writes when the cached frame is no longer rendering
--     our button, so a stale pointer is harmless.
--   - Never explicitly cleared. Acceptable because (a) the IsVisible
--     guard is the actual safety net and (b) Blizzard's pool keeps frame
--     objects alive for the addon's lifetime anyway.
local cachedShowHideFrame
local cachedLockFrame
hooksecurefunc(SettingsButtonControlMixin, "Init", function(frame, initializer)
	local data = initializer and initializer.data
	if not data then
		return
	end
	if data._tlhShowHideButton then
		cachedShowHideFrame = frame
	elseif data._tlhLockButton then
		cachedLockFrame = frame
	end
end)

function ns:RefreshShowHideButton()
	if cachedShowHideFrame and cachedShowHideFrame:IsVisible() then
		cachedShowHideFrame.Button:SetText(cachedShowHideFrame:EvaluateName())
	end
end

function ns:RefreshLockButton()
	if cachedLockFrame and cachedLockFrame:IsVisible() then
		cachedLockFrame.Button:SetText(cachedLockFrame:EvaluateName())
	end
end

-- ============================================================
-- 3. Macros — target-channel dropdown + recreate/update button
-- ============================================================
local function RegisterMacroSection(category, layout, db)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Macros"))

	-- (3a) Macro target dropdown — UI-SPEC §4.5.2
	do
		local setting = Settings.RegisterAddOnSetting(
			category,
			"TLH_MACRO_CHANNEL",
			"macroChannel",
			db,
			Settings.VarType.String,
			"Macro target",
			"SAY"
		)
		setting:SetValueChangedCallback(function(_, value)
			ns:OnMacroChannelChanged(value)
		end)
		local function GenerateMacroChannelOptions()
			local container = Settings.CreateControlTextContainer()
			container:Add("RAID", "/raid")
			container:Add("RAID_WARNING", "/rw")
			container:Add("INSTANCE_CHAT", "/i")
			container:Add("SAY", "/s")
			return container:GetData()
		end
		Settings.CreateDropdown(
			category,
			setting,
			GenerateMacroChannelOptions,
			"The chat channel each TLH_* macro sends raid markers to. /s is the default and works anywhere (great for pugs and casual groups); /raid works during raid encounters (raid-only); /rw requires raid leader/assist; /i sends to instance/dungeon chat."
		)
	end

	-- (3aa) Verbose-marker toggle — UI-SPEC follow-on / CFG-15.
	-- Inserted between (3a) channel dropdown and (3b) Recreate button.
	-- Same Macros section, same Settings.* API as the dropdown above,
	-- but Boolean+Checkbox instead of String+Dropdown. Bound to top-
	-- level db.verboseMarkers (NOT db.window or db.macros — see D-07).
	-- Framework auto-writes db.verboseMarkers BEFORE firing the
	-- SetValueChangedCallback (Phase 3 / T-03-02 invariant); callback
	-- only calls ns:OnVerboseMarkersChanged(value) to apply the new
	-- value live. No sentinel-flag hook needed — checkbox auto-syncs
	-- via SettingsCheckboxControlMixin:OnSettingValueChanged (RESEARCH Q4).
	do
		local setting = Settings.RegisterAddOnSetting(
			category,
			"TLH_VERBOSE_MARKERS",
			"verboseMarkers",
			db,
			Settings.VarType.Boolean,
			"Use verbose markers",
			false
		)
		setting:SetValueChangedCallback(function(_, value)
			ns:OnVerboseMarkersChanged(value)
		end)
		Settings.CreateCheckbox(
			category,
			setting,
			"Switches the four marker macros from {rt2} / {rt3} / {rt4} / {rt7} to {circle} / {diamond} / {triangle} / {cross}. WARNING: verbose names only render on English WoW clients — if anyone in your raid runs a non-English client, leave this OFF. The default {rt#} markers are universal across all locales. The 5th macro (TLH_T) sends the letter T either way."
		)
	end

	-- (3b) Recreate / update macros button — UI-SPEC §4.2 / §4.5.3.
	-- Always print success regardless of the macrosPrintedThisSession flag —
	-- explicit user action should always confirm (UI-SPEC §4.2 rationale).
	do
		local function OnClick()
			if InCombatLockdown() then
				print(
					"|cffaa44ffTLH|r: Can't recreate macros during combat. They will be retried on PLAYER_REGEN_ENABLED, or click again after combat."
				)
				return
			end
			ns:RegisterMacros()
			print("|cffaa44ffTLH|r: Macros recreated.")
		end
		local initializer = CreateSettingsButtonInitializer(
			"Macros",
			"Recreate",
			OnClick,
			"Recreates or updates the five TLH_* player macros if you've deleted or edited them. The macro target dropdown above already updates them on change — this button is only needed if a macro went missing. Disabled during combat — the addon retries automatically when combat ends.",
			true
		)
		layout:AddInitializer(initializer)
	end

	-- (3c) Delete macros button. Removes all five TLH_* macros. The
	-- addon recreates them automatically on next login while it's
	-- enabled, so this is mainly useful before disabling/uninstalling
	-- or to free macro slots temporarily.
	do
		local function OnClick()
			if InCombatLockdown() then
				print("|cffaa44ffTLH|r: Can't delete macros during combat. Click again after combat ends.")
				return
			end
			local deleted = ns:DeleteMacros()
			if deleted and deleted > 0 then
				print(string.format("|cffaa44ffTLH|r: Deleted %d TLH_* macro(s).", deleted))
			else
				print("|cffaa44ffTLH|r: No TLH_* macros to delete.")
			end
		end
		local initializer = CreateSettingsButtonInitializer(
			"",
			"Delete",
			OnClick,
			"Removes the five TLH_* player macros. They'll be recreated automatically on your next login while the addon is enabled.",
			true
		)
		layout:AddInitializer(initializer)
	end
end

-- ============================================================
-- 4. Slash commands — 8 help entries (single-source-of-truth via
--    SLASH_HELP; ns:PrintHelp in Core.lua iterates the same table).
-- ============================================================
local function RegisterCommandHelp(_, layout)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Slash commands"))
	for _, c in ipairs(SLASH_HELP) do
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(c[1], c[2]))
	end
end

-- ============================================================
-- Top-level registration — deferred via EventUtil.ContinueOnAddOnLoaded
-- per D-02. Phase 1's Core.lua dispatcher already calls this from
-- ADDON_LOADED; the EventUtil gate is cheap insurance against future
-- call-order regressions and matches the documented Blizzard pattern.
-- Caches ns.settingsCategoryID for /lura config (must be a number per
-- footgun §6 — never pass the category name).
-- ============================================================
function ns:InitConfig()
	EventUtil.ContinueOnAddOnLoaded(addonName, function()
		local db = ns.db
		if not db then
			return -- defensive: should never trigger because ADDON_LOADED ran first
		end

		local category, layout = Settings.RegisterVerticalLayoutCategory("TerribleLuraHelper")
		ns.settingsCategoryID = category:GetID()

		RegisterReferenceImage(category, layout)
		RegisterChannelToggles(category, layout, db)
		RegisterWindowControls(category, layout, db)
		RegisterMacroSection(category, layout, db)
		RegisterCommandHelp(category, layout)

		Settings.RegisterAddOnCategory(category)
	end)
end
