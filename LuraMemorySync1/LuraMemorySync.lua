local ADDON_NAME  = "LuraMemorySync"
local PREFIX      = "LuraMemorySync"
local TEX         = "Interface\\AddOns\\LuraMemorySync\\Textures\\"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FLAT        = "Interface\\Buttons\\WHITE8x8"

local LANG = (GetLocale() == "frFR") and "fr" or "en"

local L = {
    fr = {
        title        = "Lura Memory Sync",
        boss         = "BOSS",
        rw_header    = "-- Alerte Raid --",
        btn_clear    = "Effacer",
        btn_send     = "Envoyer",
        btn_say      = "/DIRE",
        btn_rw       = "AR",
        btn_combo    = "DIRE  +  Alerte Raid",
        tip_resize   = "Glisser pour redimensionner",
        tip_send     = "Envoyer le schéma à tous les utilisateurs de l'addon\n(fonctionne en combat)",
        tip_say      = "Envoyer le schéma en /dire\n(visible par tous les joueurs proches)",
        tip_rw       = "Alerte Raid\nAffiché à l'écran pour tous les utilisateurs de l'addon",
        tip_combo    = "Envoyer en /dire ET en Alerte Raid simultanément",
        say_prefix   = "] dit : ",
        empty        = "(vide)",
        loaded       = "chargé ! Tapez |cffffd700/ums|r pour ouvrir.",
        sym_diamond  = "Losange",
        sym_triangle = "Triangle",
        sym_circle   = "Rond",
        sym_cross    = "Croix",
        sym_t        = "T",
    },
    en = {
        title        = "Lura Memory Sync",
        boss         = "BOSS",
        rw_header    = "-- Raid Warning --",
        btn_clear    = "Clear",
        btn_send     = "Send",
        btn_say      = "/SAY",
        btn_rw       = "RW",
        btn_combo    = "SAY  +  Raid Alert",
        tip_resize   = "Drag to resize",
        tip_send     = "Send pattern to all addon users\n(works in combat)",
        tip_say      = "Send pattern in /say\n(visible to all nearby players)",
        tip_rw       = "Raid Warning\nDisplayed on screen for all addon users",
        tip_combo    = "Send in /say AND Raid Alert simultaneously",
        say_prefix   = "] says: ",
        empty        = "(empty)",
        loaded       = "loaded! Type |cffffd700/ums|r to open.",
        sym_diamond  = "Diamond",
        sym_triangle = "Triangle",
        sym_circle   = "Circle",
        sym_cross    = "Cross",
        sym_t        = "T",
    },
}

local SYMS = {
    { k="1", langKey="diamond",  tex=TEX.."diamond.png",  r=0.7, g=0.0, b=1.0 },
    { k="2", langKey="triangle", tex=TEX.."triangle.png", r=0.0, g=1.0, b=0.2 },
    { k="3", langKey="circle",   tex=TEX.."circle.png",   r=1.0, g=0.5, b=0.0 },
    { k="4", langKey="cross",    tex=TEX.."cross.png",    r=1.0, g=0.1, b=0.1 },
    { k="5", langKey="t",        tex=TEX.."t.png",        r=1.0, g=0.9, b=0.0 },
}

local MAX       = 5
local state     = {}
local arcIcons  = {}
local arcBgs    = {}
local arcRings  = {}
local autoAdded = false

local R     = 80
local slots = {}
for i = 1, MAX do
    local a  = math.rad((i - 1) / (MAX - 1) * 180)
    slots[i] = { x = R * math.cos(a), y = -R * math.sin(a) }
end

local RW_R     = 110
local RW_ICON  = 52
local RW_ARC_Y = -85
local RW_SLOTS = {}
for i = 1, MAX do
    local a     = math.rad((i - 1) / (MAX - 1) * 180)
    RW_SLOTS[i] = { x = RW_R * math.cos(a), y = -RW_R * math.sin(a) }
end

local ui = {}

