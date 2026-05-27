LuraMemorySync = LuraMemorySync or {}

local ADDON_ICONS = "Interface\\AddOns\\LuraMemorySync\\Media\\Icons\\"

-- Reihenfolge = LMS Rune 1..5 (entspricht NSRT „Create Rune-Macros“)
LuraMemorySync.RUNE_DEFINITIONS = {
    { id = "1", file = "inv_belt_39a.tga", legacyFileDataID = 7242384 },
    { id = "2", file = "inv_bracer_45green.tga", legacyFileDataID = 134635 },
    { id = "3", file = "inv_pants_cloth_38.tga", legacyFileDataID = 340528 },
    { id = "4", file = "inv_pants_leather_10.tga", legacyFileDataID = 351033 },
    { id = "5", file = "ui_majorfaction_rocket.tga", legacyFileDataID = 236903 },
}

LuraMemorySync.Symbols = {}
LuraMemorySync.SymbolByID = {}

function LuraMemorySync.ResolveIconPaths()
    wipe(LuraMemorySync.Symbols)
    wipe(LuraMemorySync.SymbolByID)

    for index, def in ipairs(LuraMemorySync.RUNE_DEFINITIONS) do
        local texture = ADDON_ICONS .. def.file
        local macroIcon = texture
        if GetFileIDFromPath then
            local fileId = GetFileIDFromPath(texture)
            if fileId then
                macroIcon = tostring(fileId)
            end
        elseif C_Texture and C_Texture.GetFileIDFromPath then
            local fileId = C_Texture.GetFileIDFromPath(texture)
            if fileId then
                macroIcon = tostring(fileId)
            end
        end

        local sym = {
            id = def.id,
            label = def.id,
            macroIndex = index,
            texture = texture,
            macroIcon = macroIcon,
            legacyFileDataID = def.legacyFileDataID,
        }
        table.insert(LuraMemorySync.Symbols, sym)
        LuraMemorySync.SymbolByID[def.id] = sym
        if def.legacyFileDataID then
            LuraMemorySync.SymbolByID[tostring(def.legacyFileDataID)] = sym
        end
    end
end

LuraMemorySync.SYMBOL_COUNT_BY_DIFFICULTY = {
    [14] = 3,
    [15] = 4,
    [16] = 5,
}

function LuraMemorySync.GetRequiredSymbolCount()
    local _, _, difficultyID = GetInstanceInfo()
    return LuraMemorySync.SYMBOL_COUNT_BY_DIFFICULTY[difficultyID] or 5
end

function LuraMemorySync.GetSymbolTexture(sym)
    if not sym then
        return nil
    end
    return sym.texture
end

function LuraMemorySync.IconsAreBundled()
    return #LuraMemorySync.RUNE_DEFINITIONS == 5
end
