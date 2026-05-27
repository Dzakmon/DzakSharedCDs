LuraMemorySync = LuraMemorySync or {}

local ADDON_PREFIX = "LURAMEMSYNC"
local ADDON_VERSION = "0.5.8"

LuraMemorySync.ADDON_VERSION = ADDON_VERSION
LuraMemorySync.playerVersions = LuraMemorySync.playerVersions or {}

local prefixRegistered = false

local function IsInAnyGroup()
    return IsInRaid() or IsInGroup()
end

local function IsFromSelf(sender)
    if not sender then
        return false
    end
    return LuraMemorySync.ShortName(sender) == LuraMemorySync.ShortName(UnitName("player"))
end

-- Eigene Raid/Party-Nachrichten kommen als CHAT_MSG_ADDON zurück — nicht erneut anwenden.
local function ShouldIgnoreOwnAddonEcho(sender)
    return IsFromSelf(sender) and IsInAnyGroup()
end

function LuraMemorySync.ShortName(fullName)
    if not fullName then
        return nil
    end
    return fullName:match("^([^%-]+)") or fullName
end

function LuraMemorySync.RegisterCommPrefix()
    if prefixRegistered or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    prefixRegistered = true
end

local function SendToGroup(message)
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, "PARTY")
    end
    -- Solo: nur lokale Apply-Funktionen, kein OnAddonMessage (verhindert Doppelung)
end

function LuraMemorySync.SenderIsLeader(sender)
    local senderShort = LuraMemorySync.ShortName(sender)
    if not senderShort then
        return false
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            local name = UnitName(unit)
            if name and LuraMemorySync.ShortName(name) == senderShort then
                return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
            end
        end
        return false
    end

    if IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name and LuraMemorySync.ShortName(name) == senderShort then
                return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
            end
        end
    end

    local playerName = UnitName("player")
    return LuraMemorySync.ShortName(playerName) == senderShort
        and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

function LuraMemorySync.ValidateSymbolIDs(symbolIDs)
    if type(symbolIDs) ~= "table" then
        return false
    end
    local seen = {}
    for i = 1, #symbolIDs do
        local id = LuraMemorySync.NormalizeSymbolID and LuraMemorySync.NormalizeSymbolID(symbolIDs[i]) or symbolIDs[i]
        if not id or not LuraMemorySync.SymbolByID[id] then
            return false
        end
        if seen[id] then
            return false
        end
        seen[id] = true
    end
    return true
end

function LuraMemorySync.CopySymbolList(symbolIDs)
    local copy = {}
    for i = 1, #symbolIDs do
        copy[i] = symbolIDs[i]
    end
    return copy
end

function LuraMemorySync.BroadcastVersion()
    local shortName = LuraMemorySync.ShortName(UnitName("player"))
    if shortName then
        LuraMemorySync.playerVersions[shortName] = ADDON_VERSION
    end
    SendToGroup("VERSION_REPLY:" .. ADDON_VERSION)
end

function LuraMemorySync.RequestVersions()
    LuraMemorySync.playerVersions = {}
    LuraMemorySync.BroadcastVersion()
    SendToGroup("VERSION_REQUEST")
end

function LuraMemorySync.GetLiveOrder()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    return LuraMemorySyncDB.lastOrder or {}
end

function LuraMemorySync.ApplyLiveOrder(symbolIDs, options)
    local copy = LuraMemorySync.CopySymbolList(symbolIDs)
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySyncDB.lastOrder = copy

    local required = LuraMemorySync.GetRequiredSymbolCount()
    if #copy >= required then
        LuraMemorySyncDB.history = LuraMemorySyncDB.history or {}
        table.insert(LuraMemorySyncDB.history, 1, copy)
        while #LuraMemorySyncDB.history > 8 do
            table.remove(LuraMemorySyncDB.history)
        end
    end

    if LuraMemorySync.RefreshDisplayIfVisible then
        LuraMemorySync.RefreshDisplayIfVisible()
    end

    if LuraMemorySync.MaybeShowFakeRaidWarning then
        LuraMemorySync.MaybeShowFakeRaidWarning(copy)
    end
end

function LuraMemorySync.AppendLiveSymbol(symbolID)
    if not LuraMemorySync.SymbolByID[symbolID] then
        return
    end

    LuraMemorySyncDB = LuraMemorySyncDB or {}
    local order = LuraMemorySyncDB.lastOrder or {}

    -- Liste voll → neue Runde mit diesem Symbol als erstem (nur anhand lastOrder)
    local required = LuraMemorySync.GetRequiredSymbolCount()
    if #order >= required then
        order = {}
    end

    local newOrder, added = LuraMemorySync.AppendSymbolsWithAutoComplete(order, symbolID)
    if not added then
        return
    end

    LuraMemorySyncDB.lastOrder = newOrder
    LuraMemorySync.ApplyLiveOrder(newOrder)
end

