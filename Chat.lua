-- Transport layer: hidden addon-channel send + receive.
--
-- Wire format (adopted from BliZzi_Interrupts/Core/Core.lua's BIT.Net):
--   "D1;VERB;arg1;arg2;..."
--   D1     — version header. Lets a future v2 receiver skip / migrate
--            messages from v1 senders without ambiguity.
--   VERB   — uppercase action: USED, READY, INIT, PING.
--   args   — semicolon-delimited extras; receiver hands them to the
--            registered handler as an array. Single-arg in v1; the
--            multi-arg shape is future-proofing for sender metadata
--            (talent fingerprint, scheduled-ready timestamp, etc.).
--
-- Distribution strategy (also from BliZzi): in instances try
-- INSTANCE_CHAT first since that's the canonical channel for instance
-- content and survives cross-realm shards. Falls back to PARTY if
-- INSTANCE_CHAT returns ret ≠ 0. Last resort: whisper each visible
-- party member directly — rescues Timed M+ scenarios where Blizzard
-- throttles the group addon channels (ret == 11 is the documented
-- block code).
--
-- All messages are silent (CHAT_MSG_ADDON, not visible in chat windows).

local addonName, ns = ...

local PREFIX = "DSCD"
local PROTOCOL_VERSION = "D1"
local SEP = ";"

local Chat = {}
ns.Chat = Chat

-- Flag the user can /dump to see whether the channel is currently
-- blocked (Timed M+, etc.). Set by Transmit, cleared on the first
-- successful send.
ns.AddonMessagesBlocked = false

local receiveHandler = nil

function Chat:SetReceiveHandler(fn)
	receiveHandler = fn
end

-- Normalize "Name-Realm" -> "Name" when sender is on our realm, so it
-- matches UnitName("partyN") which omits the realm in that case.
local function NormalizeSender(sender)
	if not sender then return nil end
	return Ambiguate(sender, "none")
end

local function IsFromSelf(normalizedSender)
	if not normalizedSender then return false end
	local mine = NormalizeSender(UnitName("player"))
	return normalizedSender == mine
end

------------------------------------------------------------
-- Transmit with multi-channel fallback
------------------------------------------------------------

-- Try one channel; return true on success (ret == 0). Records the M+
-- block flag (ret == 11) without retrying — the caller decides whether
-- to attempt another channel.
local function TrySend(payload, channel, target)
	local ok, ret = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, channel, target)
	if ok and ret == 11 then ns.AddonMessagesBlocked = true end
	if ok and ret == 0 then
		ns.AddonMessagesBlocked = false
		return true
	end
	if ns.Debug then
		ns.Debug:print("chat-send",
			string.format("%s%s ret=%s ok=%s",
				channel, target and ("->" .. target) or "",
				tostring(ret), tostring(ok)))
	end
	return false
end

local function Transmit(payload)
	-- Use IsInGroup category constants so we can distinguish a normal
	-- party from an instance group (M+ / LFG / scenario) — BliZzi's
	-- pattern. LE_PARTY_CATEGORY_INSTANCE may not exist on older
	-- clients, hence the fallback 2.
	local INSTANCE = (LE_PARTY_CATEGORY_INSTANCE or 2)
	local HOME     = (LE_PARTY_CATEGORY_HOME or 1)
	local inInstance = IsInGroup(INSTANCE)
	local inHome     = IsInGroup(HOME)
	local inRaid     = IsInRaid()

	-- 1. Prefer INSTANCE_CHAT when actually in an instance group (M+,
	--    LFG, scenarios). It survives cross-realm shards better than
	--    PARTY.
	if inInstance and TrySend(payload, "INSTANCE_CHAT") then return true end

	-- 2. Normal group channel.
	if inRaid and TrySend(payload, "RAID") then return true end
	if inHome and TrySend(payload, "PARTY") then return true end

	-- 3. Some instance groups fail INSTANCE_CHAT but accept PARTY (e.g.
	--    when the home group is the same as the instance group). Try it
	--    explicitly even if `inHome` was false — the API tolerates a
	--    nominally-empty channel rather than throwing.
	if inInstance and TrySend(payload, "PARTY") then return true end

	-- 4. Whisper-each-member fallback. Rescues the Timed M+ block: if
	--    the group channels return ret == 11, individual whispers
	--    typically still go through.
	local delivered = false
	for i = 1, 4 do
		local u = "party" .. i
		if UnitExists(u) and UnitIsPlayer(u) then
			local ok, name, realm = pcall(UnitFullName, u)
			if ok and name then
				local target = (realm and realm ~= "") and (name .. "-" .. realm) or name
				if TrySend(payload, "WHISPER", target) then delivered = true end
			end
		end
	end
	return delivered
