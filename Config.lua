local ADDON, ns = ...
local L = ns.L

-- Optionsfenster: erscheint unter Optionen > AddOns > GroupBuff SUI und öffnet mit /gbs config.
-- Nutzt bewusst nur wenige, lang bestehende Vorlagen (UICheckButtonTemplate, UIPanelButtonTemplate,
-- InputBoxTemplate). Schlägt der Aufbau fehl, bleiben die /gbs-Befehle voll nutzbar.

local Config = {}
ns.Config = Config

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end

local TOGGLES = {
    -- { Schlüssel in GroupBuffSUIDB, Spalte (1/2) }
    { "shown", 1 }, { "locked", 1 }, { "members", 1 }, { "hideWhenOk", 1 },
    { "timers", 1 }, { "expireAlert", 1 }, { "sound", 1 },
    { "roleFilter", 2 }, { "pets", 2 }, { "consumables", 2 }, { "weaponCheck", 2 },
    { "autoReport", 2 }, { "debug", 2 },
}
local CONS_KEYS = { "flask", "food", "armor" }
local MAX_CUSTOM_ROWS = 3

local panel, viewPanel, dockPanel
local dockChecks, dockValues, dockSide, dockStatus, dockStyle = {}, {}, nil, nil, nil
local viewChecks, viewValues, viewCycle, viewAccent = {}, {}, {}, {}
local checks, customRows = {}, {}
local scaleText, warnText, consCatBtn
local consCat = 1

local function DB() return ns.DB end

local function Apply()
    if not InCombatLockdown() and ns.UI then ns.UI:ApplySettings() end
    if ns.Schedule then ns.Schedule(0) end
end

local function FormatWarn(sec)
    if sec >= 60 then
        local m = math.floor(sec / 60)
        local s = sec % 60
        return s == 0 and (m .. " min") or (m .. " min " .. s .. " s")
    end
    return sec .. " s"
end

