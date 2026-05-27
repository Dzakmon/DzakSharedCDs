local _, ns = ...

-- Window.lua — smile-arc helper window: 5 positional rune slots, BOSS/TANK labels,
-- lock/unlock, drag-position persistence, 20s self-clear, in-memory sequence.
-- Slot text MUST be set directly from
-- C_ChatInfo.ReplaceIconAndGroupExpressions(msg, nil, false) — never index msg in Lua.
--
-- Gating: window visibility IS the on/off switch. OnShow registers chat
-- events; OnHide unregisters and wipes slots. No combat gating — works
-- whenever the window is open.
--
-- Phase 2 deviations from the POC are documented inline (D-17 backdrop drop,
-- D-27 in-memory sequence, D-28 20s timeout, D-30..D-31 channel filter).

-- ============================================================
-- Constants (D-28, D-29: hardcoded for v1, named for future v2 promotion)
-- ============================================================
local INACTIVITY_TIMEOUT = 20

local W, H = 380, 235
local SLOT_SIZE = 64
local ICON_SIZE = SLOT_SIZE - 8

-- Smile-arc geometry. Offsets are CENTER-relative to bossLabel.
-- Adjacent slot centers are ≥85px apart so 64px slots don't overlap.
local SLOT_POS = {
	[1] = { 140, 55 },
	[2] = { 90, -20 },
	[3] = { 0, -65 },
	[4] = { -90, -20 },
	[5] = { -140, 55 },
}

local CHAT_EVENTS = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
}

-- ============================================================
-- State (in-memory only per D-27 — NOT in TerribleLuraHelperDB)
-- ============================================================
local sequence = {}
local clearTimer
local positionApplied = false -- saved position is applied on first show only
-- Phase 3 / D-18..D-22: soft-hide state. true while autoHide=on AND #sequence==0.
-- Window stays visible (no Hide()) but with alpha=0; chat events stay registered
-- so the next slot fill can reveal it via applySoftHideState().
local softHidden = false
-- Phase 5 / D-01..D-03: combat-state cache. Read by applySoftHideState
-- (third condition clause). Seeded at frame creation via combat-query API
-- and updated on every regen-event edge by combatFrame below.
local inCombat = false

-- Forward declarations so handlers below can call helpers above.
local win, slotFrames, lockBtn
local FillSlot, ClearAll, ScheduleClear, ManualClear
local applyLockState, applySavedPosition, persistPosition, applySoftHideState
local registerChatEvents, unregisterChatEvents

