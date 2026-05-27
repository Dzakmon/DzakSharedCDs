LuraMemorySync = LuraMemorySync or {}

local FAKE_RW_WIDTH = 230
local FAKE_RW_HEIGHT = 265
local FAKE_RW_DURATION = 15

local fakeRWFrame
local fakeRWClockState
local fakeRWHideTimer

local function FakeRWEnabled()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    if LuraMemorySyncDB.fakeRWEnabled == nil then
        LuraMemorySyncDB.fakeRWEnabled = true
    end
    return LuraMemorySyncDB.fakeRWEnabled
end

local function SaveFakeRWPosition()
    if not fakeRWFrame then
        return
    end
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    local point, _, relPoint, x, y = fakeRWFrame:GetPoint()
    LuraMemorySyncDB.fakeRWPos = { point, relPoint, x, y }
end

local function RestoreFakeRWPosition()
    if not fakeRWFrame then
        return
    end
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    local pos = LuraMemorySyncDB.fakeRWPos
    if pos then
        fakeRWFrame:ClearAllPoints()
        fakeRWFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

local function PlayRaidWarningSound()
    if LuraMemorySync.IsRaidWarningMuted() then
        return
    end
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING)
        return
    end
    pcall(PlaySound, 8959, "Master")
end

local function EnsureFakeRWFrame()
    if fakeRWFrame then
        return
    end

    fakeRWFrame = CreateFrame("Frame", "LuraMemorySyncFakeRW", UIParent)
    fakeRWFrame:SetSize(FAKE_RW_WIDTH, FAKE_RW_HEIGHT)
    fakeRWFrame:SetPoint("TOP", UIParent, "TOP", 0, -88)
    fakeRWFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    fakeRWFrame:SetFrameLevel(200)
    fakeRWFrame:SetMovable(true)
    fakeRWFrame:EnableMouse(true)
    fakeRWFrame:RegisterForDrag("LeftButton")
    fakeRWFrame:SetScript("OnDragStart", fakeRWFrame.StartMoving)
    fakeRWFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFakeRWPosition()
    end)
    fakeRWFrame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(fakeRWFrame, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Raid Warning (L'ura Memory)", 1, 0.82, 0.2)
        GameTooltip:AddLine("Drag to move", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    fakeRWFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    fakeRWFrame:Hide()

    local bg = fakeRWFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.06, 0.88)

    local border = fakeRWFrame:CreateTexture(nil, "BORDER")
    border:SetHeight(3)
    border:SetPoint("TOPLEFT", fakeRWFrame, "TOPLEFT")
    border:SetPoint("TOPRIGHT", fakeRWFrame, "TOPRIGHT")
    border:SetColorTexture(1, 0.72, 0.08, 1)

    local borderBottom = fakeRWFrame:CreateTexture(nil, "BORDER")
    borderBottom:SetHeight(1)
    borderBottom:SetPoint("BOTTOMLEFT", fakeRWFrame, "BOTTOMLEFT")
    borderBottom:SetPoint("BOTTOMRIGHT", fakeRWFrame, "BOTTOMRIGHT")
    borderBottom:SetColorTexture(1, 0.55, 0.05, 0.7)

    fakeRWClockState = LuraMemorySync.CreateClockLayout(fakeRWFrame, { offsetY = 4 })
end

function LuraMemorySync.HideFakeRaidWarning()
    if fakeRWHideTimer then
        fakeRWHideTimer:Cancel()
        fakeRWHideTimer = nil
    end
    if fakeRWFrame then
        fakeRWFrame:Hide()
        fakeRWFrame:SetAlpha(1)
    end
    if fakeRWClockState then
        LuraMemorySync.HideAllClockSlots(fakeRWClockState)
        LuraMemorySync.HideClockFaceState(fakeRWClockState)
    end
end

function LuraMemorySync.ShowFakeRaidWarning(symbolIDs)
    if not FakeRWEnabled() then
        return
    end
    if LuraMemorySync.IsRaidWarningMuted() then
        return
    end
    if not symbolIDs or #symbolIDs == 0 then
        return
    end

    EnsureFakeRWFrame()
    RestoreFakeRWPosition()
    LuraMemorySync.SetClockLayoutSymbols(fakeRWClockState, symbolIDs)

    PlayRaidWarningSound()
    fakeRWFrame:SetAlpha(1)
    fakeRWFrame:Show()

    if fakeRWHideTimer then
        fakeRWHideTimer:Cancel()
    end
    if C_Timer and C_Timer.NewTimer then
        fakeRWHideTimer = C_Timer.NewTimer(FAKE_RW_DURATION, function()
            fakeRWHideTimer = nil
            LuraMemorySync.HideFakeRaidWarning()
        end)
    end
end

function LuraMemorySync.MaybeShowFakeRaidWarning(symbolIDs)
    if not symbolIDs then
        return
    end
    if LuraMemorySync.IsRaidWarningMuted() then
        return
    end
    local required = LuraMemorySync.GetRequiredSymbolCount()
    if #symbolIDs < required then
        return
    end
    LuraMemorySync.ShowFakeRaidWarning(symbolIDs)
end

function LuraMemorySync.InitFakeRaidWarning()
    EnsureFakeRWFrame()
    RestoreFakeRWPosition()
end

function LuraMemorySync.SetFakeRaidWarningEnabled(enabled)
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySyncDB.fakeRWEnabled = enabled
    if not enabled then
        LuraMemorySync.HideFakeRaidWarning()
    end
end