local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Button(parent, text, w, h, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Stepper(parent, y, title, step, onMinus, onPlus)
    Label(parent, title, 16, y)
    Button(parent, "-", 26, 22, 220, y + 4, onMinus)
    local value = Label(parent, "", 254, y)
    value:SetWidth(90)
    Button(parent, "+", 26, 22, 350, y + 4, onPlus)
    return value
end

function Config:Refresh()
    if not panel then return end
    local db = DB()
    for key, cb in pairs(checks) do cb:SetChecked(db[key] and true or false) end
    scaleText:SetText(math.floor((db.scale or 1) * 100 + 0.5) .. " %")
    warnText:SetText(FormatWarn(db.warn or 120))
    consCatBtn:SetText(L.CONS[CONS_KEYS[consCat]] or CONS_KEYS[consCat])

    local ids = {}
    for id in pairs(db.custom) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, MAX_CUSTOM_ROWS do
        local row, id = customRows[i], ids[i]
        if id then
            local c = db.custom[id]
            local extra = c.mana and (" · " .. L.CFG.MANA) or ""
            row.text:SetText((GetSpellName(id) or ("#" .. id)) .. "  (" .. id .. ")" .. extra)
            row.id = id
            row.text:Show(); row.remove:Show()
        else
            row.id = nil
            row.text:Hide(); row.remove:Hide()
        end
    end
    if #ids > MAX_CUSTOM_ROWS then
        customRows.more:SetText(string.format(L.MORE, #ids - MAX_CUSTOM_ROWS))
    else
        customRows.more:SetText("")
    end
end

local BuildView, BuildDock

local function Build()
    panel = CreateFrame("Frame", "GroupBuffSUIOptions")
    panel.name = "GroupBuff SUI"
    panel:SetSize(600, 560)
    panel:Hide()

    Label(panel, L.CFG.TITLE, 16, -14, "GameFontNormalLarge")

    -- Schalter in zwei Spalten
    local rowIdx = { 0, 0 }
    for _, t in ipairs(TOGGLES) do
        local key, col = t[1], t[2]
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 12 + (col - 1) * 290, -44 - rowIdx[col] * 28)
        rowIdx[col] = rowIdx[col] + 1
        local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(L.CFG[key])
        cb:SetScript("OnClick", function(self)
            DB()[key] = self:GetChecked() and true or false
            Apply()
        end)
        checks[key] = cb
    end

    -- Größe und Warnschwelle
    scaleText = Stepper(panel, -250, L.CFG.SCALE, 0.1,
        function()
            DB().scale = math.max(0.5, math.floor((DB().scale - 0.1) * 10 + 0.5) / 10)
            Apply(); Config:Refresh()
        end,
        function()
            DB().scale = math.min(2, math.floor((DB().scale + 0.1) * 10 + 0.5) / 10)
            Apply(); Config:Refresh()
        end)
    warnText = Stepper(panel, -284, L.CFG.WARN, 30,
        function() DB().warn = math.max(0, DB().warn - 30); Apply(); Config:Refresh() end,
        function() DB().warn = math.min(600, DB().warn + 30); Apply(); Config:Refresh() end)

    -- Eigene Buffs
    Label(panel, L.CFG.CUSTOM, 16, -326, "GameFontNormal")
    for i = 1, MAX_CUSTOM_ROWS do
        local y = -348 - (i - 1) * 24
        local row = {}
        row.text = Label(panel, "", 24, y)
        row.remove = Button(panel, "X", 26, 20, 330, y + 3, function()
            if row.id then
                DB().custom[row.id] = nil
                ns.BuildFamilies()
                Apply(); Config:Refresh()
            end
        end)
        customRows[i] = row
    end
    customRows.more = Label(panel, "", 24, -348 - MAX_CUSTOM_ROWS * 24, "GameFontDisableSmall")

    local addY = -348 - MAX_CUSTOM_ROWS * 24 - 22
    Label(panel, L.CFG.ID, 16, addY)
    local idBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    idBox:SetSize(80, 22)
    idBox:SetPoint("TOPLEFT", 92, addY + 4)
    idBox:SetAutoFocus(false)
    idBox:SetNumeric(true)
    idBox:SetMaxLetters(9)

    local manaCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    manaCb:SetSize(26, 26)
    manaCb:SetPoint("TOPLEFT", 184, addY + 6)
    local manaFs = manaCb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    manaFs:SetPoint("LEFT", manaCb, "RIGHT", 2, 0)
    manaFs:SetText(L.CFG.MANA)

    Button(panel, L.CFG.ADD, 110, 22, 300, addY + 4, function()
        local id = tonumber(idBox:GetText())
        if not id or not GetSpellName(id) then
            print("|cff33ff99GroupBuff SUI|r:", string.format(L.BAD_ID, idBox:GetText()))
            return
        end
        DB().custom[id] = { mana = manaCb:GetChecked() and true or nil }
        idBox:SetText("")
        manaCb:SetChecked(false)
        ns.BuildFamilies()
        Apply(); Config:Refresh()
    end)

    -- Verbrauchsgut-ID eintragen (Kategorie wechselbar)
    local consY = addY - 40
    Label(panel, L.CFG.CONS_ID, 16, consY)
    consCatBtn = Button(panel, "", 130, 22, 130, consY + 4, function()
        consCat = consCat % #CONS_KEYS + 1
        Config:Refresh()
    end)
    local consBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    consBox:SetSize(80, 22)
    consBox:SetPoint("TOPLEFT", 276, consY + 4)
    consBox:SetAutoFocus(false)
    consBox:SetNumeric(true)
    consBox:SetMaxLetters(9)
    Button(panel, L.CFG.ADD, 110, 22, 372, consY + 4, function()
        local id = tonumber(consBox:GetText())
        if not id or not GetSpellName(id) then
            print("|cff33ff99GroupBuff SUI|r:", string.format(L.BAD_ID, consBox:GetText()))
            return
        end
        DB().cons[CONS_KEYS[consCat]][id] = true
        consBox:SetText("")
        Apply()
        print("|cff33ff99GroupBuff SUI|r:", string.format(L.CONS_ADDED, GetSpellName(id), L.CONS[CONS_KEYS[consCat]]))
    end)
    Label(panel, L.CFG.HINT, 16, consY - 30, "GameFontDisableSmall")

    Label(panel, "GroupBuff SUI by " .. ns.AUTHOR .. "  ·  " .. ns.CREDIT_LINE, 16, -540, "GameFontDisableSmall")

    Button(panel, L.DOCK.BUTTON, 130, 22, 335, -12, function() Config:OpenDock() end)
    Button(panel, L.VIEW.BUTTON, 120, 22, 470, -12, function() Config:OpenView() end)

    panel:SetScript("OnShow", function() Config:Refresh() end)

    -- In die Blizzard-Optionen einhängen; ohne Settings-API als eigenes Fenster
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        Config.category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(Config.category)
        -- Unterkategorie "Ansicht"; scheitert sie, bleibt die Hauptseite nutzbar
        pcall(function()
            if Settings.RegisterCanvasLayoutSubcategory then
                viewPanel = BuildView()
                Config.viewCategory = Settings.RegisterCanvasLayoutSubcategory(Config.category, viewPanel, viewPanel.name)
            end
        end)
        pcall(function()
            if Settings.RegisterCanvasLayoutSubcategory then
                dockPanel = BuildDock()
                Config.dockCategory = Settings.RegisterCanvasLayoutSubcategory(Config.category, dockPanel, dockPanel.name)
            end
        end)
    else
        panel:SetParent(UIParent)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.06, 0.08, 0.95)
        local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        Config.standalone = true
        pcall(function()
            viewPanel = BuildView()
            viewPanel:SetParent(UIParent)
            viewPanel:SetPoint("CENTER", 40, -20)
            viewPanel:SetFrameStrata("DIALOG")
            viewPanel:SetMovable(true)
            viewPanel:EnableMouse(true)
            viewPanel:RegisterForDrag("LeftButton")
            viewPanel:SetScript("OnDragStart", viewPanel.StartMoving)
            viewPanel:SetScript("OnDragStop", viewPanel.StopMovingOrSizing)
            local vbg = viewPanel:CreateTexture(nil, "BACKGROUND")
            vbg:SetAllPoints()
            vbg:SetColorTexture(0.05, 0.06, 0.08, 0.95)
            local vclose = CreateFrame("Button", nil, viewPanel, "UIPanelCloseButton")
            vclose:SetPoint("TOPRIGHT", -4, -4)
        end)
        pcall(function()
            dockPanel = BuildDock()
            dockPanel:SetParent(UIParent)
            dockPanel:SetPoint("CENTER", 80, -40)
            dockPanel:SetFrameStrata("DIALOG")
            dockPanel:SetMovable(true)
            dockPanel:EnableMouse(true)
            dockPanel:RegisterForDrag("LeftButton")
            dockPanel:SetScript("OnDragStart", dockPanel.StartMoving)
            dockPanel:SetScript("OnDragStop", dockPanel.StopMovingOrSizing)
            local dbg = dockPanel:CreateTexture(nil, "BACKGROUND")
            dbg:SetAllPoints()
            dbg:SetColorTexture(0.05, 0.06, 0.08, 0.95)
            local dclose = CreateFrame("Button", nil, dockPanel, "UIPanelCloseButton")
            dclose:SetPoint("TOPRIGHT", -4, -4)
        end)
    end
end


---------------------------------------------------------------------------
-- Unterseite "Ansicht": nur Darstellung, Standardwerte = bisheriges Aussehen
---------------------------------------------------------------------------
local VIEW_TOGGLES = {
    { "corners", 1 }, { "sectionFrames", 1 }, { "sectionTitles", 1 }, { "credits", 1 },
    { "classColors", 2 }, { "zebra", 2 }, { "pulse", 2 }, { "badges", 2 }, { "gear", 1 },
}
local VIEW_STEPPERS = {
    -- { Schlüssel, Schritt, min, max, Einheit }
    { "bgAlpha", 5, 0, 100, " %" }, { "combatAlpha", 5, 0, 100, " %" },
    { "iconSize", 2, 24, 56, " px" }, { "rowSize", 2, 16, 30, " px" }, { "nameWidth", 10, 60, 150, " px" },
}
local VIEW_CYCLES = {
    { "rows", { "auto", "all", "missing" } },
    { "sort", { "missing", "name", "class" } },
}

local function ApplyView()
    if InCombatLockdown() then
        print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE)
        return
    end
    if ns.UI then ns.UI:ApplySettings() end
    if ns.Schedule then ns.Schedule(0) end
