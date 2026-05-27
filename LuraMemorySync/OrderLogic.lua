LuraMemorySync = LuraMemorySync or {}

function LuraMemorySync.NormalizeSymbolID(symbolID)
    local sym = LuraMemorySync.SymbolByID[symbolID]
    if sym then
        return sym.id
    end
    return nil
end

function LuraMemorySync.OrderContainsSymbol(order, symbolID)
    local normalized = LuraMemorySync.NormalizeSymbolID(symbolID)
    if not normalized then
        return false
    end
    for i = 1, #order do
        if LuraMemorySync.NormalizeSymbolID(order[i]) == normalized then
            return true
        end
    end
    return false
end

function LuraMemorySync.GetMissingSymbols(order)
    local missing = {}
    for _, sym in ipairs(LuraMemorySync.Symbols) do
        if not LuraMemorySync.OrderContainsSymbol(order, sym.id) then
            table.insert(missing, sym.id)
        end
    end
    return missing
end

function LuraMemorySync.GetAutoCompleteSymbol(order)
    local required = LuraMemorySync.GetRequiredSymbolCount()
    if #order ~= required - 1 then
        return nil
    end
    local missing = LuraMemorySync.GetMissingSymbols(order)
    if #missing == 1 then
        return missing[1]
    end
    return nil
end

-- Nur lastOrder zählt (nicht buildingSequence — die kann beim 4.+5. Auto-Complete schon 5 Einträge haben).
function LuraMemorySync.IsCurrentRoundComplete()
    local required = LuraMemorySync.GetRequiredSymbolCount()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    local lastOrder = LuraMemorySyncDB.lastOrder or {}
    return #lastOrder >= required
end

function LuraMemorySync.AppendSymbolsWithAutoComplete(order, symbolID)
    local normalized = LuraMemorySync.NormalizeSymbolID(symbolID)
    if not normalized then
        return order, false
    end

    order = order or {}
    if LuraMemorySync.OrderContainsSymbol(order, normalized) then
        return order, false
    end

    table.insert(order, normalized)
    local autoSymbol = LuraMemorySync.GetAutoCompleteSymbol(order)
    if autoSymbol then
        table.insert(order, autoSymbol)
    end
    return order, true
end