local function applyLocale()
    local t = L[LANG]
    if ui.title     then ui.title:SetText(t.title) end
    if ui.bossLabel then ui.bossLabel:SetText("|cffff2222"..t.boss.."|r") end
    if ui.clr       then ui.clr:SetText(t.btn_clear) end
    if ui.snd       then ui.snd:SetText(t.btn_send) end
    if ui.say       then ui.say:SetText(t.btn_say) end
    if ui.rw        then ui.rw:SetText(t.btn_rw) end
    if ui.combo     then ui.combo:SetText(t.btn_combo) end
    if ui.rwHeader  then ui.rwHeader:SetText("|cffff4400"..t.rw_header.."|r") end
    if ui.rwBossLbl then ui.rwBossLbl:SetText("|cffff2222"..t.boss.."|r") end
    if ui.langBtn   then
        ui.langBtn:SetText(LANG == "fr" and "|cff88ccff[FR]|r  EN" or "FR  |cff88ccff[EN]|r")
    end
end

local function applyCircularMask(parent, tex)
    local mask = parent:CreateMaskTexture()
    mask:SetAllPoints(tex)
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask)
end

local function getSymColor(k)
    for _, sym in ipairs(SYMS) do
        if sym.k == k then return sym.r, sym.g, sym.b end
    end
    return 0.55, 0.30, 0.85
end

local function saveFramePos(frame, key)
    LuraMemorySyncDB[key] = {
        x = frame:GetLeft() + frame:GetWidth() / 2 - UIParent:GetWidth() / 2,
        y = frame:GetBottom() + frame:GetHeight() / 2 - UIParent:GetHeight() / 2,
    }
end

local function restoreFramePos(frame, key)
    local p = LuraMemorySyncDB[key]
    if p then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    end
end

local function redraw()
    for i = 1, MAX do arcBgs[i]:Hide() end
    for i, s in ipairs(state) do
        arcIcons[i]:SetTexture(s.tex)
        local r, g, b = getSymColor(s.k)
        if autoAdded and i == #state then
            arcIcons[i]:SetVertexColor(0.55, 0.55, 0.55, 1)
            arcRings[i]:SetColorTexture(r, g, b, 0.4)
        else
            arcIcons[i]:SetVertexColor(1, 1, 1, 1)
            arcRings[i]:SetColorTexture(r, g, b, 0.85)
        end
        arcBgs[i]:Show()
    end
end

