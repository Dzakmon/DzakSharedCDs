local addonName, ns = ...

-- DzakSharedCDs — party cooldown display.
--
-- Transport is deliberately dumb: a generated macro types a tagged line into
-- /p chat, and every receiver string-matches it. No addon comms, no libraries.
-- The consequence, and the whole point, is that the sender does not need this
-- addon installed — the macro is just text. Receivers therefore never assume
-- anything about sender-side state.
--
-- Duration and cooldown travel inside the message, so a receiver can display a
-- spell it has never heard of and has no local config for.
--
-- No COMBAT_LOG_EVENT_UNFILTERED anywhere. Combat log reliability regressed in
-- 12.0; this is a design decision, not an omission.

local TAG          = "DSCD1"
local MSG_PATTERN   = "^" .. TAG .. ":(%d+):([%d%.]+):(%d+)"
local MACRO_PREFIX  = "DSCD_"

local UPDATE_THROTTLE = 0.05
local DEDUPE_WINDOW   = 1.0

local BAR_WIDTH   = 220
local BAR_HEIGHT  = 20
local BAR_SPACING = 2

-- Values predate 12.0 and are unverified against live. Confirm in game.
local DEFAULT_SPELLS = {
	[51052]  = { duration = 8, cooldown = 120 },                 -- Anti-Magic Zone
	[196718] = { duration = 8, cooldown = 300, mod = "@cursor" }, -- Darkness (reticle)
	[374227] = { duration = 8, cooldown = 120 },                 -- Zephyr
}

local db      -- shorthand for DzakSharedCDsDB, set on ADDON_LOADED
local anchor
local pool    = {}  -- released bars, reused
local active  = {}  -- bars currently showing something
local lastSeen = {} -- guid..spellID -> timestamp, for dedupe


local function log(...)
	if ns.Debug then ns.Debug:print("core", ...) end
end


local function chat(msg)
	print("|cff00ffaa[DzakSharedCDs]|r " .. msg)
end


-- ============================ helpers ============================

local function spellName(spellID)
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
	return info and info.name or nil
end


local function spellIcon(spellID)
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
		or 134400 -- INV_MISC_QUESTIONMARK
end


-- Realm suffix is noise in a party display: "Dzak-Silvermoon" -> "Dzak".
local function shortName(name)
	if not name then return "?" end
	return (strsplit("-", name))
end


-- 12.0 secret values: UnitClass and UnitClassBase reject them, the GUID
-- variant does not. Return order has moved around between builds, so accept
-- whichever return actually keys into RAID_CLASS_COLORS.
local function classColor(guid)
	if not guid then return nil end
	local ok, a, b = pcall(UnitClassFromGUID, guid)
	if not ok then return nil end
	return RAID_CLASS_COLORS[b] or RAID_CLASS_COLORS[a]
end


-- ============================ bar pool ============================
-- Acquire and release, never destroy. A long session with a chatty party
-- would otherwise leak frames until the taint-free frame budget hurts.

local function createBar()
	local bar = CreateFrame("StatusBar", nil, anchor)
	bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 1)

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)

	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetSize(BAR_HEIGHT - 2, BAR_HEIGHT - 2)
	bar.icon:SetPoint("LEFT", bar, "LEFT", 1, 0)
	bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.label:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
	bar.label:SetJustifyH("LEFT")

	bar.timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.timer:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	bar.timer:SetJustifyH("RIGHT")

	-- Leave room for the timer so long spell names truncate instead of overlap.
	bar.label:SetPoint("RIGHT", bar.timer, "LEFT", -4, 0)
	bar.label:SetWordWrap(false)

	return bar
end


local function acquireBar()
	local bar = table.remove(pool)
	if not bar then bar = createBar() end
	bar:Show()
	return bar
end


local function releaseBar(bar)
	bar:Hide()
	bar:ClearAllPoints()
	pool[#pool + 1] = bar
end


-- ============================ display ============================

local function layout()
	-- Sort by remaining ascending so the next expiry is always at the same
	-- edge, whichever way the list grows.
	table.sort(active, function(a, b) return a.remaining < b.remaining end)

	local step = BAR_HEIGHT + BAR_SPACING
	local up   = db.growUp
	for i, bar in ipairs(active) do
		bar:ClearAllPoints()
		local offset = (i - 1) * step
		bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, up and offset or -offset)
	end