-- ============================================================
-- Frame construction (called from ns:InitWindow)
-- ============================================================
local function CreateWindow()
	-- Plain frame with a solid black backdrop, no border. BackdropTemplate
	-- gives us SetBackdrop/SetBackdropColor; no edgeFile = no border.
	win = CreateFrame("Frame", "TerribleLuraHelperWindow", UIParent, "BackdropTemplate")
	win:SetSize(W, H)
	win:EnableMouse(true)
	win:SetClampedToScreen(true)
	win:Hide() -- hidden by default on every login/reload

	-- Deep midnight-blue backdrop — matches the L'ura encounter's
	-- void/starlight aesthetic. No edgeFile keeps it borderless.
	win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	win:SetBackdropColor(0.05, 0.07, 0.18, 1)

	-- Initial anchor — overridden by applySavedPosition on first show.
	win:SetPoint("CENTER", UIParent, "CENTER", 200, 80)

	-- Apply scale and alpha at creation (alpha live-update lands in Phase 3).
	win:SetScale(ns.db.window.scale or 1.00)
	win:SetAlpha(ns.db.window.alpha or 1.00)

	-- No close button or title bar — /lura toggles visibility.

	-- Lock toggle: text "Lock" in the bottom-right corner. Hidden when
	-- the window is locked (clean look once positioned). To unlock,
	-- the user uses the config panel toggle (Phase 3).
	lockBtn = CreateFrame("Button", nil, win)
	lockBtn:SetSize(40, 18)
	lockBtn:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 6)
	local lockText = lockBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lockText:SetPoint("CENTER")
	lockText:SetText("Lock")
	lockBtn:SetFontString(lockText)
	lockBtn:SetScript("OnEnter", function()
		lockText:SetTextColor(1, 1, 1)
	end)
	lockBtn:SetScript("OnLeave", function()
		lockText:SetTextColor(1.0, 0.82, 0.0)
	end)
	lockBtn:SetScript("OnClick", function()
		ns:ToggleLocked()
	end)

	-- ============================================================
	-- Boss view + smile-arc slots (port verbatim from POC lines 121-178; D-18)
	-- ============================================================
	local bossView = CreateFrame("Frame", nil, win)
	bossView:SetSize(W - 20, 210)
	bossView:SetPoint("TOP", win, "TOP", 0, -10)

	local bossLabel = bossView:CreateFontString(nil, "OVERLAY")
	bossLabel:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
	bossLabel:SetPoint("CENTER", bossView, "CENTER", 0, 0)
	bossLabel:SetText("BOSS")

	local tankLabel = bossView:CreateFontString(nil, "OVERLAY")
	tankLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	tankLabel:SetPoint("CENTER", bossLabel, "CENTER", 0, 70)
	tankLabel:SetText("TANK")

	slotFrames = {}
	for i = 1, 5 do
		local slot = CreateFrame("Frame", nil, bossView, "BackdropTemplate")
		slot:SetSize(SLOT_SIZE, SLOT_SIZE)
		slot:SetPoint("CENTER", bossLabel, "CENTER", SLOT_POS[i][1], SLOT_POS[i][2])
		slot:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		slot:SetBackdropColor(0.10, 0.10, 0.13, 0.7)
		slot:SetBackdropBorderColor(0.65, 0.62, 0.55, 0.6)

		local fs = slot:CreateFontString(nil, "OVERLAY")
		fs:SetFont("Fonts\\FRIZQT__.TTF", ICON_SIZE, "OUTLINE")
		fs:SetPoint("CENTER")
		fs:SetText("")
		slot.fs = fs

		local idx = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		idx:SetPoint("TOP", slot, "BOTTOM", 0, -2)
		idx:SetText(tostring(i))
		idx:SetTextColor(0.65, 0.65, 0.7, 0.85)

		slotFrames[i] = slot
	end

	-- ============================================================
	-- Drag handlers — bound regardless of locked state; SetMovable
	-- is the actual gate (D-15, UI-SPEC §3.2).
	-- ============================================================
	win:SetScript("OnDragStart", function(self)
		if self:IsMovable() then
			self:StartMoving()
		end
	end)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		persistPosition()
	end)

	-- Visibility-driven event gating: open window = process chat,
	-- closed window = silent. Replaces the combat-only registration model.
	win:SetScript("OnShow", function()
		registerChatEvents()
	end)
	win:SetScript("OnHide", function()
		unregisterChatEvents()
		ManualClear()
	end)

	-- Apply current locked/unlocked state to drag bindings + button texture.
	applyLockState()

	-- ============================================================
	-- Combat-state listener (Phase 5 / D-02, D-03; WIN-13, WIN-14, WIN-15)
	-- Seeds inCombat at frame-creation time (handles /reload mid-combat where
	-- the regen-disabled event never fires for an already-in-combat player).
	-- Then registers a PERMANENT listener on both regen edges — the frame
	-- never unregisters, unlike Macros.lua's regenFrame (lines 86-98) which
	-- is a fire-once retry pattern. Both edges flip the cached flag and
	-- re-evaluate applySoftHideState so the soft-hide reframe responds
	-- immediately to combat boundaries.
	-- ============================================================
	inCombat = InCombatLockdown()
	-- `local combatFrame` is intentionally discarded after registration —
	-- the C-level frame and its event registrations survive past this scope
	-- (CreateFrame returns a Lua handle to a persistent C frame; the GC
	-- cannot collect it once events are bound). The handle is only needed
	-- here to call :RegisterEvent / :SetScript.
	local combatFrame = CreateFrame("Frame")
	combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatFrame:SetScript("OnEvent", function(_, event)
		inCombat = (event == "PLAYER_REGEN_DISABLED")
		applySoftHideState()
	end)
end

-- ============================================================
-- Slot helpers (port verbatim from POC FillSlot/ClearAll)
-- ============================================================
FillSlot = function(i, msg)
	local slot = slotFrames[i]
	if not slot then
		return
	end
	-- Pass msg opaquely. SetText is C-level and does not index msg.
	slot.fs:SetText(msg)
	slot:SetBackdropBorderColor(1.0, 0.92, 0.7, 0.95)
	-- Phase 3 / D-19: sequence is now non-empty → may exit soft-hide.
	applySoftHideState()
end

ClearAll = function()
	wipe(sequence)
	for i = 1, 5 do
		slotFrames[i].fs:SetText("")
		slotFrames[i]:SetBackdropBorderColor(0.65, 0.62, 0.55, 0.6)
	end
	-- Phase 3 / D-19: sequence is now empty → may enter soft-hide if autoHide=on.
	applySoftHideState()
end

