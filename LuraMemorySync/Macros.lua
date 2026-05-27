LuraMemorySync = LuraMemorySync or {}

LuraMemorySync.buildingSequence = LuraMemorySync.buildingSequence or {}

function LuraMemorySync.ClearBuildingSequence()
    wipe(LuraMemorySync.buildingSequence)
end

function LuraMemorySync.GetBuildingSequence()
    return LuraMemorySync.buildingSequence
end

function LuraMemorySync.CanBroadcastOrder()
    return UnitIsGroupLeader("player")
        or UnitIsGroupAssistant("player")
        or LuraMemorySync.forceMode
end

function LuraMemorySync.CanClearOrder()
    if not IsInRaid() and not IsInGroup() then
        return true
    end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function LuraMemorySync.AddSymbol(symbolID)
    local normalized = LuraMemorySync.NormalizeSymbolID(symbolID)
    if not normalized then
        return
    end

    if not LuraMemorySync.CanBroadcastOrder() then
        return
    end

    LuraMemorySyncDB = LuraMemorySyncDB or {}

    if LuraMemorySync.IsCurrentRoundComplete() then
        LuraMemorySync.BeginNewRound({ broadcast = true })
    elseif #LuraMemorySync.buildingSequence == 0 then
        if LuraMemorySyncDB.lastOrder and #LuraMemorySyncDB.lastOrder > 0 then
            LuraMemorySync.BeginNewRound({ broadcast = true })
        else
            LuraMemorySyncDB.lastOrder = {}
            if LuraMemorySync.ClearDisplayIfVisible then
                LuraMemorySync.ClearDisplayIfVisible()
            end
        end
    end

    if LuraMemorySync.OrderContainsSymbol(LuraMemorySync.buildingSequence, normalized) then
        return
    end

    table.insert(LuraMemorySync.buildingSequence, normalized)

    local autoSymbol = LuraMemorySync.GetAutoCompleteSymbol(LuraMemorySync.buildingSequence)
    if autoSymbol then
        table.insert(LuraMemorySync.buildingSequence, autoSymbol)
    end

    LuraMemorySync.SendLiveAdd(normalized, {
        force = LuraMemorySync.forceMode,
        autoCompleteSymbol = autoSymbol,
    })
end

function LuraMemorySync.SendCurrentBuild()
    if #LuraMemorySync.buildingSequence == 0 then
        return
    end
    if not LuraMemorySync.CanBroadcastOrder() then
        return
    end
    local order = LuraMemorySync.CopySymbolList(LuraMemorySync.buildingSequence)
    LuraMemorySync.SendLiveOrder(order, { force = LuraMemorySync.forceMode })
end

local function MacroIconFromPath(iconPath)
    if not iconPath then
        return "INV_Misc_QuestionMark"
    end
    if C_Texture and C_Texture.GetFileIDFromPath then
        local fileDataID = C_Texture.GetFileIDFromPath(iconPath)
        if fileDataID then
            return tostring(fileDataID)
        end
    end
    if GetFileIDFromPath then
        local fileDataID = GetFileIDFromPath(iconPath)
        if fileDataID then
            return tostring(fileDataID)
        end
    end
    return iconPath
end

local UTILITY_MACRO_ICONS = {
    ["LMS Send"] = "Interface\\Icons\\INV_Letter_15",
    ["LMS Undo"] = "Interface\\Icons\\Ability_Rogue_Feint",
    ["LMS Reset"] = "Interface\\Icons\\INV_Misc_Cancel_02",
}

local function UpsertMacro(name, icon, body)
    local existingIndex
    for i = 1, MAX_ACCOUNT_MACROS do
        if GetMacroInfo(i) == name then
            existingIndex = i
            break
        end
    end

    if existingIndex then
        EditMacro(existingIndex, name, icon, body)
        return existingIndex
    end

    if GetNumMacros() >= MAX_ACCOUNT_MACROS then
        return nil
    end
    return CreateMacro(name, icon, body, false)
end

function LuraMemorySync.CreateSymbolMacros()
    if #LuraMemorySync.Symbols == 0 then
        LuraMemorySync.ResolveIconPaths()
    end

    for _, sym in ipairs(LuraMemorySync.Symbols) do
        local macroName = "LMS Rune " .. sym.label
        local body = string.format("/run LuraMemorySync_AddSymbol('%s')", sym.id)
        UpsertMacro(macroName, sym.macroIcon or sym.texture, body)
    end

    UpsertMacro("LMS Send", MacroIconFromPath(UTILITY_MACRO_ICONS["LMS Send"]), "/run LuraMemorySync_SendBuild()")
    UpsertMacro("LMS Undo", MacroIconFromPath(UTILITY_MACRO_ICONS["LMS Undo"]), "/run LuraMemorySync_UndoSymbol()")
    UpsertMacro("LMS Reset", MacroIconFromPath(UTILITY_MACRO_ICONS["LMS Reset"]), "/run LuraMemorySync_ResetAll()")
end

function LuraMemorySync_UndoSymbol()
    if not LuraMemorySync.CanBroadcastOrder() then
        return
    end
    if #LuraMemorySync.buildingSequence == 0 then
        return
    end
    table.remove(LuraMemorySync.buildingSequence)
    local order = LuraMemorySync.CopySymbolList(LuraMemorySync.buildingSequence)
    if #order > 0 then
        LuraMemorySync.SendLiveOrder(order, { force = LuraMemorySync.forceMode })
    else
        LuraMemorySync.BeginNewRound({ broadcast = true })
    end
end

function LuraMemorySync_SendBuild()
    LuraMemorySync.SendCurrentBuild()
end

function LuraMemorySync_ResetAll()
    LuraMemorySync.SendReset()
end

function LuraMemorySync_AddSymbol(symbolID)
    LuraMemorySync.AddSymbol(symbolID)
end

_G.LuraMemorySync_AddSymbol = LuraMemorySync_AddSymbol
_G.LuraMemorySync_SendBuild = LuraMemorySync_SendBuild
_G.LuraMemorySync_UndoSymbol = LuraMemorySync_UndoSymbol
_G.LuraMemorySync_ResetAll = LuraMemorySync_ResetAll