end


-- Two states, one bar. Bright while the effect is up and counting the
-- duration; on expiry the same bar dims and counts down the remaining
-- cooldown, then releases. One code path, one sort key, no second list.
local function refreshBar(bar, now)
	if bar.state == "active" and now >= bar.expiresAt then
		bar.state = "cooldown"
	end

	if bar.state == "active" then
		bar.remaining = bar.expiresAt - now
		bar:SetValue(bar.total > 0 and (bar.remaining / bar.total) or 0)
		local c = bar.color
		bar:SetStatusBarColor(c.r, c.g, c.b, 1)
		bar:SetAlpha(1)
	else
		bar.remaining = bar.cdEndsAt - now
		bar:SetValue(bar.cd > 0 and (bar.remaining / bar.cd) or 0)
		bar:SetStatusBarColor(0.4, 0.4, 0.4, 1)
		bar:SetAlpha(0.55)
	end

	bar.timer:SetFormattedText(bar.remaining >= 10 and "%.0f" or "%.1f", bar.remaining)
	return bar.remaining > 0
end


local elapsedSinceUpdate = 0

-- One OnUpdate on the anchor iterating every bar, not one per bar.
local function onUpdate(_, elapsed)
	elapsedSinceUpdate = elapsedSinceUpdate + elapsed
	if elapsedSinceUpdate < UPDATE_THROTTLE then return end
	elapsedSinceUpdate = 0

	local now = GetTime()

	for i = #active, 1, -1 do
		local bar = active[i]
		if not refreshBar(bar, now) then
			table.remove(active, i)
			releaseBar(bar)
		end
	end

	if #active == 0 then
		anchor:SetScript("OnUpdate", nil)
		return
	end

	-- Re-sort every tick: a bar flipping from duration to cooldown jumps its
	-- remaining value, so the order genuinely can change on any tick. This is
	-- a handful of elements at 20 Hz.
	layout()
end


local function showTimer(spellID, duration, cooldown, senderName, senderGUID)
	local key = (senderGUID or senderName or "?") .. ":" .. spellID
	local now = GetTime()

	-- A double macro press should not stack two bars.
	if lastSeen[key] and (now - lastSeen[key]) < DEDUPE_WINDOW then
		log("deduped", key)
		return
	end
	lastSeen[key] = now

	local name = spellName(spellID) or ("Spell " .. spellID)
	local bar  = acquireBar()

	bar.spellID   = spellID
	bar.total     = duration
	bar.cd        = cooldown
	bar.expiresAt = now + duration
	bar.cdEndsAt  = now + cooldown
	bar.state     = duration > 0 and "active" or "cooldown"
	bar.remaining = duration > 0 and duration or cooldown
	bar.color     = classColor(senderGUID) or { r = 0.8, g = 0.8, b = 0.8 }

	bar.icon:SetTexture(spellIcon(spellID))
	bar.label:SetFormattedText("|cff%02x%02x%02x%s|r  %s",
		bar.color.r * 255, bar.color.g * 255, bar.color.b * 255,
		shortName(senderName), name)

	active[#active + 1] = bar
	refreshBar(bar, now)
	layout()

	anchor:SetScript("OnUpdate", onUpdate)
	log("show", spellID, duration, cooldown, senderName)
end


-- ============================ anchor ============================

local function saveAnchorPosition()
	local point, _, relPoint, x, y = anchor:GetPoint()
	db.anchor = { point = point, relPoint = relPoint, x = x, y = y }
end


local function applyLock()
	local locked = db.locked
	anchor:EnableMouse(not locked)
	anchor:SetMovable(not locked)
	if locked then
		anchor.backdrop:Hide()
		anchor.hint:Hide()
	else
		anchor.backdrop:Show()
		anchor.hint:Show()
	end
end


local function createAnchor()
	anchor = CreateFrame("Frame", "DzakSharedCDsAnchor", UIParent)
	anchor:SetSize(BAR_WIDTH, BAR_HEIGHT)
	anchor:SetClampedToScreen(true)

	anchor.backdrop = anchor:CreateTexture(nil, "BACKGROUND")
	anchor.backdrop:SetAllPoints()
	anchor.backdrop:SetColorTexture(0, 0.6, 0.9, 0.35)

	anchor.hint = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	anchor.hint:SetPoint("CENTER")
	anchor.hint:SetText("DzakSharedCDs — drag me, then /dscd lock")

	local a = db.anchor
	if a and a.point then
		anchor:SetPoint(a.point, UIParent, a.relPoint or a.point, a.x or 0, a.y or 0)
	else
		anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
	end

	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self)
		if not db.locked then self:StartMoving() end
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		saveAnchorPosition()
	end)

	applyLock()
