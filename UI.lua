local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local ICON, CELL, ROWH, NAMEW, HEAD, SEC_HEAD = 36, 22, 22, 90, 20, 19 -- ICON/CELL/ROWH/NAMEW folgen den Ansicht-Optionen
local MAXBTN, MAXROWS, MAXCOLS = 6, 8, 8

local TEX_OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local TEX_BAD = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

local COL = {
    bg = { 0.04, 0.05, 0.07, 0.92 },
    border = { 0.18, 0.21, 0.28, 1 },
    head = { 0.09, 0.11, 0.15, 1 },
    gold = { 0.85, 0.70, 0.35 },
    ok = { 0.16, 0.55, 0.28 },
    missing = { 0.95, 0.30, 0.30 },
    expiring = { 0.95, 0.75, 0.20 },
    grey = { 0.35, 0.37, 0.42 },
}

-- Akzentfarben (Standard: gold = bisheriges Aussehen)
local ACCENTS = {
    gold = { { 0.85, 0.70, 0.35 }, { 0.80, 0.67, 0.38 } },
    silver = { { 0.75, 0.80, 0.88 }, { 0.70, 0.76, 0.85 } },
    blue = { { 0.35, 0.65, 0.95 }, { 0.45, 0.70, 0.95 } },
    green = { { 0.35, 0.80, 0.50 }, { 0.45, 0.80, 0.55 } },
    rose = { { 0.90, 0.45, 0.65 }, { 0.90, 0.55, 0.70 } },
}
ns.ACCENT_ORDER = { "gold", "silver", "blue", "green", "rose" }

local function V()
    return (ns.DB and ns.DB.view) or ns.DefaultView
end

local accentTex = {}   -- { tex, alpha }  (Ecken, Kopflinie)
local cornerTex = {}   -- nur Ecken (abschaltbar)
local secTitles = {}   -- Bereichsüberschriften

local frame
local buttons, rows = {}, {}
local secA, secB, secC -- Bereiche: Zu buffen / Hinweise / Gruppe
local colIcons = {}

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function FormatTime(sec)
    if sec >= 3600 then return math.floor(sec / 3600 + 0.5) .. "h" end
    if sec >= 60 then return math.floor(sec / 60 + 0.5) .. "m" end
    return math.max(0, math.floor(sec)) .. "s"
end

ns.FormatTime = FormatTime

local function Outline(fs, size)
    fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
end


