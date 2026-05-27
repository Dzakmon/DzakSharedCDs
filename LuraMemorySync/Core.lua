LuraMemorySync = LuraMemorySync or {}

local eventFrame = CreateFrame("Frame")

local function PrintHelp()
    print("|cff66ccffLuraMemorySync|r Befehle:")
    print("  /lms show    — Layout-Fenster einblenden (nur auf Wunsch)")
    print("  /lms test    — alle 5 Positionen mit Test-Symbolen")
    print("  /lms hide    — Layout verstecken")
    print("  /lms macro   — Macros für alle 5 Symbole + Send/Undo/Reset")
    print("  /lms send    — aktuelle Klick-Reihenfolge an den Raid senden")
    print("  /lms undo    — letztes Symbol entfernen")
    print("  /lms reset   — Anzeige + Sync zurücksetzen")
    print("  /lms force   — ohne RL/Assist senden")
    print("  /lms ver     — wer hat das Addon?")
    print("  /lms last    — letzte Reihenfolge erneut senden")
    print("  /lms rw      — Fake Raid Warning testen")
    print("  /lms rw off  — Fake RW aus | /lms rw on — an")
    print("  /lms mute    — Raid Warning stumm schalten")
end

local function OnAddonLoaded(name)
    if name ~= "LuraMemorySync" then
        return
    end

    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySync.ResolveIconPaths()
    LuraMemorySync.RegisterCommPrefix()
    LuraMemorySync.InitDisplay()
    LuraMemorySync.InitFakeRaidWarning()
    LuraMemorySync.BroadcastVersion()

end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == "LURAMEMSYNC" then
            LuraMemorySync.OnAddonMessage(message, sender)
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        LuraMemorySync.BroadcastVersion()
        LuraMemorySync.UpdateClearButtonState()
    elseif event == "ENCOUNTER_START" then
        LuraMemorySync.BeginNewRound({ broadcast = false })
        LuraMemorySync.HideDisplay()
        if LuraMemorySync.HideFakeRaidWarning then
            LuraMemorySync.HideFakeRaidWarning()
        end
        LuraMemorySync.StartMarkedScan()
    elseif event == "ENCOUNTER_END" then
        LuraMemorySync.StopMarkedScan()
        LuraMemorySync.HideDisplay()
        if LuraMemorySync.HideFakeRaidWarning then
            LuraMemorySync.HideFakeRaidWarning()
        end
    end
end)

SLASH_LURAMEMORYSYNC1 = "/lms"
SLASH_LURAMEMORYSYNC2 = "/luramemory"
SlashCmdList["LURAMEMORYSYNC"] = function(msg)
    local arg = (msg or ""):lower():match("^%s*(%S*)")

    if arg == "" or arg == "help" then
        PrintHelp()
    elseif arg == "show" or arg == "layout" then
        LuraMemorySync.ShowLayout()
    elseif arg == "test" then
        LuraMemorySync.TestLayout()
    elseif arg == "hide" then
        LuraMemorySync.HideDisplay()
    elseif arg == "macro" or arg == "macros" then
        LuraMemorySync.CreateSymbolMacros()
    elseif arg == "send" then
        LuraMemorySync.SendCurrentBuild()
    elseif arg == "undo" then
        LuraMemorySync_UndoSymbol()
    elseif arg == "reset" then
        LuraMemorySync_ResetAll()
    elseif arg == "force" then
        LuraMemorySync.forceMode = true
    elseif arg == "ver" or arg == "version" then
        LuraMemorySync.RequestVersions()
        C_Timer.After(1, function()
            local lines = {}
            for name, version in pairs(LuraMemorySync.playerVersions) do
                table.insert(lines, name .. " v" .. version)
            end
            table.sort(lines)
            print("|cff66ccffLuraMemorySync|r " .. (#lines > 0 and table.concat(lines, ", ") or "Keine Antworten."))
        end)
    elseif arg == "last" then
        LuraMemorySyncDB = LuraMemorySyncDB or {}
        local last = LuraMemorySyncDB.history and LuraMemorySyncDB.history[1]
        if not last then
            print("|cffff6600LuraMemorySync|r Keine History.")
            return
        end
        LuraMemorySync.SendOrder(last, { force = LuraMemorySync.forceMode })
    elseif arg == "mute" then
        local toggle = (msg or ""):lower():match("%s+(%S+)")
        if toggle == "off" or toggle == "0" then
            LuraMemorySync.SetRaidWarningMuted(false)
            print("|cff66ccffLuraMemorySync|r Raid Warning: |cff20ff20an|r")
        elseif toggle == "on" or toggle == "1" then
            LuraMemorySync.SetRaidWarningMuted(true)
            print("|cffff6600LuraMemorySync|r Raid Warning: |cffff2020stumm|r")
        else
            LuraMemorySync.ToggleRaidWarningMute()
            print("|cff66ccffLuraMemorySync|r Raid Warning: "
                .. (LuraMemorySync.IsRaidWarningMuted() and "|cffff2020stumm|r" or "|cff20ff20an|r"))
        end
        LuraMemorySync.UpdateMuteButtonState()
    elseif arg == "rw" or arg == "raidwarning" then
        local toggle = (msg or ""):lower():match("%s+(%S+)")
        if toggle == "off" or toggle == "0" then
            LuraMemorySync.SetFakeRaidWarningEnabled(false)
            print("|cff66ccffLuraMemorySync|r Fake Raid Warning: |cffff2020aus|r")
        elseif toggle == "on" or toggle == "1" then
            LuraMemorySync.SetFakeRaidWarningEnabled(true)
            print("|cff66ccffLuraMemorySync|r Fake Raid Warning: |cff20ff20an|r")
        else
            LuraMemorySyncDB = LuraMemorySyncDB or {}
            local order = LuraMemorySyncDB.lastOrder
            if not order or #order == 0 then
                if #LuraMemorySync.Symbols == 0 then
                    LuraMemorySync.ResolveIconPaths()
                end
                order = {}
                for _, sym in ipairs(LuraMemorySync.Symbols) do
                    table.insert(order, sym.id)
                end
            end
            LuraMemorySync.ShowFakeRaidWarning(order)
        end
    else
        PrintHelp()
    end
end