end

function Config:RefreshView()
    if not viewPanel or not ns.DB then return end
    local v = ns.DB.view
    for key, cb in pairs(viewChecks) do cb:SetChecked(v[key] and true or false) end
    for _, st in ipairs(VIEW_STEPPERS) do
        viewValues[st[1]]:SetText((v[st[1]] or 0) .. st[5])
    end
    for _, cy in ipairs(VIEW_CYCLES) do
        viewCycle[cy[1]]:SetText(L.VIEW[cy[1]:upper() .. "_V"][v[cy[1]]] or v[cy[1]])
    end
    for name, b in pairs(viewAccent) do
        b:SetText((v.accent == name and "> " or "") .. L.VIEW.ACCENTS[name])
    end
end

BuildView = function()
    local vp = CreateFrame("Frame", "GroupBuffSUIViewOptions")
    vp.name = L.VIEW.TITLE
    vp:SetSize(600, 560)
    vp:Hide()

    Label(vp, L.VIEW.HEADLINE, 16, -14, "GameFontNormalLarge")

    -- Akzentfarbe
    Label(vp, L.VIEW.ACCENT, 16, -52)
    for i, name in ipairs(ns.ACCENT_ORDER) do
        viewAccent[name] = Button(vp, "", 82, 22, 130 + (i - 1) * 86, -48, function()
            ns.DB.view.accent = name
            ApplyView(); Config:RefreshView()
        end)
    end

    -- Zahlenwerte
    for i, st in ipairs(VIEW_STEPPERS) do
        local key, step, lo, hi = st[1], st[2], st[3], st[4]
        local y = -88 - (i - 1) * 32
        viewValues[key] = Stepper(vp, y, L.VIEW[key:upper()], step,
            function()
                local v = ns.DB.view
                v[key] = math.max(lo, (v[key] or lo) - step)
                ApplyView(); Config:RefreshView()
            end,
            function()
                local v = ns.DB.view
                v[key] = math.min(hi, (v[key] or lo) + step)
                ApplyView(); Config:RefreshView()
            end)
    end

    -- Auswahl: Zeilenanzeige und Sortierung
    for i, cy in ipairs(VIEW_CYCLES) do
        local key, opts = cy[1], cy[2]
        local y = -258 - (i - 1) * 32
        Label(vp, L.VIEW[key:upper()], 16, y)
        viewCycle[key] = Button(vp, "", 160, 22, 220, y + 4, function()
            local v = ns.DB.view
            local idx = 1
            for n, o in ipairs(opts) do if o == v[key] then idx = n end end
            v[key] = opts[idx % #opts + 1]
            ApplyView(); Config:RefreshView()
        end)
    end

    -- Schalter
    local rowIdx = { 0, 0 }
    for _, t in ipairs(VIEW_TOGGLES) do
        local key, col = t[1], t[2]
        local cb = CreateFrame("CheckButton", nil, vp, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 12 + (col - 1) * 290, -330 - rowIdx[col] * 28)
        rowIdx[col] = rowIdx[col] + 1
        local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(L.VIEW.T[key])
        cb:SetScript("OnClick", function(self)
            ns.DB.view[key] = self:GetChecked() and true or false
            ApplyView()
        end)
        viewChecks[key] = cb
    end

    Button(vp, L.VIEW.RESET, 200, 24, 16, -482, function()
        if InCombatLockdown() then print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE); return end
        for k, d in pairs(ns.DefaultView) do ns.DB.view[k] = d end
        ApplyView(); Config:RefreshView()
    end)
    Label(vp, L.VIEW.HINT, 16, -514, "GameFontDisableSmall")
    Label(vp, "GroupBuff SUI by " .. ns.AUTHOR .. "  ·  " .. ns.CREDIT_LINE, 16, -540, "GameFontDisableSmall")

    vp:SetScript("OnShow", function() Config:RefreshView() end)
    return vp