local function serialize()
    local t = {}
    for _, s in ipairs(state) do t[#t+1] = s.k end
    return table.concat(t, ",")
end

local function deserialize(str)
    local decoded = {}
    if not str or str == "" then return decoded end
    for k in str:gmatch("[^,]+") do
        for _, sym in ipairs(SYMS) do
            if sym.k == k then
                decoded[#decoded+1] = { k=sym.k, tex=sym.tex }
                break
            end
        end
    end
    return decoded
end

local function buildPatternTextPlain()
    local parts = {}
    for i = #state, 1, -1 do
        local s = state[i]
        for _, sym in ipairs(SYMS) do
            if sym.k == s.k then
                parts[#parts+1] = L[LANG]["sym_"..sym.langKey]
                break
            end
        end
    end
    return #parts > 0 and table.concat(parts, " < ") or L[LANG].empty
end

local sayFrame      = nil
local sayFrameIcons = {}
local sayNameLabel  = nil

local function showSayIcons(senderName, symState)
    if not sayFrame then
        local iconSz, gap = 34, 8
        local totalW = MAX * iconSz + (MAX - 1) * gap
        local fW = math.max(totalW + 20, 220)
        sayFrame = CreateFrame("Frame", "LuraMemorySyncSayFrame", UIParent, "BackdropTemplate")
        sayFrame:SetSize(fW, 60)
        sayFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 6, 168)
        restoreFramePos(sayFrame, "sayPos")
        sayFrame:SetFrameStrata("HIGH")
        sayFrame:SetMovable(true)
        sayFrame:EnableMouse(true)
        sayFrame:RegisterForDrag("LeftButton")
        sayFrame:SetScript("OnDragStart", sayFrame.StartMoving)
        sayFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            saveFramePos(self, "sayPos")
        end)
        sayFrame:SetBackdrop({
            bgFile   = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets   = { left=1, right=1, top=1, bottom=1 },
        })
        sayFrame:SetBackdropColor(0.04, 0.0, 0.13, 0.88)
        sayFrame:SetBackdropBorderColor(0.5, 0.15, 0.9, 0.9)
        sayNameLabel = sayFrame:CreateFontString(nil, "OVERLAY")
        sayNameLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        sayNameLabel:SetPoint("TOP", sayFrame, "TOP", 0, -6)
        local startX = -(totalW / 2) + iconSz / 2
        for i = 1, MAX do
            local slot = CreateFrame("Frame", nil, sayFrame)
            slot:SetSize(iconSz, iconSz)
            slot:SetPoint("BOTTOM", sayFrame, "BOTTOM", startX + (i - 1) * (iconSz + gap), 5)
            slot:Hide()
            local ring = slot:CreateTexture(nil, "BACKGROUND")
            ring:SetAllPoints(slot)
            ring:SetColorTexture(0.55, 0.30, 0.85, 0.75)
            applyCircularMask(slot, ring)
            local inner = slot:CreateTexture(nil, "BORDER")
            inner:SetSize(iconSz - 5, iconSz - 5)
            inner:SetPoint("CENTER")
            inner:SetColorTexture(0.07, 0.03, 0.15, 0.92)
            applyCircularMask(slot, inner)
            local tex = slot:CreateTexture(nil, "ARTWORK")
            tex:SetSize(iconSz - 9, iconSz - 9)
            tex:SetPoint("CENTER")
            applyCircularMask(slot, tex)
            sayFrameIcons[i] = { slot = slot, tex = tex, ring = ring }
        end
        for i = 1, MAX - 1 do
            local arr = sayFrame:CreateFontString(nil, "OVERLAY")
            arr:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            arr:SetPoint("BOTTOM", sayFrame, "BOTTOM", startX + (i - 0.5) * (iconSz + gap), 14)
            arr:SetText("<")
            arr:SetTextColor(0.5, 0.3, 0.8, 0.8)
        end
    end
    local name = senderName and senderName:match("^([^-]+)") or UnitName("player")
    local parts = {}
    for i = #symState, 1, -1 do
        local s = symState[i]
        for _, sym in ipairs(SYMS) do
            if sym.k == s.k then
                parts[#parts + 1] = "|T" .. sym.tex .. ":18:18|t"
                break
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffaa44ff[UMS]|r |cffffffff" .. name .. "|r" .. L[LANG].say_prefix
        .. (#parts > 0 and table.concat(parts, " < ") or L[LANG].empty)
    )
    if sayNameLabel then
        sayNameLabel:SetText("|cffaa44ff[UMS]|r |cffffd700" .. name .. "|r" .. L[LANG].say_prefix)
    end
    for i = 1, MAX do sayFrameIcons[i].slot:Hide() end
    for i, s in ipairs(symState) do
        if sayFrameIcons[i] then
            local r, g, b = getSymColor(s.k)
            sayFrameIcons[i].ring:SetColorTexture(r, g, b, 0.85)
            sayFrameIcons[i].tex:SetTexture(s.tex)
            sayFrameIcons[i].tex:SetVertexColor(1, 1, 1, 1)
            sayFrameIcons[i].slot:Show()
        end
    end
    UIFrameFadeIn(sayFrame, 0.25, 0, 1)
    C_Timer.After(7, function() if sayFrame then UIFrameFadeOut(sayFrame, 0.5, 1, 0) end end)
end

local function sendSayIcons()
    local msg = "SAYICO:" .. serialize()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    else
        showSayIcons(UnitName("player"), state)
    end
end

local function sendState()
    local msg = serialize()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, "S:"..msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, "S:"..msg, "PARTY")
    end
end

local function sendClear()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, "CLEAR", "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, "CLEAR", "PARTY")
    end
end

local fakeRWFrame = nil
local fakeRWIcons = {}
local fakeRWNums  = {}
local fakeRWBgs   = {}
local fakeRWRings = {}

local function showFakeRW(symbols)
    if not fakeRWFrame then
        fakeRWFrame = CreateFrame("Frame", "LuraMemorySyncRW", UIParent, "BackdropTemplate")
        fakeRWFrame:SetSize(360, 255)
        fakeRWFrame:SetPoint("TOP", UIParent, "TOP", 0, -80)
        restoreFramePos(fakeRWFrame, "rwPos")
        fakeRWFrame:SetFrameStrata("DIALOG")
        fakeRWFrame:SetMovable(true)
        fakeRWFrame:EnableMouse(true)
        fakeRWFrame:RegisterForDrag("LeftButton")
        fakeRWFrame:SetScript("OnDragStart", fakeRWFrame.StartMoving)
        fakeRWFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            saveFramePos(self, "rwPos")
        end)
        fakeRWFrame:SetBackdrop({
            bgFile   = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
            insets   = { left=1, right=1, top=1, bottom=1 },
        })
        fakeRWFrame:SetBackdropColor(0.05, 0.0, 0.12, 0.78)
        fakeRWFrame:SetBackdropBorderColor(0.8, 0.2, 0.0, 0.75)

        local hdr = fakeRWFrame:CreateFontString(nil, "OVERLAY")
        hdr:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        hdr:SetPoint("TOP", fakeRWFrame, "TOP", 0, -6)
        hdr:SetText("|cffff4400"..L[LANG].rw_header.."|r")
        ui.rwHeader = hdr

        local bossLbl = fakeRWFrame:CreateFontString(nil, "OVERLAY")
        bossLbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        bossLbl:SetPoint("CENTER", fakeRWFrame, "TOP", 0, RW_ARC_Y)
        bossLbl:SetText("|cffff2222"..L[LANG].boss.."|r")
        ui.rwBossLbl = bossLbl

        for i = 1, MAX do
            local slot = CreateFrame("Frame", nil, fakeRWFrame)
            slot:SetSize(RW_ICON, RW_ICON)
            slot:SetPoint("CENTER", fakeRWFrame, "TOP",
                RW_SLOTS[i].x, RW_ARC_Y + RW_SLOTS[i].y)
            slot:Hide()
            fakeRWBgs[i] = slot

            local ring = slot:CreateTexture(nil, "BACKGROUND")
            ring:SetAllPoints(slot)
            ring:SetColorTexture(0.55, 0.30, 0.85, 0.85)
            applyCircularMask(slot, ring)
            fakeRWRings[i] = ring

            local inner = slot:CreateTexture(nil, "BORDER")
            inner:SetSize(RW_ICON - 5, RW_ICON - 5)
            inner:SetPoint("CENTER")
            inner:SetColorTexture(0.07, 0.03, 0.15, 0.92)
            applyCircularMask(slot, inner)

            local tex = slot:CreateTexture(nil, "ARTWORK")
            tex:SetSize(RW_ICON - 9, RW_ICON - 9)
            tex:SetPoint("CENTER")
            applyCircularMask(slot, tex)
            fakeRWIcons[i] = tex

            local num = fakeRWFrame:CreateFontString(nil, "OVERLAY")
            num:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            num:SetPoint("CENTER", fakeRWFrame, "TOP",
                RW_SLOTS[i].x, RW_ARC_Y + RW_SLOTS[i].y - RW_ICON / 2 - 9)
            num:SetText(tostring(i))
            num:SetTextColor(1, 0.85, 0.1)
            num:Hide()
            fakeRWNums[i] = num
        end

        for i = 1, MAX - 1 do
            local mx = (RW_SLOTS[i].x + RW_SLOTS[i+1].x) / 2
            local my = (RW_SLOTS[i].y + RW_SLOTS[i+1].y) / 2
            local arr = fakeRWFrame:CreateFontString(nil, "OVERLAY")
            arr:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            arr:SetPoint("CENTER", fakeRWFrame, "TOP", mx, RW_ARC_Y + my)
            arr:SetText("<")
            arr:SetTextColor(0.6, 0.3, 0.9, 0.85)
        end
    end

    for i = 1, MAX do
        fakeRWBgs[i]:Hide()
        fakeRWNums[i]:Hide()
    end
    for i, sym in ipairs(symbols) do
        if fakeRWBgs[i] then
            local r, g, b = getSymColor(sym.k)
            fakeRWRings[i]:SetColorTexture(r, g, b, 0.85)
            fakeRWIcons[i]:SetTexture(sym.tex)
            fakeRWIcons[i]:SetVertexColor(1, 1, 1, 1)
            fakeRWBgs[i]:Show()
            fakeRWNums[i]:Show()
        end
    end

    UIFrameFadeIn(fakeRWFrame, 0.3, 0, 1)
    PlaySound(8959, "Master")
    C_Timer.After(5, function() if fakeRWFrame then UIFrameFadeOut(fakeRWFrame, 0.5, 1, 0) end end)