-- ============================================================
-- Lock state (D-14..D-16, UI-SPEC §3.1)
-- ============================================================
applyLockState = function()
	local locked = ns.db.window.locked
	if locked then
		win:SetMovable(false)
		win:RegisterForDrag()
		lockBtn:Hide()
	else
		win:SetMovable(true)
		win:RegisterForDrag("LeftButton")
		lockBtn:Show()
	end
	win:EnableMouse(not locked)
	-- Live-refresh the config panel's Lock/Unlock button label. Safe to
	-- call from any code path (slash command, on-window button, /lura
	-- toggle dispatcher) — Config.lua's RefreshLockButton early-exits if
	-- the panel hasn't been opened yet (cachedLockFrame is nil) or if
	-- the cached frame isn't currently visible.
	if ns.RefreshLockButton then
		ns:RefreshLockButton()
	end
end

function ns:ToggleLocked()
	ns.db.window.locked = not ns.db.window.locked
	applyLockState()
end

-- ============================================================
-- Soft-hide state (Phase 3 / D-18..D-22)
-- Soft-hide = window stays visible (no Hide()) but alpha=0 while
-- autoHide=on AND sequence is empty. Chat events stay registered so
-- the next slot fill reveals the window via FillSlot → applySoftHideState.
-- ============================================================
-- SAFE-05: soft-hide MUST use SetAlpha(0) exclusively — NEVER the Hide() method.
-- Calling Hide() on the frame fires OnHide which calls unregisterChatEvents(),
-- breaking the AMEND-01 invariant: chat events must stay registered while the
-- window is shown (even at alpha=0) so the next slot fill can reveal it.
-- Origin: .planning/archive/v0.1.0/02-poc-port-macros-window-commands/02-VERIFICATION.md (AMEND-01)
applySoftHideState = function()
	if ns.db.window.autoHide and #sequence == 0 and inCombat then
		softHidden = true
		win:SetAlpha(0)
	else
		softHidden = false
		win:SetAlpha(ns.db.window.alpha or 1.00)
	end
end

-- ============================================================
-- Phase 3 exports — invoked by Config.lua's Settings change callbacks.
-- All five touch Window.lua state only; Config.lua never writes db.* directly.
-- ============================================================
function ns:SetWindowScale(value)
	if win then
		win:SetScale(value)
	end
end

function ns:SetWindowAlpha(value)
	-- Per D-21: while soft-hidden, do NOT call SetAlpha — the soft-hide
	-- override (alpha=0) wins; the new alpha applies on next exit.
	if win and not softHidden then
		win:SetAlpha(value)
	end
end

function ns:OnAutoHideChanged(value)
	-- The framework already wrote db.window.autoHide=value before this
	-- callback fires. We just re-evaluate state.
	applySoftHideState()
end

function ns:LockWindow()
	ns.db.window.locked = true
	applyLockState()
end

function ns:UnlockWindow()
	ns.db.window.locked = false
	applyLockState()
end

-- Phase 6 / CFG-13. The Show/Hide button label uses CreateSettingsButtonInitializer's
-- buttonText closure (Config.lua:201-207) which the framework only re-evaluates when
-- the panel runs Init for the element. This hook lets visibility-changing call sites
-- (ShowWindow, HideWindow, RestoreWindowVisibility) tell the framework to re-init
-- visible elements via SettingsInbound.RepairDisplay, so the label flips live without
-- the user having to close-and-reopen the panel. The early-exit guard makes this a
-- no-op when the panel isn't open (the 99.9% case — user is in combat, etc.). Per
-- D-12: applySoftHideState does NOT call this hook (soft-hide changes alpha only,
-- IsShown stays true, label is correct without a refresh — engineering-truth model).
function ns:NotifyWindowVisibilityChanged()
	-- Delegate to Config.lua's surgical button-text update. The Config.lua
	-- side captures the rendered frame via hooksecurefunc on
	-- SettingsButtonControlMixin:Init (gated by a sentinel data flag so
	-- only OUR Show/Hide button is captured) and calls SetText directly.
	-- This avoids the panel rebuild that DisplayCategory would do — which
	-- preserves the user's current scroll position. ns.RefreshShowHideButton
	-- is set up inside Config.lua's InitConfig deferred load; if the panel
	-- has never been opened in this session, the cached frame is nil and
	-- the function is a safe no-op.
	if ns.RefreshShowHideButton then
		ns:RefreshShowHideButton()
	end
end

-- ============================================================
-- Position persistence (D-20..D-22, WIN-09)
-- ============================================================
persistPosition = function()
	local point, relativeTo, relativePoint, x, y = win:GetPoint()
	ns.db.window.position = {
		point,
		(relativeTo and relativeTo.GetName and relativeTo:GetName()) or "UIParent",
		relativePoint,
		x,
		y,
	}
