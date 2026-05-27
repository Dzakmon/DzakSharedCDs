-- Transport layer: party/instance chat send + receive.
--
-- Proof-of-concept transport using visible /p (or /raid / /instance) chat
-- instead of the hidden addon-message channel. Each wire message is
-- tagged "[DSCD]VERB:payload" so receivers can filter their own from
-- normal chatter. Visible-by-design while we confirm delivery actually
-- happens; once verified, we'll move back to C_ChatInfo.SendAddonMessage.
--
-- Wire format on tag "[DSCD]":
--   "[DSCD]USED:<spellID>"          - sender just cast the spell
--   "[DSCD]READY:<spellID>"         - sender's cooldown finished
--   "[DSCD]INIT:<id1>,<id2>,..."    - sender announces tracked spells

local addonName, ns = ...

local TAG = "[DSCD]"

local Chat = {}
ns.Chat = Chat

-- Subscribers: ns.Tracker registers a single OnReceive handler.
local receiveHandler = nil

function Chat:SetReceiveHandler(fn)
	receiveHandler = fn
end

-- Mirrors the original addon-channel distribution rule: inside any
-- instanced PvE/PvP you must use INSTANCE_CHAT (the auto-merged /i),
-- otherwise PARTY / RAID is silently dropped.
local function GetChatType()
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena") then
		return "INSTANCE_CHAT"
	end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

function Chat:Send(verb, payload)
	local chatType = GetChatType()
	if not chatType then return end
	local msg = TAG .. verb .. ":" .. tostring(payload)
	SendChatMessage(msg, chatType)
	if ns.Debug then
		local logMsg = #msg > 80 and (msg:sub(1, 80) .. "...") or msg
		ns.Debug:print("chat-send", chatType, logMsg)
	end
end

-- Normalize "Name-Realm" -> "Name" when sender is on our realm, so it
-- matches UnitName("partyN") which omits the realm in that case.
local function NormalizeSender(sender)
	if not sender then return nil end
	return Ambiguate(sender, "none")
end

local function ParseTagged(text)
	if not text or text:sub(1, #TAG) ~= TAG then return nil, nil end
	local body = text:sub(#TAG + 1)
	return body:match("^(%u+):(.+)$")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
frame:SetScript("OnEvent", function(_, event, text, sender)
	if not receiveHandler then return end

	local verb, payload = ParseTagged(text)
	if not verb or not payload then return end

	local normalized = NormalizeSender(sender)
	if ns.Debug then
		local logPayload = #payload > 80 and (payload:sub(1, 80) .. "...") or payload
		ns.Debug:print("chat-recv", event, normalized, verb, logPayload)
	end
	receiveHandler(normalized, verb, payload)
end)

-- Kept for compatibility with any code that referenced the old addon-
-- channel prefix; not used by the chat transport.
Chat.PREFIX = TAG