end

function Config:OpenView()
    if Config.failed or not viewPanel then
        print("|cff33ff99GroupBuff SUI|r:", L.CFG.UNAVAILABLE)
        return
    end
    if Config.standalone then
        if viewPanel:IsShown() then viewPanel:Hide() else viewPanel:Show() end
    elseif Settings and Settings.OpenToCategory and Config.viewCategory then
        if InCombatLockdown() then
            print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE)
            return
        end
        Settings.OpenToCategory(Config.viewCategory:GetID())
    end
end

---------------------------------------------------------------------------
-- Unterseite "SpartanUI-Dock"
---------------------------------------------------------------------------
local DOCK_STEPPERS = {
    { "dockX", "X", -2000, 2000, 10, " px" }, { "dockY", "Y", -2000, 2000, 10, " px" },
    { "dockAlpha", "ALPHA", 0, 100, 10, " %" }, { "dockShade", "SHADE", 0, 80, 10, " %" },
}

local function ApplyDock()
    if InCombatLockdown() then
        print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE)
        return
    end
    if ns.UI then ns.UI:ApplySettings() end
    if ns.Schedule then ns.Schedule(0) end
end

function Config:RefreshDock()
    if not dockPanel or not ns.DB then return end
    local v = ns.DB.view
    for key, cb in pairs(dockChecks) do cb:SetChecked(v[key] and true or false) end
    for _, st in ipairs(DOCK_STEPPERS) do dockValues[st[1]]:SetText((v[st[1]] or 0) .. st[6]) end
    dockStyle:SetText(L.DOCK.STYLE_V[v.dockStyle] or tostring(v.dockStyle))
    dockSide:SetText(L.DOCK.SIDE_V[v.dockSide] or v.dockSide)
    local ok = ns.Dock and ns.Dock:Available()
    dockStatus:SetText((ok and "|cff6fe08a" or "|cffffb347") .. (ok and L.DOCK.STATUS_OK or L.DOCK.STATUS_NO) .. "|r")
