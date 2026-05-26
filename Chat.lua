-- Transport layer: hidden addon-channel send + receive.
--
-- Wire format on prefix "DSCD":
--   "USED:<spellID>"            - sender just cast the spell
--   "READY:<spellID>"           - sender's cooldown finished
--   "INIT:<id1>,<id2>,..."      - sender announces which tracked spells
--                                 they actually have talented; receivers
--                                 use this to filter what's drawn for
--                                 the sender's row.
--
-- Messages are silent (CHAT_MSG_ADDON, not visible in chat windows).
-- Throttled to 10 burst + 1/sec per prefix by Blizzard; Tracker
-- additionally debounces INIT broadcasts to be polite.

local addonName, ns = ...

local PREFIX = "DSCD"

local Chat = {}
ns.Chat = Chat

-- Subscribers: ns.Tracker registers a single OnReceive handler.
local receiveHandler = nil

function Chat:SetReceiveHandler(fn)
	receiveHandler = fn
end

-- Choose the right group distribution. INSTANCE_CHAT is required inside
-- instanced PvE/PvP so the message reaches the dungeon group rather than
-- being silently dropped.
local function GetDistribution()
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena") then
		return "INSTANCE_CHAT"
	end
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
		-- Truncate INIT payloads for log readability; the full CSV can be long.
		local logMsg = #msg > 80 and (msg:sub(1, 80) .. "...") or msg
		ns.Debug:print("chat-send", dist, logMsg, ok and "" or "FAILED")
	end
end

-- Normalize "Name-Realm" -> "Name" when sender is on our realm, so it
-- matches UnitName("partyN") which omits the realm in that case.
local function NormalizeSender(sender)
	if not sender then return nil end
	return Ambiguate(sender, "none")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	if prefix ~= PREFIX then return end
	if not receiveHandler then return end

	-- "VERB:PAYLOAD" — payload is a single spellID for USED/READY, a CSV
	-- of spellIDs for INIT. Verb is uppercase ASCII.
	local verb, payload = text:match("^(%u+):(.+)$")
	if not verb or not payload then
		if ns.Debug then ns.Debug:print("chat-recv", "malformed", text, "from", sender) end
		return
	end

	local normalized = NormalizeSender(sender)
	if ns.Debug then
		local logPayload = #payload > 80 and (payload:sub(1, 80) .. "...") or payload
		ns.Debug:print("chat-recv", channel, normalized, verb, logPayload)
	end
	receiveHandler(normalized, verb, payload)
end)

-- Prefix registration is the gate for receiving CHAT_MSG_ADDON; without
-- this our handler never fires even if other clients send to "DSCD".
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

Chat.PREFIX = PREFIX
