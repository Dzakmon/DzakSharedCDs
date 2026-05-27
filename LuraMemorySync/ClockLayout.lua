LuraMemorySync = LuraMemorySync or {}

LuraMemorySync.CLOCK_LAYOUT = {
    WIDTH = 230,
    HEIGHT = 247,
    OFFSET_Y = 18,
    RADIUS = 78,
    TANK_LABEL_OFFSET = 10,
    ICON_SIZE = 42,
    SLOT_STEP_DEG = 60,
    HAND_START_Y = 14,
    CLOCK_HAND_THICKNESS = 3,
    CLOCK_TICK_THICKNESS = 2,
}

function LuraMemorySync.GetSymbolSlotXY(slotIndex)
    local cfg = LuraMemorySync.CLOCK_LAYOUT
    local angleDeg = 90 - slotIndex * cfg.SLOT_STEP_DEG
    local rad = math.rad(angleDeg)
    return cfg.RADIUS * math.cos(rad), cfg.RADIUS * math.sin(rad) + cfg.OFFSET_Y
end

function LuraMemorySync.CreateClockLayout(parent, options)
    options = options or {}
    local cfg = LuraMemorySync.CLOCK_LAYOUT

    local state = {
        parent = parent,
        layoutRoot = CreateFrame("Frame", nil, parent),
        slotIcons = {},
        slotLabels = {},
        clockHourTicks = {},
        clockHand = nil,
        bossLabel = nil,
        tankLabel = nil,
    }

    state.layoutRoot:SetSize(cfg.WIDTH, cfg.HEIGHT)
    state.layoutRoot:SetPoint("CENTER", parent, "CENTER", 0, options.offsetY or 0)

    if options.showLabels ~= false then
        state.bossLabel = state.layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        state.bossLabel:SetPoint("CENTER", state.layoutRoot, "CENTER", 0, cfg.OFFSET_Y)
        state.bossLabel:SetText("BOSS")
        state.bossLabel:SetTextColor(1, 0.15, 0.15, 1)

        state.tankLabel = state.layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        state.tankLabel:SetPoint("CENTER", state.layoutRoot, "CENTER", 0, cfg.RADIUS + cfg.TANK_LABEL_OFFSET + cfg.OFFSET_Y)
        state.tankLabel:SetText("TANK")
        state.tankLabel:SetTextColor(0.55, 0.75, 1, 1)
    end

    local function createLine(drawLayer)
        local line = state.layoutRoot:CreateTexture(nil, "ARTWORK")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:SetDrawLayer("ARTWORK", drawLayer or 1)
        line:Hide()
        return line
    end

    local function placeLine(tex, x1, y1, x2, y2, thickness)
        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then
            tex:Hide()
            return
        end
        tex:SetSize(length, thickness)
        tex:SetPoint("CENTER", state.layoutRoot, "CENTER", (x1 + x2) * 0.5, (y1 + y2) * 0.5)
        tex:SetRotation(math.atan2(dy, dx))
        tex:Show()
    end

    state.placeLine = placeLine
    state.createLine = createLine

    for i = 0, 5 do
        local tick = createLine(2)
        tick:SetVertexColor(0.55, 0.7, 0.95, 0.7)
        state.clockHourTicks[i] = tick
    end

    state.clockHand = createLine(3)
    state.clockHand:SetVertexColor(0.5, 0.78, 1, 0.95)

    return state
end

function LuraMemorySync.UpdateClockFace(state)
    if not state or not state.placeLine then
        return
    end
    local cfg = LuraMemorySync.CLOCK_LAYOUT

    for i = 0, 5 do
        local angle = math.rad(90 - i * cfg.SLOT_STEP_DEG)
        local cosA, sinA = math.cos(angle), math.sin(angle)
        local innerR = cfg.RADIUS - 5
        local outerR = cfg.RADIUS + 5
        state.placeLine(
            state.clockHourTicks[i],
            innerR * cosA, innerR * sinA + cfg.OFFSET_Y,
            outerR * cosA, outerR * sinA + cfg.OFFSET_Y,
            cfg.CLOCK_TICK_THICKNESS
        )
    end

    local tankY = cfg.RADIUS + cfg.TANK_LABEL_OFFSET + cfg.OFFSET_Y
    state.placeLine(
        state.clockHand,
        0, cfg.HAND_START_Y + cfg.OFFSET_Y,
        0, tankY - 4,
        cfg.CLOCK_HAND_THICKNESS
    )
end

function LuraMemorySync.HideClockFaceState(state)
    if not state then
        return
    end
    for _, tick in pairs(state.clockHourTicks) do
        if tick then
            tick:Hide()
        end
    end
    if state.clockHand then
        state.clockHand:Hide()
    end
end

function LuraMemorySync.HideAllClockSlots(state)
    if not state then
        return
    end
    for i = 1, 5 do
        local icon = state.slotIcons[i]
        local label = state.slotLabels[i]
        if icon then
            icon:Hide()
        end
        if label then
            label:Hide()
            label:SetText("")
        end
    end
end

function LuraMemorySync.SetClockLayoutSymbols(state, symbolIDs)
    if not state then
        return
    end
    local cfg = LuraMemorySync.CLOCK_LAYOUT
    symbolIDs = symbolIDs or {}

    LuraMemorySync.HideAllClockSlots(state)

    for i = 1, #symbolIDs do
        if i > 5 then
            break
        end
        local sym = LuraMemorySync.SymbolByID[symbolIDs[i]]
        if sym then
            local icon = state.slotIcons[i]
            local label = state.slotLabels[i]
            if not icon then
                icon = state.layoutRoot:CreateTexture(nil, "OVERLAY")
                icon:SetSize(cfg.ICON_SIZE, cfg.ICON_SIZE)
                icon:SetDrawLayer("OVERLAY", 4)
                state.slotIcons[i] = icon

                label = state.layoutRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                label:SetDrawLayer("OVERLAY", 5)
                label:SetPoint("BOTTOM", icon, "TOP", 0, 2)
                label:SetTextColor(0.9, 0.9, 1, 1)
                state.slotLabels[i] = label
            end

            local x, y = LuraMemorySync.GetSymbolSlotXY(i)
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", state.layoutRoot, "CENTER", x, y)
            label:ClearAllPoints()
            label:SetPoint("BOTTOM", icon, "TOP", 0, 2)
            label:SetText(tostring(i))
            icon:SetTexture(LuraMemorySync.GetSymbolTexture(sym))
            icon:Show()
            label:Show()
        end
    end

    LuraMemorySync.UpdateClockFace(state)
end

function LuraMemorySync.IsRaidWarningMuted()
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    return LuraMemorySyncDB.fakeRWMuted == true
end

function LuraMemorySync.SetRaidWarningMuted(muted)
    LuraMemorySyncDB = LuraMemorySyncDB or {}
    LuraMemorySyncDB.fakeRWMuted = muted
    if muted and LuraMemorySync.HideFakeRaidWarning then
        LuraMemorySync.HideFakeRaidWarning()
    end
    if LuraMemorySync.UpdateMuteButtonState then
        LuraMemorySync.UpdateMuteButtonState()
    end
end

function LuraMemorySync.ToggleRaidWarningMute()
    LuraMemorySync.SetRaidWarningMuted(not LuraMemorySync.IsRaidWarningMuted())
end