end

BuildDock = function()
    local dp = CreateFrame("Frame", "GroupBuffSUIDockOptions")
    dp.name = L.DOCK.TITLE
    dp:SetSize(600, 480)
    dp:Hide()

    Label(dp, L.DOCK.HEADLINE, 16, -14, "GameFontNormalLarge")
    dockStatus = Label(dp, "", 16, -44, "GameFontHighlightSmall")
    dockStatus:SetWidth(560)

    local y = -76
    for _, key in ipairs({ "dock", "dockSkin", "dockBorder" }) do
        local cb = CreateFrame("CheckButton", nil, dp, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 12, y)
        y = y - 28
        local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(key == "dock" and L.DOCK.DOCK or (key == "dockSkin" and L.DOCK.SKIN or L.DOCK.BORDER))
        cb:SetScript("OnClick", function(self)
            ns.DB.view[key] = self:GetChecked() and true or false
            ApplyDock(); Config:RefreshDock()
        end)
        dockChecks[key] = cb
    end

    Label(dp, L.DOCK.SIDE, 16, y - 10)
    dockSide = Button(dp, "", 230, 22, 220, y - 6, function()
        local v = ns.DB.view
        local idx = 1
        for n, o in ipairs(ns.DOCK_SIDES) do if o == v.dockSide then idx = n end end
        v.dockSide = ns.DOCK_SIDES[idx % #ns.DOCK_SIDES + 1]
        ApplyDock(); Config:RefreshDock()
    end)
    y = y - 34

    Label(dp, L.DOCK.STYLE, 16, y - 10)
    dockStyle = Button(dp, "", 230, 22, 220, y - 6, function()
        local v = ns.DB.view
        v.dockStyle = (v.dockStyle == "flat") and "classic" or "flat"
        ApplyDock(); Config:RefreshDock()
    end)
    y = y - 34

    for _, st in ipairs(DOCK_STEPPERS) do
        local key, lo, hi, step = st[1], st[3], st[4], st[5]
        dockValues[key] = Stepper(dp, y, L.DOCK[st[2]], step,
            function()
                local v = ns.DB.view
                v[key] = math.max(lo, (v[key] or 0) - step)
                ApplyDock(); Config:RefreshDock()
            end,
            function()
                local v = ns.DB.view
                v[key] = math.min(hi, (v[key] or 0) + step)
                ApplyDock(); Config:RefreshDock()
            end)
        y = y - 32
    end

    Button(dp, L.DOCK.RESET, 200, 24, 16, y - 8, function()
        if InCombatLockdown() then print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE); return end
        for _, k in ipairs({ "dock", "dockSkin", "dockSide", "dockX", "dockY", "dockStyle", "dockAlpha", "dockShade", "dockBorder" }) do ns.DB.view[k] = ns.DefaultView[k] end
        ApplyDock(); Config:RefreshDock()
    end)
    local hint = Label(dp, L.DOCK.HINT, 16, y - 44, "GameFontDisableSmall")
    hint:SetWidth(560)
    Label(dp, "GroupBuff SUI by " .. ns.AUTHOR .. "  ·  " .. ns.CREDIT_LINE, 16, -458, "GameFontDisableSmall")

    dp:SetScript("OnShow", function() Config:RefreshDock() end)
    return dp
end

function Config:OpenDock()
    if Config.failed or not dockPanel then
        print("|cff33ff99GroupBuff SUI|r:", L.CFG.UNAVAILABLE)
        return
    end
    if Config.standalone then
        if dockPanel:IsShown() then dockPanel:Hide() else dockPanel:Show() end
    elseif Settings and Settings.OpenToCategory and Config.dockCategory then
        if InCombatLockdown() then
            print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE)
            return
        end
        Settings.OpenToCategory(Config.dockCategory:GetID())
    end
end

function Config:Create()
    local ok, err = pcall(Build)
    if not ok then
        Config.failed = true
        if ns.DB and ns.DB.debug then geterrorhandler()(err) end
    end
end

function Config:Open()
    if Config.failed or not panel then
        print("|cff33ff99GroupBuff SUI|r:", L.CFG.UNAVAILABLE)
        return
    end
    if Config.standalone then
        if panel:IsShown() then panel:Hide() else panel:Show() end
    elseif Settings and Settings.OpenToCategory and Config.category then
        if InCombatLockdown() then
            print("|cff33ff99GroupBuff SUI|r:", L.COMBAT_NOTE)
            return
        end
        Settings.OpenToCategory(Config.category:GetID())
    end
end