-- goldene Eckzierden (Zierrahmen)
local function AddCorners(f, size, a)
    local g = COL.gold
    local function line(p, w, h)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(g[1], g[2], g[3], a)
        t:SetSize(w, h)
        t:SetPoint(p, f, p, 0, 0)
        accentTex[#accentTex + 1] = { t, a }
        cornerTex[#cornerTex + 1] = t
    end
    for _, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        line(p, size, 1)
        line(p, 1, size)
    end
end

-- eingerahmter Bereich mit Überschrift und Trennlinie
local function MakeSection(titleText)
    local sec = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sec:SetFrameLevel(frame:GetFrameLevel() + 1)
    sec:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sec:SetBackdropColor(0.07, 0.085, 0.11, 0.9)
    sec:SetBackdropBorderColor(0.20, 0.24, 0.32, 1)
    sec.title = sec:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sec.title:SetPoint("TOPLEFT", 8, -4)
    sec.title:SetText(titleText)
    sec.title:SetTextColor(0.80, 0.67, 0.38)
    secTitles[#secTitles + 1] = sec.title
    sec.line = sec:CreateTexture(nil, "ARTWORK")
    sec.line:SetPoint("TOPLEFT", 6, -(SEC_HEAD - 2))
    sec.line:SetPoint("TOPRIGHT", -6, -(SEC_HEAD - 2))
    sec.line:SetHeight(1)
    sec.line:SetColorTexture(1, 1, 1, 0.08)
    AddCorners(sec, 5, 0.7)
    sec.secCorners = { unpack(cornerTex, #cornerTex - 7, #cornerTex) }
    sec:Hide()
    return sec
end

---------------------------------------------------------------------------
-- Aufbau (einmalig, außerhalb des Kampfes bei PLAYER_LOGIN)
---------------------------------------------------------------------------
function UI:Create()
    frame = CreateFrame("Frame", "GroupBuffSUIFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetSize(170, 40)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(COL.bg))
    frame:SetBackdropBorderColor(unpack(COL.border))

    frame:SetScript("OnDragStart", function(self)
        if not ns.DB.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) UI:StopDrag() end)

    -- Kopfleiste mit Goldlinie, Titel, Zähler und Einklapp-Knopf
    frame.head = frame:CreateTexture(nil, "BACKGROUND")
    frame.head:SetPoint("TOPLEFT", 1, -1)
    frame.head:SetPoint("TOPRIGHT", -1, -1)
    frame.head:SetHeight(HEAD - 2)
    frame.head:SetColorTexture(unpack(COL.head))

    frame.accent = frame:CreateTexture(nil, "BORDER")
    frame.accent:SetPoint("TOPLEFT", 1, -(HEAD - 1))
    frame.accent:SetPoint("TOPRIGHT", -1, -(HEAD - 1))
    frame.accent:SetHeight(1)
    frame.accent:SetColorTexture(COL.gold[1], COL.gold[2], COL.gold[3], 0.9)
    accentTex[#accentTex + 1] = { frame.accent, 0.9 }

    AddCorners(frame, 8, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("LEFT", frame, "TOPLEFT", 8, -(HEAD / 2))
    frame.title:SetText(L.TITLE .. " |cff8a95a5by " .. ns.AUTHOR .. "|r")

    -- Credits beim Überfahren des Titels
    frame.titleHit = CreateFrame("Frame", nil, frame)
    frame.titleHit:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.titleHit:SetSize(150, HEAD - 3)
    frame.titleHit:EnableMouse(true)
    frame.titleHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L.TITLE, 0.9, 0.75, 0.4)
        GameTooltip:AddLine("by " .. ns.AUTHOR, 0.8, 0.85, 0.9)
        GameTooltip:AddLine(ns.CREDIT_LINE, 1, 0.6, 0.8)
        GameTooltip:Show()
    end)
    frame.titleHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.titleHit:RegisterForDrag("LeftButton")
    frame.titleHit:SetScript("OnDragStart", function()
        if not ns.DB.locked and not InCombatLockdown() then frame:StartMoving() end
    end)
    frame.titleHit:SetScript("OnDragStop", function() UI:StopDrag() end)

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.count:SetPoint("RIGHT", frame, "TOPRIGHT", -26, -(HEAD / 2))

    -- Zahnrad: öffnet die Optionen
    frame.gear = CreateFrame("Button", nil, frame)
    frame.gear:SetSize(16, 16)
    frame.gear:SetPoint("RIGHT", frame, "TOPRIGHT", -24, -(HEAD / 2))
    frame.gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    frame.gear:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton")
    frame.gear:GetNormalTexture():SetVertexColor(0.8, 0.8, 0.85)
    frame.gear:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if ns.Config then ns.Config:Open() end
    end)
    frame.gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.GEAR_TT)
        GameTooltip:Show()
    end)
    frame.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.toggle = CreateFrame("Button", nil, frame)
    frame.toggle:SetSize(18, 18)
    frame.toggle:SetPoint("RIGHT", frame, "TOPRIGHT", -4, -(HEAD / 2))
    frame.toggle.t = frame.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.toggle.t:SetAllPoints()
    frame.toggle:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        ns.DB.collapsed = not ns.DB.collapsed
        if ns.Schedule then ns.Schedule(0) end
    end)
    frame.toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.COLLAPSE_TT)
        GameTooltip:Show()
    end)
    frame.toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    secA = MakeSection(L.SEC_CAST)
    secB = MakeSection(L.SEC_INFO)
    secC = MakeSection(L.SEC_GROUP)

    secB.status = secB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    secB.status:SetJustifyH("LEFT")
    secB.alert = secB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    secB.alert:SetJustifyH("LEFT")
    secB.cons = secB:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    secB.cons:SetJustifyH("LEFT")

    secC.more = secC:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    for c = 1, MAXCOLS do
        local t = secC:CreateTexture(nil, "ARTWORK")
        t:SetSize(CELL - 6, CELL - 6)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t:Hide()
        colIcons[c] = t
    end

    -- Klickbare Cast-Buttons (secure): Klick zaubert auf das Mitglied, dem der Buff fehlt
    for i = 1, MAXBTN do
        local b = CreateFrame("Button", "GroupBuffSUIBtn" .. i, frame, "SecureActionButtonTemplate")
        b:SetSize(ICON, ICON)
        b:SetFrameLevel(frame:GetFrameLevel() + 3)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "spell")

        -- farbiger Rahmen (Zustand), pulsiert bei fehlendem Buff
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetPoint("TOPLEFT", -2, 2)
        b.bg:SetPoint("BOTTOMRIGHT", 2, -2)
        b.bg:SetColorTexture(unpack(COL.gold))

        b.inner = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.inner:SetAllPoints()
        b.inner:SetColorTexture(0, 0, 0, 1)

        b.pulse = b.bg:CreateAnimationGroup()
        b.pulse:SetLooping("BOUNCE")
        local a = b.pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.25)
        a:SetDuration(0.7)

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        b.count = b:CreateFontString(nil, "OVERLAY")
        Outline(b.count, 14)
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)

        b.time = b:CreateFontString(nil, "OVERLAY")
        Outline(b.time, 10)
        b.time:SetPoint("TOP", 0, -2)
        b.time:SetTextColor(1, 0.85, 0.3)

        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.2)

        b:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.fam.name, 1, 1, 1)
            GameTooltip:AddLine(L.MISSING_TT, 0.8, 0.8, 0.8)
            for idx, u in ipairs(e.units) do
                if idx > 10 then
                    GameTooltip:AddLine(string.format(L.MORE, #e.units - 10), 0.7, 0.7, 0.7)
                    break
                end
                local r, g, bb = ClassColor(u.class)
                local suffix = u.inRange and "" or (" |cff999999" .. L.OUT_OF_RANGE .. "|r")
                local timeText = (u.state == "expiring" and u.rem) and (" |cffffd24d" .. FormatTime(u.rem) .. "|r") or ""
                GameTooltip:AddLine(u.name .. timeText .. suffix, r, g, bb)
            end
            GameTooltip:AddLine(string.format(L.CLICK_TT, e.targetName or "?"), 0.5, 1, 0.5)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        buttons[i] = b
    end

    -- Mitgliederzeilen
    for r = 1, MAXROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(NAMEW + MAXCOLS * CELL, ROWH)
        row:SetFrameLevel(frame:GetFrameLevel() + 3)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetWidth(NAMEW - 8)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.cells = {}
        for c = 1, MAXCOLS do
            local bd = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            local t = row:CreateTexture(nil, "ARTWORK")
            t:SetSize(CELL - 4, CELL - 4)
            t:SetPoint("LEFT", NAMEW + (c - 1) * CELL + 2, 0)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            bd:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1)
            bd:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
            bd:SetColorTexture(0, 0, 0, 0)

            local fs = row:CreateFontString(nil, "OVERLAY")
            Outline(fs, 9)
            fs:SetPoint("BOTTOM", t, "BOTTOM", 0, 0)

            local mark = row:CreateFontString(nil, "OVERLAY")
            Outline(mark, 16)
            mark:SetPoint("CENTER", t, "CENTER", 0, 0)
            mark:SetTextColor(1, 0.35, 0.35)

            row.cells[c] = { tex = t, bd = bd, txt = fs, mark = mark }
        end
        row:Hide()
        rows[r] = row
    end

    UI:ApplySettings()
end

-- Ziehen beenden: angedockt wird der Abstand zur Leiste gemerkt, sonst die freie Bildschirmposition
function UI:StopDrag()
    frame:StopMovingOrSizing()
    if ns.Dock and ns.Dock:IsActive() then
        ns.Dock:SaveFree(frame)
        if ns.Config and ns.Config.RefreshDock then ns.Config:RefreshDock() end
    else
        local p, _, rp, x, y = frame:GetPoint()
        ns.DB.point = { p, "UIParent", rp, x, y }
    end
end

-- Ansicht-Optionen anwenden (nur außerhalb des Kampfes aufrufen)
function UI:ApplyView()
    if not frame then return end
    local v = V()
    local pal = ACCENTS[v.accent] or ACCENTS.gold
    local c, tc = pal[1], pal[2]
    for _, e in ipairs(accentTex) do e[1]:SetColorTexture(c[1], c[2], c[3], e[2]) end
    for _, t in ipairs(secTitles) do t:SetTextColor(tc[1], tc[2], tc[3]) end
    for _, t in ipairs(cornerTex) do t:SetShown(v.corners) end

    local a = math.max(0, math.min(100, v.bgAlpha or 92)) / 100
    local skinned = ns.Dock and ns.Dock:IsSkinned()
    if ns.Dock then ns.Dock:Skin(frame, skinned) end
    -- mit Classic-Hintergrund: Standardfläche ausblenden, der SpartanUI-Hintergrund scheint durch
    frame:SetBackdropColor(COL.bg[1], COL.bg[2], COL.bg[3], skinned and 0 or a)
    if skinned and not v.dockBorder then
        frame:SetBackdropBorderColor(0, 0, 0, 0.7)
    else
        frame:SetBackdropBorderColor(unpack(COL.border))
    end
    for _, sec in ipairs({ secA, secB, secC }) do
        if sec then
            if v.sectionFrames and skinned then
                -- auf dem Artwork: keine dunklen Kästen, nur feine Trennlinien
                sec:SetBackdropColor(0, 0, 0, 0)
                sec:SetBackdropBorderColor(0, 0, 0, 0.55)
            elseif v.sectionFrames then
                sec:SetBackdropColor(0.07, 0.085, 0.11, math.min(0.9, a))
                sec:SetBackdropBorderColor(0.20, 0.24, 0.32, 1)
            else
                sec:SetBackdropColor(0, 0, 0, 0)
                sec:SetBackdropBorderColor(0, 0, 0, 0)
            end
            sec.title:SetShown(v.sectionTitles)
            sec.line:SetShown(v.sectionTitles)
            for _, t in ipairs(sec.secCorners or {}) do t:SetShown(v.corners and v.sectionFrames) end
        end
    end
    frame.gear:SetShown(v.gear)
    frame.count:ClearAllPoints()
    frame.count:SetPoint("RIGHT", frame, "TOPRIGHT", v.gear and -44 or -26, -(HEAD / 2))
    frame.title:SetText(L.TITLE .. (v.credits and (" |cff8a95a5by " .. ns.AUTHOR .. "|r") or ""))
end

function UI:ApplySettings()
    if not frame then return end
    local DB = ns.DB
    UI:ApplyView()
    if ns.Dock and ns.Dock:IsActive() then
        ns.Dock:Place(frame)
    else
        frame:ClearAllPoints()
        local p = DB.point
        frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    end
    frame:SetScale(DB.scale or 1)
    if DB.shown then frame:Show() else frame:Hide() end
end

-- Im Kampf nur abdunkeln: geschützte Frames dürfen dort nicht verändert werden.
function UI:SetCombat(flag)
    if not frame then return end
    frame:SetAlpha(flag and (V().combatAlpha or 35) / 100 or 1)
end

---------------------------------------------------------------------------
-- Darstellung (wird nur außerhalb des Kampfes aufgerufen)
---------------------------------------------------------------------------
local function SetCellBorder(cell, color, alpha)
    if color then
        cell.bd:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    else
        cell.bd:SetColorTexture(0, 0, 0, 0)
    end
end

function UI:Render(model)
    if not frame then return end
    local DB = ns.DB
    frame:SetAlpha(1)

    local v = V()
    ICON = v.iconSize or 36
    CELL = v.rowSize or 22
    ROWH = CELL
    NAMEW = v.nameWidth or 90
    for _, b in ipairs(buttons) do b:SetSize(ICON, ICON) end
    for c = 1, MAXCOLS do colIcons[c]:SetSize(CELL - 6, CELL - 6) end
    for _, row in ipairs(rows) do
        row:SetHeight(ROWH)
        row.name:SetWidth(NAMEW - 8)
        for c = 1, MAXCOLS do
            local cell = row.cells[c]
            cell.tex:SetSize(CELL - 4, CELL - 4)
            cell.tex:ClearAllPoints()
            cell.tex:SetPoint("LEFT", NAMEW + (c - 1) * CELL + 2, 0)
        end
    end

    local fams = model.fams
    local nF = math.min(#fams, MAXCOLS)
    local nBtn = math.min(#model.missing, MAXBTN)
    local collapsed = DB.collapsed and true or false
    local showRows = DB.members and not collapsed and #model.rows > 0 and nF > 0

    local cons = model.cons
    local consMissing = cons and #cons.missing or 0
    local consExpiring = cons and #cons.expiring or 0
    local allOk = nF > 0 and #model.missing == 0 and consMissing == 0 and consExpiring == 0

    -- Kopfzeile: Zähler und Einklapp-Knopf
    frame.toggle.t:SetText(collapsed and "+" or "-")
    if nF == 0 then
        frame.count:SetText("")
    elseif allOk then
        frame.count:SetText(TEX_OK)
    else
        frame.count:SetText(TEX_BAD .. " |cffff8a8a" .. (#model.missing + consMissing) .. "|r")
    end

    local CX = 12                 -- linker Innenrand der Inhalte (Fenster)
    local y = HEAD + 6            -- laufende Position im Fenster
    local secs = {}               -- { frame, top, height }

    ---------------------------------------------------------------- Bereich A: Zu buffen
    for i = 1, MAXBTN do
        local b = buttons[i]
        local e = model.missing[i]
        if i <= nBtn and e then
            b.entry = e
            b.icon:SetTexture(e.fam.icon)
            b.icon:SetDesaturated(not e.inRange)
            b.icon:SetAlpha(e.inRange and 1 or 0.5)
            b.count:SetText((v.badges and #e.units > 1) and #e.units or "")
            b.time:SetText((DB.timers and e.minRem) and FormatTime(e.minRem) or "")
            b:SetAttribute("spell", e.fam.name)
            b:SetAttribute("unit", e.target)

            local hasMissing = false
            for _, u in ipairs(e.units) do
                if u.state == "missing" then hasMissing = true; break end
            end
            local c = (not e.inRange) and COL.grey or (hasMissing and COL.missing or COL.expiring)
            b.bg:SetColorTexture(c[1], c[2], c[3], 1)
            b.pulse:Stop()
            b.bg:SetAlpha(1)
            if hasMissing and e.inRange and v.pulse then b.pulse:Play() end

            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", CX + 4 + (i - 1) * (ICON + 8), -(y + SEC_HEAD + 5))
            b:Show()
        else
            b.entry = nil
            b.pulse:Stop()
            b:Hide()
        end
    end
    if nBtn > 0 then
        local h = SEC_HEAD + ICON + 14
        secs[#secs + 1] = { secA, y, h }
        y = y + h + 6
    end

    ---------------------------------------------------------------- Bereich B: Hinweise
    local lines = {}
    if nF == 0 then
        lines[#lines + 1] = { secB.status, "|cffaaaaaa" .. L.NO_SPELLS .. "|r", 1 }
    elseif allOk then
        lines[#lines + 1] = { secB.status, TEX_OK .. " |cff6fe08a" .. L.ALL_OK .. "|r", 1 }
    end

    local ex = model.expiring or {}
    if #ex > 0 then
        local t = {}
        for _, e in ipairs(ex) do
            t[#t + 1] = string.format(L.EXPIRE_LINE, e.fam.name, e.n, e.total)
        end
        lines[#lines + 1] = { secB.alert, "|cffffb347" .. table.concat(t, "\n") .. "|r", #t }
    end

    local consLines = {}
    if consMissing > 0 then
        local t = {}
        for _, e in ipairs(cons.missing) do t[#t + 1] = L.CONS[e.key] or e.key end
        consLines[#consLines + 1] = "|cffff7b7b" .. string.format(L.CONS_MISSING, table.concat(t, ", ")) .. "|r"
    end
    if consExpiring > 0 then
        local t = {}
        for _, e in ipairs(cons.expiring) do
            t[#t + 1] = (L.CONS[e.key] or e.key) .. " (" .. FormatTime(e.rem) .. ")"
        end
        consLines[#consLines + 1] = "|cffffd24d" .. string.format(L.CONS_EXPIRING, table.concat(t, ", ")) .. "|r"
    end
    if #consLines > 0 then
        lines[#lines + 1] = { secB.cons, table.concat(consLines, "\n"), #consLines }
    end

    secB.status:SetText(""); secB.alert:SetText(""); secB.cons:SetText("")
    local infoW = 0
    if #lines > 0 then
        local oy = SEC_HEAD + 4
        for _, ln in ipairs(lines) do
            local fs, text, n = ln[1], ln[2], ln[3]
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", secB, "TOPLEFT", 8, -oy)
            fs:SetText(text)
            infoW = math.max(infoW, math.ceil(fs:GetStringWidth()) + 28)
            oy = oy + 15 * n
        end
        local h = oy + 4
        secs[#secs + 1] = { secB, y, h }
        y = y + h + 6
    end

    ---------------------------------------------------------------- Bereich C: Gruppe
    local shownRows = 0
    for c = 1, MAXCOLS do colIcons[c]:Hide() end
    if showRows then
        local top = y
        -- Spaltenköpfe: die Buff-Icons
        for c = 1, nF do
            local t = colIcons[c]
            t:SetTexture(fams[c].icon)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", secC, "TOPLEFT", (CX - 6) + NAMEW + (c - 1) * CELL + 4, -(SEC_HEAD + 3))
            t:Show()
        end
        y = y + SEC_HEAD + 3 + (CELL - 6) + 3

        for r = 1, MAXROWS do
            local row = rows[r]
            local data = model.rows[r]
            if data then
                shownRows = shownRows + 1
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", CX, -y)
                row.name:SetText(data.name)
                if v.classColors then row.name:SetTextColor(ClassColor(data.class)) else row.name:SetTextColor(0.9, 0.9, 0.9) end
                if data.missing > 0 then
                    row.bg:SetColorTexture(0.6, 0.1, 0.1, 0.20)
                elseif v.zebra and r % 2 == 0 then
                    row.bg:SetColorTexture(1, 1, 1, 0.04)
                else
                    row.bg:SetColorTexture(1, 1, 1, 0)
                end
                for c = 1, MAXCOLS do
                    local cell = row.cells[c]
                    local f = fams[c]
                    if c <= nF and f then
                        local st = data.status[f.key]
                        cell.tex:SetTexture(f.icon)
                        cell.txt:SetText("")
                        cell.mark:SetText("")
                        cell.tex:SetDesaturated(false)
                        cell.tex:SetVertexColor(1, 1, 1)
                        cell.tex:SetAlpha(1)
                        SetCellBorder(cell, nil)
                        if st == "missing" then
                            cell.tex:SetDesaturated(true)
                            cell.tex:SetVertexColor(0.55, 0.3, 0.3)
                            cell.mark:SetText("×")
                            SetCellBorder(cell, COL.missing)
                        elseif st == "expiring" then
                            SetCellBorder(cell, COL.expiring)
                            local rem = data.rem[f.key]
                            if rem then cell.txt:SetText(FormatTime(rem)) end
                        elseif st == "ok" then
                            SetCellBorder(cell, COL.ok, 0.9)
                            local rem = data.rem[f.key]
                            if DB.timers and rem then cell.txt:SetText(FormatTime(rem)) end
                        elseif st == "na" then
                            cell.tex:SetAlpha(0.12)
                        elseif st == "unknown" then
                            cell.tex:SetAlpha(0.35)
                            cell.txt:SetText("?")
                            SetCellBorder(cell, COL.grey, 0.8)
                        end
                        cell.tex:Show()
                    else
                        cell.tex:Hide()
                        cell.txt:SetText("")
                        cell.mark:SetText("")
                        SetCellBorder(cell, nil)
                    end
                end
                row:Show()
                y = y + ROWH
            else
                row:Hide()
            end
        end

        secC.more:SetText("")
        if #model.rows > MAXROWS then
            secC.more:ClearAllPoints()
            secC.more:SetPoint("TOPLEFT", frame, "TOPLEFT", CX, -y)
            secC.more:SetText(string.format(L.MORE, #model.rows - MAXROWS))
            y = y + 14
        end
        y = y + 4
        secs[#secs + 1] = { secC, top, y - top }
        y = y + 6
    else
        for r = 1, MAXROWS do rows[r]:Hide() end
        secC.more:SetText("")
    end

    ---------------------------------------------------------------- Größe und Bereiche platzieren
    local w = 250 -- Titel "GroupBuff SUI by Solomon" ist länger als bei GroupBuffs
    if nBtn > 0 then w = math.max(w, 2 * CX + 8 + nBtn * (ICON + 8)) end
    if shownRows > 0 then w = math.max(w, 2 * CX + NAMEW + nF * CELL + 8) end
    w = math.max(w, infoW + 12)
    frame:SetSize(w, y + 4)

    for _, sec in ipairs({ secA, secB, secC }) do sec:Hide() end
    for _, e in ipairs(secs) do
        local sec, top, h = e[1], e[2], e[3]
        sec:ClearAllPoints()
        sec:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -top)
        sec:SetSize(w - 12, h)
        sec:Show()
    end
    for r = 1, MAXROWS do rows[r]:SetWidth(w - 2 * CX) end

    if ns.Dock then ns.Dock:Sync() end

    -- Sichtbarkeit
    if not DB.shown then
        frame:Hide()
    elseif DB.hideWhenOk and nF > 0 and #model.missing == 0 then
        frame:Hide()
    else
        frame:Show()
    end
end
