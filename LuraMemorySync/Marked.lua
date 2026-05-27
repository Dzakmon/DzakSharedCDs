LuraMemorySync = LuraMemorySync or {}

local DARK_RUNE_NAME = "Dark Rune"
local MAX_MARKED = 5
local ROW_H = 18
local ROUND_TIMEOUT = 18

local markedPlayers = {}
local lastMarkTime = 0
local scanTicker = nil

local markedFrame
local rows = {}

local function EnsureMarkedUI()
    if markedFrame then
        return
    end

    markedFrame = CreateFrame("Frame", "LuraMemorySyncMarked", UIParent, "BackdropTemplate")
    markedFrame:SetSize(170, 40)
    markedFrame:SetPoint("LEFT", "LuraMemorySyncDisplay", "RIGHT", 10, 0)
    markedFrame:SetMovable(true)
    markedFrame:EnableMouse(true)
    markedFrame:RegisterForDrag("LeftButton")
    markedFrame:SetScript("OnDragStart", markedFrame.StartMoving)
    markedFrame:SetScript("OnDragStop", markedFrame.StopMovingOrSizing)
    markedFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            markedFrame:Hide()
        end
    end)
    markedFrame:Hide()

    local bg = markedFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.03, 0.1, 0.85)

    local title = markedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", markedFrame, "TOP", 0, -8)
    title:SetText("Dark Rune")
    title:SetTextColor(0.75, 0.55, 1, 1)

    for i = 1, MAX_MARKED do
        local row = CreateFrame("Frame", nil, markedFrame)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", markedFrame, "TOPLEFT", 8, -(24 + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", markedFrame, "TOPRIGHT", -8, -(24 + (i - 1) * ROW_H))

        local numLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        numLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
        numLabel:SetWidth(16)
        numLabel:SetJustifyH("LEFT")
        row.numLabel = numLabel

        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLabel:SetPoint("LEFT", row, "LEFT", 18, 0)
        nameLabel:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        nameLabel:SetJustifyH("LEFT")
        row.nameLabel = nameLabel

        row:Hide()
        rows[i] = row
    end
end

local function RefreshMarked()
    EnsureMarkedUI()
    local count = #markedPlayers

    for i = 1, MAX_MARKED do
        rows[i]:Hide()
    end

    for i, name in ipairs(markedPlayers) do
        rows[i].numLabel:SetText(i .. ".")
        rows[i].nameLabel:SetText(name)
        rows[i]:Show()
    end

    if count > 0 then
        markedFrame:SetHeight(28 + count * ROW_H + 8)
        markedFrame:Show()
    else
        markedFrame:Hide()
    end
end

local function ClearMarked()
    markedPlayers = {}
    lastMarkTime = 0
    if markedFrame then
        markedFrame:Hide()
    end
end

local function UnitHasDarkRune(unit)
    if not UnitExists(unit) then
        return false
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        return C_UnitAuras.GetAuraDataBySpellName(unit, DARK_RUNE_NAME, "HARMFUL") ~= nil
    end
    local ok, aura = pcall(AuraUtil.FindAuraByName, DARK_RUNE_NAME, unit, "HARMFUL")
    return ok and aura ~= nil
end

local function OnPlayerMarked(shortName)
    local now = GetTime()
    if now - lastMarkTime > ROUND_TIMEOUT then
        markedPlayers = {}
    end
    lastMarkTime = now

    for _, existing in ipairs(markedPlayers) do
        if existing == shortName then
            return
        end
    end

    table.insert(markedPlayers, shortName)
    RefreshMarked()

    if #markedPlayers == 1 then
        LuraMemorySync.OnNewDirgeRound()
    end
end

local function ScanGroup()
    if UnitHasDarkRune("player") then
        local shortName = LuraMemorySync.ShortName(UnitName("player"))
        if shortName then
            OnPlayerMarked(shortName)
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitHasDarkRune(unit) then
                local shortName = LuraMemorySync.ShortName(UnitName(unit))
                if shortName then
                    OnPlayerMarked(shortName)
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitHasDarkRune(unit) then
                local shortName = LuraMemorySync.ShortName(UnitName(unit))
                if shortName then
                    OnPlayerMarked(shortName)
                end
            end
        end
    end
end

function LuraMemorySync.GetMarkedPlayers()
    return markedPlayers
end

function LuraMemorySync.StartMarkedScan()
    if scanTicker then
        return
    end
    scanTicker = C_Timer.NewTicker(0.5, ScanGroup)
end

function LuraMemorySync.StopMarkedScan()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
    ClearMarked()
end

function LuraMemorySync.OnNewDirgeRound()
    LuraMemorySync.BeginNewRound({ broadcast = LuraMemorySync.CanBroadcastOrder() })
end
