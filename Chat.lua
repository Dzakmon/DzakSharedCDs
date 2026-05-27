-- Transport layer: hidden addon-channel send + receive.
--
-- Confirmed pattern (mirrors LuraMemorySync / LuraMemorySync1, both of
-- which are working production addons living next to this one): register
-- a 16-char-max prefix once, send via C_ChatInfo.SendAddonMessage to
-- PARTY or RAID, receive on CHAT_MSG_ADDON filtered by prefix. We do
-- NOT use INSTANCE_CHAT — LuraMemorySync explicitly avoids it and is
-- known to deliver inside dungeons. (Some wiki guidance says addon
-- messages "should" use INSTANCE_CHAT in instances; in practice PARTY
-- works and is what real addons ship.)
--
-- Wire format on prefix "DSCD":
--   "USED:<spellID>"        - sender just cast the spell
--   "READY:<spellID>"       - sender's cooldown finished
--   "INIT:<id1>,<id2>,..."  - sender announces talented + tracked spells
--   "PING:<anything>"       - delivery parity test from /dscd ping;
--                             receiver prints a visible confirmation
--
-- Messages are silent (CHAT_MSG_ADDON, not visible in chat windows).
-- Throttled by Blizzard to 10 burst + 1/sec per prefix; Tracker
-- additionally debounces INIT to stay polite.

local addonName, ns = ...

local PREFIX = "DSCD"

local Chat = {}
ns.Chat = Chat

-- Subscribers: ns.Tracker registers a single OnReceive handler.
local receiveHandler = nil

function Chat:SetReceiveHandler(fn)
	receiveHandler = fn
end

-- LuraMemorySync uses PARTY/RAID only; we mirror that. No INSTANCE_CHAT.
local function GetDistribution()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

function Chat:Send(verb, payload)
	local dist = GetDistribution()
	if not dist then return end
	local msg = verb .. ":" .. tostring(payload)
	local ok = C_ChatInfo.SendAddonMessage(PREFIX, msg, dist)
	if ns.Debug then
		local logMsg = #msg > 80 and (msg:sub(1, 80) .. "...") or msg
		ns.Debug:print("chat-send", dist, logMsg, ok and "" or "FAILED")
	end
end

-- Explicit delivery test. Always prints a chat-visible line on the
-- receiver, regardless of debug mode — that's its whole purpose.
function Chat:SendPing()
	local dist = GetDistribution()
	if not dist then
		print("|cffff5555DzakSharedCDs:|r not in a group; ping has no recipients")
		return
	end
	local stamp = tostring(math.floor(GetTime() * 1000))
	local ok = C_ChatInfo.SendAddonMessage(PREFIX, "PING:" .. stamp, dist)
	print(string.format("|cff00ff00DzakSharedCDs:|r ping sent to %s (%s)", dist, ok and "ok" or "FAILED"))
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	if prefix ~= PREFIX then return end

	local verb, payload = text:match("^(%u+):(.+)$")
	if not verb or not payload then
		if ns.Debug then ns.Debug:print("chat-recv", "malformed", text, "from", sender) end
		return
	end

	local normalized = NormalizeSender(sender)

	-- PING is transport-layer and bypasses the regular handler so the
	-- delivery test works even before Tracker has registered.
	if verb == "PING" then
		if IsFromSelf(normalized) then
			-- Own echo: PARTY/RAID addon messages come back to the sender.
			-- Note it so the user can see both sides of the round-trip.
			print(string.format("|cff00ff00DzakSharedCDs:|r ping echoed back to self (channel=%s)", channel))
		else
			print(string.format("|cff00ff00DzakSharedCDs:|r received PING from %s (channel=%s)", normalized or "?", channel))
		end
		return
	end

	if not receiveHandler then return end

	if ns.Debug then
		local logPayload = #payload > 80 and (payload:sub(1, 80) .. "...") or payload
		ns.Debug:print("chat-recv", channel, normalized, verb, logPayload)
	end
	receiveHandler(normalized, verb, payload)
end)

-- Prefix registration is the gate for receiving CHAT_MSG_ADDON; without
-- this our handler never fires even if other clients send to "DSCD".
-- Verify with: /dump C_ChatInfo.IsAddonMessagePrefixRegistered("DSCD")
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

Chat.PREFIX = PREFIX
