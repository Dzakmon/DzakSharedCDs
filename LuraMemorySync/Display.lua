LuraMemorySync = LuraMemorySync or {}

local cfg = LuraMemorySync.CLOCK_LAYOUT
local FRAME_WIDTH = cfg.WIDTH
local FRAME_HEIGHT = 285
local CLEAR_BAND_HEIGHT = 38
local BASE_CONTENT_HEIGHT = FRAME_HEIGHT - CLEAR_BAND_HEIGHT
local TOP_CONTENT_INSET = 14
local AUTO_HIDE_SECONDS = 30

local MIN_FRAME_WIDTH = 160
local MIN_FRAME_HEIGHT = 200
local MAX_FRAME_WIDTH = 400
local MAX_FRAME_HEIGHT = 480
local MIN_LAYOUT_SCALE = 0.55
local MAX_LAYOUT_SCALE = 1.75

local displayFrame
local displayClockState
local closeButton
local resizeSizer
local clearButton
local muteButton
local lastShownCount = 0
local autoHideTimer

local MUTE_ICON_ON = "Interface\\ChatFrame\\UI-ChatIcon-Volume-Up"
local MUTE_ICON_OFF = "Interface\\ChatFrame\\UI-ChatIcon-Volume-Off"

local function SaveDisplayLayout()
    if not displayFrame then
        return
    end
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    local point, _, relPoint, x, y = displayFrame:GetPoint()
    LuraMemorySyncDB.displayPos = { point, relPoint, x, y }
    local w, h = displayFrame:GetSize()
    LuraMemorySyncDB.displaySize = { w, h }
end

local function ApplyDisplayScale()
    if not displayFrame or not displayClockState then
        return
    end

    local w = displayFrame:GetWidth()
    local h = displayFrame:GetHeight()
    local contentH = math.max(1, h - CLEAR_BAND_HEIGHT)
    local scale = math.min(w / FRAME_WIDTH, contentH / BASE_CONTENT_HEIGHT)
    scale = math.max(MIN_LAYOUT_SCALE, math.min(MAX_LAYOUT_SCALE, scale))

    displayClockState.layoutRoot:SetScale(scale)
    local scaledH = BASE_CONTENT_HEIGHT * scale
    local topInset = math.max(0, (contentH - scaledH) * 0.5) + TOP_CONTENT_INSET
    displayClockState.layoutRoot:ClearAllPoints()
    displayClockState.layoutRoot:SetPoint("TOP", displayFrame, "TOP", 0, -topInset)
end

local function RefreshLayoutVisuals()
    if not displayFrame or not displayFrame:IsShown() then
        return
    end
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySync.SetClockLayoutSymbols(displayClockState, LuraMemorySyncDB.lastOrder or {})
end

local function OnDisplayLayoutChanged()
    ApplyDisplayScale()
    RefreshLayoutVisuals()
end

function LuraMemorySync.UpdateMuteButtonState()
    if not muteButton then
        return
    end
    local muted = LuraMemorySync.IsRaidWarningMuted()
    local icon = muteButton.icon
    if icon then
        icon:SetTexture(muted and MUTE_ICON_OFF or MUTE_ICON_ON)
    end
    muteButton:SetAlpha(muted and 0.55 or 1)
end