end

------------------------------------------------------------
-- Public send API
------------------------------------------------------------

-- Build a versioned-header payload from a verb + optional args.
-- Args are stringified individually; nil args become empty fields so
-- positional indexing on the receive side stays stable.
local function BuildPayload(verb, ...)
	local n = select("#", ...)
	if n == 0 then
		return PROTOCOL_VERSION .. SEP .. verb
	end
	local parts = { PROTOCOL_VERSION, verb }
	for i = 1, n do
		parts[i + 2] = tostring(select(i, ...) or "")
	end
	return table.concat(parts, SEP)
end

-- Send a verb with arbitrary args. Existing callers pass a single
-- payload arg (USED/READY: a spellID number; INIT: a CSV of IDs); the
-- multi-arg form is available for future protocol extensions without
-- a wire-format change.
function Chat:Send(verb, ...)
	if not (IsInGroup() or IsInRaid()) then return end
	local payload = BuildPayload(verb, ...)
	local sent = Transmit(payload)
	if ns.Debug then
		local logMsg = #payload > 80 and (payload:sub(1, 80) .. "...") or payload
		ns.Debug:print("chat-send", logMsg, sent and "ok" or "FAILED")
	end
end

-- Explicit delivery test. Always prints a chat-visible line on the
-- receiver, regardless of debug mode — that's its whole purpose.
function Chat:SendPing()
	if not (IsInGroup() or IsInRaid()) then
		print("|cffff5555DzakSharedCDs:|r not in a group; ping has no recipients")
		return
	end
	local stamp = tostring(math.floor(GetTime() * 1000))
	local payload = BuildPayload("PING", stamp)
	local sent = Transmit(payload)
	print(string.format("|cff00ff00DzakSharedCDs:|r ping sent (%s)%s",
		sent and "ok" or "FAILED",
		ns.AddonMessagesBlocked and " |cffff5555[M+ block detected]|r" or ""))
end

------------------------------------------------------------
-- Receive: parse the versioned format and dispatch
------------------------------------------------------------

-- Split a D1;VERB;arg1;arg2 payload into (verb, args[]). Returns nil
-- for malformed input. Backwards-compat: also accepts the legacy
-- "VERB:payload" format produced by pre-v0.8 clients.
local function Parse(text)
	if not text or text == "" then return nil end
	-- New format: starts with the protocol version.
	if text:sub(1, 3) == PROTOCOL_VERSION .. SEP then
		local body = text:sub(4)
		local parts = {}
		for part in body:gmatch("[^" .. SEP .. "]+") do
			parts[#parts + 1] = part
		end
		local verb = table.remove(parts, 1)
		return verb, parts
	end
	-- Legacy format: VERB:payload (no version header).
	local verb, payload = text:match("^(%u+):(.+)$")
	if verb then return verb, { payload } end
	return nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	if prefix ~= PREFIX then return end

	local verb, args = Parse(text)
	if not verb then
		if ns.Debug then ns.Debug:print("chat-recv", "malformed", text, "from", sender) end
		return
	end
	-- Parse() returns (nil) or (verb, table). When verb is non-nil args
	-- is always a table (possibly empty). The explicit reassignment is
	-- to satisfy the linter's nil-narrowing, which doesn't infer the
	-- "verb non-nil ⇒ args non-nil" invariant.
	args = args or {}

	local normalized = NormalizeSender(sender)

	-- PING is transport-layer and bypasses the regular handler so the
	-- delivery test works even before Tracker has registered.
	if verb == "PING" then
		if IsFromSelf(normalized) then
			print(string.format("|cff00ff00DzakSharedCDs:|r ping echoed back to self (channel=%s)", channel))
		else
			print(string.format("|cff00ff00DzakSharedCDs:|r received PING from %s (channel=%s)", normalized or "?", channel))
		end
		return
	end

	if not receiveHandler then return end

	if ns.Debug then
		local joined = table.concat(args, ";")
		local logArg = #joined > 80 and (joined:sub(1, 80) .. "...") or joined
		ns.Debug:print("chat-recv", channel, normalized, verb, logArg)
	end
	-- Pass the full args table — Tracker reads args[1] for spellId,
	-- args[2] for duration (USED only), etc. Single-arg verbs (READY,
	-- INIT) ignore args[2+].
	receiveHandler(normalized, verb, args)
end)

-- Prefix registration is the gate for receiving CHAT_MSG_ADDON; without
-- this our handler never fires even if other clients send to "DSCD".
-- Verify with: /dump C_ChatInfo.IsAddonMessagePrefixRegistered("DSCD")
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

Chat.PREFIX = PREFIX
Chat.PROTOCOL_VERSION = PROTOCOL_VERSION