end

local function autoComplete()
    autoAdded = false
    if #state ~= MAX - 1 then return end
    local used = {}
    for _, s in ipairs(state) do used[s.k] = true end
    for _, sym in ipairs(SYMS) do
        if not used[sym.k] then
            state[#state+1] = { k=sym.k, tex=sym.tex }
            autoAdded = true
            break
        end
    end
end

local function sendRW()
    showFakeRW(state)
    local msg = "RW:" .. serialize()
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY")
    end
end

local function makeActionBtn(parent, r, g, b)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets   = { left=1, right=1, top=1, bottom=1 },
    })
    btn:SetBackdropColor(r * 0.18, g * 0.18, b * 0.18, 0.9)
    btn:SetBackdropBorderColor(r, g, b, 0.85)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    lbl:SetPoint("CENTER")
    lbl:SetTextColor(1, 1, 1, 1)
    function btn:SetText(t) lbl:SetText(t) end
    function btn:GetText()  return lbl:GetText() end
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(r * 0.38, g * 0.38, b * 0.38, 1)
        self:SetBackdropBorderColor(1, 1, 1, 0.9)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(r * 0.18, g * 0.18, b * 0.18, 0.9)
        self:SetBackdropBorderColor(r, g, b, 0.85)
    end)
    return btn