function LuraMemorySync.BeginNewRound(options)
    options = options or {}
    if LuraMemorySync.CancelAutoHideTimer then
        LuraMemorySync.CancelAutoHideTimer()
    end
    LuraMemorySync.ClearBuildingSequence()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySyncDB.lastOrder = {}

    if LuraMemorySync.ClearDisplayIfVisible then
        LuraMemorySync.ClearDisplayIfVisible()
    end
    if LuraMemorySync.HideFakeRaidWarning then
        LuraMemorySync.HideFakeRaidWarning()
    end

    if options.broadcast and LuraMemorySync.CanBroadcastOrder() then
        SendToGroup("NEWROUND")
    end
end

function LuraMemorySync.SendReset()
    if not LuraMemorySync.CanClearOrder() then
        return false
    end
    LuraMemorySync.BeginNewRound({ broadcast = true })
    return true
end

function LuraMemorySync.SendLiveAdd(symbolID, options)
    options = options or {}
    if not LuraMemorySync.SymbolByID[symbolID] then
        return false
    end

    local header = options.force and "FORCE_ADD:" or "LIVEADD:"
    SendToGroup(header .. symbolID)

    if not options.skipLocalApply then
        LuraMemorySync.AppendLiveSymbol(symbolID)
    end

    if options.autoCompleteSymbol and not options.skipLocalApply then
        SendToGroup(header .. options.autoCompleteSymbol)
    end

    return true
end

function LuraMemorySync.SendLiveOrder(symbolIDs, options)
    options = options or {}
    if not LuraMemorySync.ValidateSymbolIDs(symbolIDs) or #symbolIDs == 0 then
        return false
    end

    local copy = LuraMemorySync.CopySymbolList(symbolIDs)
    local header = (options.force and "FORCE_LIVE:") or "LIVE:"
    SendToGroup(header .. table.concat(copy, ","))

    if not options.skipLocalApply then
        LuraMemorySync.ApplyLiveOrder(copy)
    end
    return true
end

function LuraMemorySync.SendOrder(symbolIDs, options)
    return LuraMemorySync.SendLiveOrder(symbolIDs, options)
end

local function ParseListMessage(message, headerLen)
    local ids = {}
    for id in message:sub(headerLen + 1):gmatch("[^,]+") do
        table.insert(ids, id)
    end
    return ids
end

local function CanAcceptLiveFrom(sender, forceMessage)
    if forceMessage then
        return true
    end
    return LuraMemorySync.SenderIsLeader(sender)
end

local function HandleLiveAdd(message, sender, headerLen, forceMessage)
    if ShouldIgnoreOwnAddonEcho(sender) then
        return
    end
    if not CanAcceptLiveFrom(sender, forceMessage) then
        return
    end
    local symbolID = message:sub(headerLen + 1)
    LuraMemorySync.AppendLiveSymbol(symbolID)
end

local function HandleLiveFull(message, sender, headerLen, forceMessage)
    if ShouldIgnoreOwnAddonEcho(sender) then
        return
    end
    if not CanAcceptLiveFrom(sender, forceMessage) then
        return
    end
    local ids = ParseListMessage(message, headerLen)
    if not LuraMemorySync.ValidateSymbolIDs(ids) or #ids == 0 then
        return
    end
    LuraMemorySync.ApplyLiveOrder(ids)
end

function LuraMemorySync.OnAddonMessage(message, sender)
    if message == "VERSION_REQUEST" then
        LuraMemorySync.BroadcastVersion()
        return
    end

    local version = message:match("^VERSION_REPLY:(.+)$")
    if version then
        local shortName = LuraMemorySync.ShortName(sender)
        if shortName then
            LuraMemorySync.playerVersions[shortName] = version
        end
        return
    end

    if message == "NEWROUND" or message == "RESET" then
        if not ShouldIgnoreOwnAddonEcho(sender) then
            LuraMemorySync.ClearBuildingSequence()
            LuraMemorySyncDB = LuraMemorySyncDB or {}
            LuraMemorySyncDB.lastOrder = {}
            if LuraMemorySync.ClearDisplayIfVisible then
                LuraMemorySync.ClearDisplayIfVisible()
            end
        end
        return
    end

    if message:sub(1, 10) == "FORCE_ADD:" then
        HandleLiveAdd(message, sender, 10, true)
        return
    end

    if message:sub(1, 8) == "LIVEADD:" then
        HandleLiveAdd(message, sender, 8, false)
        return
    end

    if message:sub(1, 11) == "FORCE_LIVE:" then
        HandleLiveFull(message, sender, 11, true)
        return
    end

    if message:sub(1, 5) == "LIVE:" then
        HandleLiveFull(message, sender, 5, false)
        return
    end

    if message:sub(1, 12) == "FORCE_ORDER:" then
        HandleLiveFull(message, sender, 12, true)
        return
    end

    if message:sub(1, 6) == "ORDER:" then
        HandleLiveFull(message, sender, 6, false)
    end
end