end

applySavedPosition = function()
	if positionApplied then
		return
	end
	positionApplied = true
	local pos = ns.db.window.position
	win:ClearAllPoints()
	if pos then
		win:SetPoint(pos[1], _G[pos[2]] or UIParent, pos[3], pos[4], pos[5])
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 200, 80)
	end
end

-- ============================================================
-- 20s inactivity self-clear (D-28, D-29; UI-SPEC §3.4)
-- ============================================================
ScheduleClear = function()
	if clearTimer then
		clearTimer:Cancel()
	end
	clearTimer = C_Timer.NewTimer(INACTIVITY_TIMEOUT, function()
		ClearAll()
		clearTimer = nil
	end)
end

ManualClear = function()
	if clearTimer then
		clearTimer:Cancel()
		clearTimer = nil
	end
	ClearAll()
end

-- ============================================================
-- Chat reception (D-30..D-32; SAFE-01, SAFE-02, SAFE-04)
--
-- Pipeline: msg arrives opaque → check db.listenChannels[event:sub(10)]
-- (D-31) → C_ChatInfo.ReplaceIconAndGroupExpressions(msg, nil, false)
-- (D-30, the Blizzard-secure helper exempt from taint) → FontString:SetText.
-- ZERO Lua string operations on msg.
-- ============================================================
local chatFrame = CreateFrame("Frame")
chatFrame:SetScript("OnEvent", function(self, event, msg)
	-- Channel filter (D-31). event:sub(10) strips "CHAT_MSG_" (9 chars + 1).
	-- This is a string op on EVENT, not on MSG — explicitly safe per SAFE-02.
	if not ns.db.listenChannels[event:sub(10)] then
		return
	end

	-- Pass msg opaquely through the Blizzard-secure helper (D-30).
	local processed = C_ChatInfo.ReplaceIconAndGroupExpressions(msg, nil, false)
	if not processed then
		return
	end

	-- Six-press wrap-around (UI-SPEC §5.3): clear all when full, then refill.
	if #sequence >= 5 then
		ClearAll()
	end
	sequence[#sequence + 1] = processed
	FillSlot(#sequence, processed)
	ScheduleClear()
	-- Do NOT call win:Show() here. Visibility is governed by /lura only.
end)

-- Internal helpers: callers are limited to Window.lua's own OnShow/OnHide
-- closures. Exposing them on ns would invite outside-Window.lua code to
-- bypass the visibility-gating contract (AMEND-01) — kept file-local.
registerChatEvents = function()
	for _, ev in ipairs(CHAT_EVENTS) do
		chatFrame:RegisterEvent(ev)
	end
end

unregisterChatEvents = function()
	for _, ev in ipairs(CHAT_EVENTS) do
		chatFrame:UnregisterEvent(ev)
	end
end

-- ============================================================
-- Window show/hide/wipe — exported for slash dispatcher (02-03).
-- OnShow/OnHide on the frame handle event registration + slot wipe;
-- these wrappers just toggle visibility.
-- ============================================================
function ns:ShowWindow()
	applySavedPosition()
	win:Show()
	-- Phase 3 / D-20: explicit show always reveals — visibility is a UX
	-- confirmation that the addon is engaged. The next 20s self-clear may
	-- re-enter soft-hide via ClearAll → applySoftHideState() if autoHide=on.
	softHidden = false
	win:SetAlpha(ns.db.window.alpha or 1.00)
	-- Persist visibility so /reload restores the same state.
	ns.db.window.visible = true
	ns:NotifyWindowVisibilityChanged()
end

function ns:HideWindow()
	win:Hide()
	ns.db.window.visible = false
	ns:NotifyWindowVisibilityChanged()
end

-- Like ShowWindow but respects soft-hide. Used by Core.lua at ADDON_LOADED
-- to restore the previous session's visibility without flashing the window
-- visible briefly when autoHide is on and the sequence is empty.
function ns:RestoreWindowVisibility()
	applySavedPosition()
	win:Show()
	-- OnShow re-registers chat events. Apply soft-hide if applicable
	-- (autoHide=on AND sequence empty → alpha=0, chat still hot).
	applySoftHideState()
	-- visible stays true (it already was — that's why we're restoring).
	ns:NotifyWindowVisibilityChanged()
end

function ns:IsWindowShown()
	return win and win:IsShown() or false
end

-- ============================================================
-- ns:InitWindow — Phase 1 dispatcher entry point
-- ============================================================
function ns:InitWindow()
	CreateWindow()
	-- Window stays hidden until /lura show. OnShow/OnHide handle
	-- chat-event registration + slot wipe.
end