end

local win

local function build()
    if win then return end

    local W, H = 290, 370

    win = CreateFrame("Frame", "LuraMemorySyncWin", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER", UIParent, "CENTER", 200, 80)
    restoreFramePos(win, "winPos")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePos(self, "winPos")
    end)
    win:SetFrameStrata("HIGH")
    win:SetBackdrop({
        bgFile   = FLAT,
        edgeFile = FLAT,
        edgeSize = 1,
        insets   = { left=1, right=1, top=1, bottom=1 },
    })
    win:SetBackdropColor(0.04, 0.0, 0.13, 0.92)
    win:SetBackdropBorderColor(0.5, 0.0, 0.9, 1.0)

    local header = win:CreateTexture(nil, "BACKGROUND", nil, 1)
    header:SetPoint("TOPLEFT",  win, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
    header:SetHeight(52)
    header:SetColorTexture(0.08, 0.0, 0.22, 1.0)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() win:Hide() end)

    local langBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    langBtn:SetSize(66, 18)
    langBtn:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -10)
    langBtn:SetScript("OnClick", function()
        LANG = (LANG == "fr") and "en" or "fr"
        LuraMemorySyncDB.lang = LANG
        applyLocale()
    end)
    ui.langBtn = langBtn

    local grip = CreateFrame("Frame", nil, win)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -4, 4)
    grip:EnableMouse(true)
    grip:SetFrameStrata("TOOLTIP")
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnEnter", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        GameTooltip:SetOwner(grip, "ANCHOR_TOP")
        GameTooltip:SetText(L[LANG].tip_resize, 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        GameTooltip:Hide()
    end)
    local resizing = false
    local origW, origH, origX, origY
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then
            resizing = true
            origW = win:GetWidth()
            origH = win:GetHeight()
            origX, origY = GetCursorPosition()
        end
    end)
    grip:SetScript("OnMouseUp", function() resizing = false end)
    grip:SetScript("OnUpdate", function()
        if not resizing then return end
        local cx, cy = GetCursorPosition()
        local eff = UIParent:GetEffectiveScale()
        local newW = math.max(250, math.min(600, origW + (cx - origX) / eff))
        local newH = math.max(350, math.min(700, origH + (origY - cy) / eff))
        win:SetSize(newW, newH)
    end)

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", win, "TOP", 0, -20)
    title:SetTextColor(0.85, 0.4, 1.0)
    ui.title = title

    local sep1 = win:CreateTexture(nil, "ARTWORK")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT",  win, "TOPLEFT",  1, -53)
    sep1:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -53)
    sep1:SetColorTexture(0.5, 0.0, 0.9, 0.8)

    local ARC_Y, iconSz = -100, 44
    for i = 1, MAX do
        local slot = CreateFrame("Frame", nil, win)
        slot:SetSize(iconSz, iconSz)
        slot:SetPoint("CENTER", win, "TOP", slots[i].x, ARC_Y + slots[i].y)
        slot:Hide()
        arcBgs[i] = slot

        local ring = slot:CreateTexture(nil, "BACKGROUND")
        ring:SetAllPoints(slot)
        ring:SetColorTexture(0.55, 0.30, 0.85, 0.85)
        applyCircularMask(slot, ring)
        arcRings[i] = ring

        local inner = slot:CreateTexture(nil, "BORDER")
        inner:SetSize(iconSz - 5, iconSz - 5)
        inner:SetPoint("CENTER")
        inner:SetColorTexture(0.07, 0.03, 0.15, 0.92)
        applyCircularMask(slot, inner)

        local tex = slot:CreateTexture(nil, "ARTWORK")
        tex:SetSize(iconSz - 9, iconSz - 9)
        tex:SetPoint("CENTER")
        applyCircularMask(slot, tex)
        arcIcons[i] = tex
    end

    for i = 1, MAX - 1 do
        local mx = (slots[i].x + slots[i+1].x) / 2
        local my = (slots[i].y + slots[i+1].y) / 2
        local arr = win:CreateFontString(nil, "OVERLAY")
        arr:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        arr:SetPoint("CENTER", win, "TOP", mx, ARC_Y + my)
        arr:SetText("<")
        arr:SetTextColor(0.5, 0.3, 0.8, 0.7)
    end

    local bossLabel = win:CreateFontString(nil, "OVERLAY")
    bossLabel:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    bossLabel:SetPoint("CENTER", win, "TOP", 0, ARC_Y)
    ui.bossLabel = bossLabel

    local sep2 = win:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 138)
    sep2:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 138)
    sep2:SetColorTexture(0.4, 0.0, 0.8, 0.45)

    local clr = makeActionBtn(win, 0.8, 0.1, 0.1)
    clr:SetHeight(24)
    clr:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 140)
    clr:SetPoint("BOTTOMRIGHT", win, "BOTTOM",      -5, 140)
    clr:SetScript("OnClick", function()
        state     = {}
        autoAdded = false
        redraw()
        sendClear()
    end)
    ui.clr = clr

    local snd = makeActionBtn(win, 0.0, 0.9, 0.3)
    snd:SetHeight(24)
    snd:SetPoint("BOTTOMLEFT",  win, "BOTTOM",       5, 140)
    snd:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 140)
    snd:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(L[LANG].tip_send, 1, 1, 1)
        GameTooltip:Show()
    end)
    snd:HookScript("OnLeave", function() GameTooltip:Hide() end)
    snd:SetScript("OnClick", function()
        if #state == 0 then return end
        sendState()
    end)
    ui.snd = snd

    local sep3 = win:CreateTexture(nil, "ARTWORK")
    sep3:SetHeight(1)
    sep3:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 134)
    sep3:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 134)
    sep3:SetColorTexture(0.3, 0.0, 0.6, 0.3)

    local say = makeActionBtn(win, 1.0, 0.85, 0.0)
    say:SetHeight(24)
    say:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 105)
    say:SetPoint("BOTTOMRIGHT", win, "BOTTOM",      -5, 105)
    say:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(L[LANG].tip_say, 1, 1, 1)
        GameTooltip:Show()
    end)
    say:HookScript("OnLeave", function() GameTooltip:Hide() end)
    say:SetScript("OnClick", function()
        if #state == 0 then return end
        SendChatMessage(buildPatternTextPlain(), "SAY")
        sendSayIcons()
    end)
    ui.say = say

    local rw = makeActionBtn(win, 1.0, 0.25, 0.05)
    rw:SetHeight(24)
    rw:SetPoint("BOTTOMLEFT",  win, "BOTTOM",       5, 105)
    rw:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 105)
    rw:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(L[LANG].tip_rw, 1, 1, 1)
        GameTooltip:Show()
    end)
    rw:HookScript("OnLeave", function() GameTooltip:Hide() end)
    rw:SetScript("OnClick", function() sendRW() end)
    ui.rw = rw

    local sep5 = win:CreateTexture(nil, "ARTWORK")
    sep5:SetHeight(1)
    sep5:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 99)
    sep5:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 99)
    sep5:SetColorTexture(0.3, 0.0, 0.6, 0.3)

    local combo = makeActionBtn(win, 1.0, 0.55, 0.0)
    combo:SetHeight(24)
    combo:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 72)
    combo:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 72)
    combo:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(L[LANG].tip_combo, 1, 1, 1)
        GameTooltip:Show()
    end)
    combo:HookScript("OnLeave", function() GameTooltip:Hide() end)
    combo:SetScript("OnClick", function()
        if #state == 0 then return end
        SendChatMessage(buildPatternTextPlain(), "SAY")
        sendSayIcons()
        sendRW()
    end)
    ui.combo = combo

    local sep4 = win:CreateTexture(nil, "ARTWORK")
    sep4:SetHeight(1)
    sep4:SetPoint("BOTTOMLEFT",  win, "BOTTOMLEFT",  10, 57)
    sep4:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 57)
    sep4:SetColorTexture(0.3, 0.0, 0.6, 0.3)

    local bSz, bGap = 44, 5

    for i, sym in ipairs(SYMS) do
        local btn = CreateFrame("Button", nil, win)
        btn:SetSize(bSz, bSz)
        local xCenter = (i - (MAX + 1) / 2) * (bSz + bGap)
        btn:SetPoint("BOTTOM", win, "BOTTOM", xCenter, 8)

        local outerRing = btn:CreateTexture(nil, "BACKGROUND")
        outerRing:SetAllPoints(btn)
        outerRing:SetColorTexture(sym.r, sym.g, sym.b, 1.0)
        applyCircularMask(btn, outerRing)

        local innerBg = btn:CreateTexture(nil, "BORDER")
        innerBg:SetSize(bSz - 6, bSz - 6)
        innerBg:SetPoint("CENTER")
        innerBg:SetColorTexture(0.05, 0.05, 0.1, 0.95)
        applyCircularMask(btn, innerBg)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetSize(bSz - 12, bSz - 12)
        tex:SetPoint("CENTER")
        tex:SetTexture(sym.tex)
        applyCircularMask(btn, tex)

        btn:SetScript("OnEnter", function(s)
            outerRing:SetColorTexture(1, 1, 1, 1)
            innerBg:SetColorTexture(sym.r * 0.2, sym.g * 0.2, sym.b * 0.2, 1)
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L[LANG]["sym_"..sym.langKey], 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            outerRing:SetColorTexture(sym.r, sym.g, sym.b, 1.0)
            innerBg:SetColorTexture(0.05, 0.05, 0.1, 0.95)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if #state >= MAX then return end
            for _, s in ipairs(state) do
                if s.k == sym.k then return end
            end
            autoAdded = false
            state[#state+1] = { k=sym.k, tex=sym.tex }
            autoComplete()
            redraw()
        end)
    end

    applyLocale()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("CHAT_MSG_ADDON")

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and (...) == ADDON_NAME then
        if not LuraMemorySyncDB then LuraMemorySyncDB = {} end
        if LuraMemorySyncDB.lang then LANG = LuraMemorySyncDB.lang end
        build()
        print("|cffaa44ff"..L[LANG].title.."|r "..L[LANG].loaded)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX then return end

        if msg == "CLEAR" then
            state     = {}
            autoAdded = false
            if win then redraw() end
            return
        end

        local stateStr = msg:match("^S:(.*)$")
        if stateStr then
            state     = deserialize(stateStr)
            autoAdded = false
            if not win then build() end
            win:Show()
            redraw()
            return
        end

        local rwStr = msg:match("^RW:(.*)$")
        if rwStr then
            showFakeRW(deserialize(rwStr))
            return
        end

        local sayIcoStr = msg:match("^SAYICO:(.*)$")
        if sayIcoStr then
            showSayIcons(sender, deserialize(sayIcoStr))
            return
        end
    end
end)

SLASH_LURAMEMORYSYNC1 = "/ums"
SLASH_LURAMEMORYSYNC2 = "/ura"

SlashCmdList["LURAMEMORYSYNC"] = function(msg)
    msg = (msg or ""):lower():trim()
    if msg == "clear" then
        state     = {}
        autoAdded = false
        if win then redraw() end
        sendClear()
    elseif msg == "rw" then
        sendRW()
    else
        if win then
            if win:IsShown() then win:Hide() else win:Show() end
        end
    end
end