local function EnsureDisplay()
    if displayFrame then
        return
    end

    displayFrame = CreateFrame("Frame", "LuraMemorySyncDisplay", UIParent, "BackdropTemplate")
    displayFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    displayFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    displayFrame:SetMovable(true)
    displayFrame:EnableMouse(true)
    displayFrame:RegisterForDrag("LeftButton")

    if displayFrame.SetResizable then
        displayFrame:SetResizable(true)
    end
    if displayFrame.SetResizeBounds then
        displayFrame:SetResizeBounds(MIN_FRAME_WIDTH, MIN_FRAME_HEIGHT, MAX_FRAME_WIDTH, MAX_FRAME_HEIGHT)
    end

    local function IsDisplayChromeMouseOver()
        return (closeButton and closeButton:IsMouseOver())
            or (resizeSizer and resizeSizer:IsMouseOver())
            or (clearButton and clearButton:IsMouseOver())
            or (muteButton and muteButton:IsMouseOver())
    end

    displayFrame:SetScript("OnDragStart", function(self, button)
        if button == "LeftButton" and not IsDisplayChromeMouseOver() then
            self:StartMoving()
        end
    end)
    displayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveDisplayLayout()
        OnDisplayLayoutChanged()
    end)
    displayFrame:SetScript("OnSizeChanged", function()
        OnDisplayLayoutChanged()
    end)
    displayFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            LuraMemorySync.SendReset()
        end
    end)
    displayFrame:Hide()

    local bg = displayFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.02, 0.06, 0.82)

    local border = displayFrame:CreateTexture(nil, "BORDER")
    border:SetHeight(2)
    border:SetPoint("TOPLEFT", displayFrame, "TOPLEFT")
    border:SetPoint("TOPRIGHT", displayFrame, "TOPRIGHT")
    border:SetColorTexture(0.45, 0.35, 0.85, 1)

    closeButton = CreateFrame("Button", nil, displayFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", displayFrame, "TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        LuraMemorySync.HideDisplay()
    end)

    displayClockState = LuraMemorySync.CreateClockLayout(displayFrame)

    clearButton = CreateFrame("Button", nil, displayFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(72, 22)
    clearButton:SetPoint("BOTTOM", displayFrame, "BOTTOM", 0, 10)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        LuraMemorySync.SendReset()
    end)
    clearButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Clear rune order", 1, 1, 1)
        GameTooltip:AddLine("Raid leader or assist only.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    muteButton = CreateFrame("Button", nil, displayFrame)
    muteButton:SetSize(24, 24)
    muteButton:SetPoint("BOTTOMRIGHT", displayFrame, "BOTTOMRIGHT", -22, 10)
    local muteIcon = muteButton:CreateTexture(nil, "ARTWORK")
    muteIcon:SetAllPoints()
    muteButton.icon = muteIcon
    muteButton:SetScript("OnClick", function()
        LuraMemorySync.ToggleRaidWarningMute()
    end)
    muteButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Raid Warning", 1, 1, 1)
        if LuraMemorySync.IsRaidWarningMuted() then
            GameTooltip:AddLine("Muted — click to unmute", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Click to mute sound + popup", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    muteButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    resizeSizer = CreateFrame("Button", nil, displayFrame)
    resizeSizer:SetSize(16, 16)
    resizeSizer:SetPoint("BOTTOMRIGHT", displayFrame, "BOTTOMRIGHT", -2, 2)
    resizeSizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeSizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeSizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeSizer:SetScript("OnMouseDown", function()
        if displayFrame.StartSizing then
            displayFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeSizer:SetScript("OnMouseUp", function()
        displayFrame:StopMovingOrSizing()
        SaveDisplayLayout()
        OnDisplayLayoutChanged()
    end)

    ApplyDisplayScale()
    LuraMemorySync.UpdateClearButtonState()
    LuraMemorySync.UpdateMuteButtonState()
end

function LuraMemorySync.UpdateClearButtonState()
    if not clearButton then
        return
    end
    if LuraMemorySync.CanClearOrder() then
        clearButton:Enable()
        clearButton:SetAlpha(1)
    else
        clearButton:Disable()
        clearButton:SetAlpha(0.45)
    end
end

local function RestoreDisplayLayout()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    if not displayFrame then
        return
    end

    local size = LuraMemorySyncDB.displaySize
    if size and size[1] and size[2] then
        local w = math.max(MIN_FRAME_WIDTH, math.min(MAX_FRAME_WIDTH, size[1]))
        local h = math.max(MIN_FRAME_HEIGHT, math.min(MAX_FRAME_HEIGHT, size[2]))
        displayFrame:SetSize(w, h)
    end

    local pos = LuraMemorySyncDB.displayPos
    if pos then
        displayFrame:ClearAllPoints()
        displayFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    ApplyDisplayScale()
end

function LuraMemorySync.CancelAutoHideTimer()
    if autoHideTimer then
        autoHideTimer:Cancel()
        autoHideTimer = nil
    end
end

function LuraMemorySync.ScheduleAutoHide()
    LuraMemorySync.CancelAutoHideTimer()
    if not C_Timer or not C_Timer.NewTimer then
        return
    end
    autoHideTimer = C_Timer.NewTimer(AUTO_HIDE_SECONDS, function()
        autoHideTimer = nil
        LuraMemorySync.HideDisplay()
    end)
end

function LuraMemorySync.RefreshDisplayIfVisible()
    if not displayFrame or not displayFrame:IsShown() or not displayClockState then
        return
    end
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySync.SetClockLayoutSymbols(displayClockState, LuraMemorySyncDB.lastOrder or {})
    LuraMemorySync.UpdateClearButtonState()
    LuraMemorySync.UpdateMuteButtonState()
end

function LuraMemorySync.ClearDisplayIfVisible()
    if not displayFrame or not displayFrame:IsShown() or not displayClockState then
        return
    end
    LuraMemorySync.HideAllClockSlots(displayClockState)
    LuraMemorySync.UpdateClockFace(displayClockState)
    LuraMemorySync.UpdateClearButtonState()
end

function LuraMemorySync.ShowDisplay(symbolIDs, options)
    EnsureDisplay()
    symbolIDs = symbolIDs or {}
    options = options or {}

    LuraMemorySync.SetClockLayoutSymbols(displayClockState, symbolIDs)
    lastShownCount = #symbolIDs

    if options.scheduleAutoHide and lastShownCount == 1 then
        LuraMemorySync.ScheduleAutoHide()
    end

    LuraMemorySync.UpdateClearButtonState()
    LuraMemorySync.UpdateMuteButtonState()
    displayFrame:Show()
end

function LuraMemorySync.ClearRoundDisplay()
    LuraMemorySync.CancelAutoHideTimer()
    lastShownCount = 0
    EnsureDisplay()
    LuraMemorySync.HideAllClockSlots(displayClockState)
    LuraMemorySync.UpdateClockFace(displayClockState)
    LuraMemorySync.UpdateClearButtonState()
    LuraMemorySync.UpdateMuteButtonState()
    displayFrame:Show()
end

function LuraMemorySync.HideDisplay()
    LuraMemorySync.CancelAutoHideTimer()
    lastShownCount = 0
    if displayFrame then
        LuraMemorySync.HideClockFaceState(displayClockState)
        displayFrame:Hide()
    end
end

function LuraMemorySync.ShowLayout()
    EnsureDisplay()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    local order = LuraMemorySyncDB.lastOrder
    if order and #order > 0 then
        LuraMemorySync.ShowDisplay(order)
    else
        LuraMemorySync.ClearRoundDisplay()
    end
end

function LuraMemorySync.TestLayout()
    if #LuraMemorySync.Symbols == 0 then
        LuraMemorySync.ResolveIconPaths()
    end
    local test = {}
    for i, sym in ipairs(LuraMemorySync.Symbols) do
        test[i] = sym.id
    end
    LuraMemorySync.ShowDisplay(test)
end

function LuraMemorySync.InitDisplay()
    EnsureDisplay()
    RestoreDisplayLayout()
end