end


-- ============================ macros ============================

local function macroBody(spellID, cfg, name)
	local line = string.format("%s:%d:%s:%d %s down",
		TAG, spellID, tostring(cfg.duration), cfg.cooldown, name)

	local castTarget = cfg.mod and (cfg.mod .. " " .. name) or name
	return string.format("#showtooltip %s\n/p %s\n/cast %s", name, line, castTarget)
end


local function generateMacros()
	-- CreateMacro and EditMacro are protected in combat.
	if InCombatLockdown() then
		chat("Can't touch macros in combat — retry once you're out.")
		return
	end

	local made, edited, failed = 0, 0, 0
	for spellID, cfg in pairs(db.spells) do
		-- Build the name from the ID so macros work on non-English clients.
		local name = spellName(spellID)
		if not name then
			chat(string.format("Spell %d is unknown to the client — skipped.", spellID))
			failed = failed + 1
		else
			local macroName = MACRO_PREFIX .. spellID
			local body      = macroBody(spellID, cfg, name)
			local index     = GetMacroIndexByName(macroName)
			if index and index > 0 then
				EditMacro(index, macroName, spellIcon(spellID), body)
				edited = edited + 1
			else
				local created = CreateMacro(macroName, spellIcon(spellID), body, false)
				if created then
					made = made + 1
				else
					chat("Out of macro slots — free one and rerun /dscd macro.")
					failed = failed + 1
				end
			end
		end
	end

	chat(string.format("Macros: %d created, %d updated%s.",
		made, edited, failed > 0 and (", " .. failed .. " skipped") or ""))
end


-- ============================ messages ============================

local function onChatMessage(text, senderName, senderGUID)
	if not text then return end

	-- Anchored at string start, so ordinary party chat quoting the tag
	-- mid-sentence cannot trigger a bar.
	local spellID, duration, cooldown = text:match(MSG_PATTERN)
	if not spellID then return end

	spellID  = tonumber(spellID)
	duration = tonumber(duration)
	cooldown = tonumber(cooldown)
	if not (spellID and duration and cooldown) then return end

	-- A macro fires its chat line even when the cast failed, so this timer can
	-- be wrong. Accepted tradeoff; do not add machinery to second-guess it.
	showTimer(spellID, duration, cooldown, senderName, senderGUID)
end


-- ============================ slash ============================

local function cmdAdd(rest)
	local id, dur, cd, mod = strsplit(" ", rest or "")
	id, dur, cd = tonumber(id), tonumber(dur), tonumber(cd)
	if not (id and dur and cd) then
		chat("Usage: /dscd add <spellID> <duration> <cooldown> [castModifier]")
		return
	end
	if not spellName(id) then
		chat(string.format("Warning: spell %d is unknown to this client. Added anyway.", id))
	end
	db.spells[id] = { duration = dur, cooldown = cd, mod = (mod ~= "" and mod) or nil }
	chat(string.format("Added %s (%d): %ss for %ss cooldown.",
		spellName(id) or "?", id, tostring(dur), tostring(cd)))
	chat("Run /dscd macro to (re)generate the macro.")
end


local function cmdRemove(rest)
	local id = tonumber(rest)
	if not id then
		chat("Usage: /dscd remove <spellID>")
		return
	end
	if not db.spells[id] then
		chat(string.format("Spell %d isn't configured.", id))
		return
	end
	db.spells[id] = nil
	chat(string.format("Removed %d. Its macro is left in place — delete it by hand if you want it gone.", id))
end


local function cmdList()
	local ids = {}
	for id in pairs(db.spells) do ids[#ids + 1] = id end
	table.sort(ids)

	if #ids == 0 then
		chat("No spells configured.")
		return
	end

	chat("Configured spells:")
	for _, id in ipairs(ids) do
		local cfg = db.spells[id]
		print(string.format("  %d  %s  %ss / %ss%s",
			id, spellName(id) or "|cffff5555unknown|r",
			tostring(cfg.duration), tostring(cfg.cooldown),
			cfg.mod and ("  " .. cfg.mod) or ""))
	end
end


local function cmdTest(rest)
	local id = tonumber(rest)
	local cfg = id and db.spells[id]
	if not cfg then
		-- Fall back to any configured spell so /dscd test alone does something.
		for sid, c in pairs(db.spells) do
			id, cfg = sid, c
			break
		end
	end
	if not cfg then
		chat("Nothing to test — configure a spell first with /dscd add.")
		return
	end
	-- Bypass the dedupe window so repeated tests always draw.
	lastSeen[(UnitGUID("player") or "?") .. ":" .. id] = nil
	showTimer(id, cfg.duration, cfg.cooldown, UnitName("player"), UnitGUID("player"))
end


local SLASH_HELP = {
	"/dscd add <spellID> <duration> <cooldown> [castModifier]",
	"/dscd remove <spellID>",
	"/dscd list",
	"/dscd macro           (re)generate all macros",
	"/dscd unlock | lock   move the anchor",
	"/dscd grow            flip growth direction",
	"/dscd test <spellID>  fake an inbound message",
}

SLASH_DZAKSHAREDCDS1 = "/dscd"
SlashCmdList["DZAKSHAREDCDS"] = function(msg)
	local cmd, rest = strsplit(" ", msg or "", 2)
	cmd = (cmd or ""):lower()

	if cmd == "add" then
		cmdAdd(rest)
	elseif cmd == "remove" then
		cmdRemove(rest)
	elseif cmd == "list" then
		cmdList()
	elseif cmd == "macro" then
		generateMacros()
	elseif cmd == "unlock" then
		db.locked = false
		applyLock()
		chat("Anchor unlocked — drag it, then /dscd lock.")
	elseif cmd == "lock" then
		db.locked = true
		applyLock()
		saveAnchorPosition()
		chat("Anchor locked.")
	elseif cmd == "grow" then
		db.growUp = not db.growUp
		layout()
		chat("Bars now grow " .. (db.growUp and "up." or "down."))
	elseif cmd == "test" then
		cmdTest(rest)
	else
		chat("Commands:")
		for _, line in ipairs(SLASH_HELP) do print("  " .. line) end
	end
end


-- ============================ init ============================

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CHAT_MSG_PARTY")
events:RegisterEvent("CHAT_MSG_PARTY_LEADER")

events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= addonName then return end

		DzakSharedCDsDB = DzakSharedCDsDB or {}
		db = DzakSharedCDsDB
		if db.locked == nil then db.locked = true end
		if db.growUp == nil then db.growUp = false end
		if not db.spells then
			db.spells = {}
			for id, cfg in pairs(DEFAULT_SPELLS) do
				db.spells[id] = { duration = cfg.duration, cooldown = cfg.cooldown, mod = cfg.mod }
			end
		end

		createAnchor()
		self:UnregisterEvent("ADDON_LOADED")
		log("loaded")
		return
	end

	-- arg1 is the message text, arg2 the sender, arg12 the sender GUID. The
	-- GUID is the only identity source here that survives 12.0 secret values.
	local text, senderName = ...
	local senderGUID = select(12, ...)
	onChatMessage(text, senderName, senderGUID)
end)
