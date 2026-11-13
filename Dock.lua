local ADDON, ns = ...
local L = ns.L

-- SpartanUI-Dock: hängt das Fenster an das Classic-Artwork von SpartanUI.
-- Nutzt nur lesend das globale SUI-Objekt und die Artwork-Frames (Classic_ActionBarPlate).
-- Ohne SpartanUI oder mit anderem Theme bleibt das Fenster frei verschiebbar wie gewohnt.

local Dock = {}
ns.Dock = Dock

-- Classic-Leistenhintergrund aus dem installierten SpartanUI (wird nur referenziert, nicht kopiert)
local CLASSIC_BG = "Interface\\AddOns\\SpartanUI\\Themes\\Classic\\Images\\bar-backdrop1"
local CLASSIC_TC = { 0.107421875, 0.896484375, 0.25, 0.765625 }

-- Positionen relativ zur Classic-Aktionsleisten-Platte (1002 x 139).
-- Die Seitenleisten von SpartanUI liegen bis ~146 px neben der Platte, daher dieser Abstand.
local SPOTS = {
    left = { "BOTTOMRIGHT", "BOTTOMLEFT", -146, 0 },
    right = { "BOTTOMLEFT", "BOTTOMRIGHT", 146, 0 },
    center = { "BOTTOM", "TOP", 0, 4 },
}
ns.DOCK_SIDES = { "left", "right", "center" }

local function SUIStyle()
    local sui = _G.SUI
    return sui and sui.DB and sui.DB.Artwork and sui.DB.Artwork.Style
end

-- Classic-Artwork von SpartanUI vorhanden und sichtbar? Maßgeblich ist die Platte selbst,
-- nicht die Theme-Einstellung (deren Ablage kann je nach SpartanUI-Version abweichen).
function Dock:Available()
    local plate = _G.Classic_ActionBarPlate
    if not plate or not plate.IsVisible or not plate:IsVisible() then return false end
    local style = SUIStyle()
    return style == nil or style == "Classic"
end

-- Diagnose für /gbs dock debug
function Dock:Debug()
    local function yn(b) return b and "ja" or "nein" end
    local plate = _G.Classic_ActionBarPlate
    local p = print
    p("|cff33ff99GroupBuff SUI|r Dock-Diagnose:")
    p("  SUI-Objekt: " .. yn(_G.SUI ~= nil))
    p("  SUI.DB.Artwork.Style: " .. tostring(SUIStyle()))
    p("  Classic_ActionBarPlate: " .. yn(plate ~= nil) .. (plate and (", sichtbar: " .. yn(plate:IsVisible()) ..
        string.format(", %.0fx%.0f", plate:GetWidth() or 0, plate:GetHeight() or 0)) or ""))
    p("  SUI_Art_Classic: " .. yn(_G.SUI_Art_Classic ~= nil) .. (_G.SUI_Art_Classic and (", sichtbar: " .. yn(_G.SUI_Art_Classic:IsVisible())) or ""))
    p("  Dock verfügbar: " .. yn(Dock:Available()) .. ", aktiv: " .. yn(Dock:IsActive()) .. ", Hintergrund: " .. yn(Dock:IsSkinned()))
    local f = _G.GroupBuffSUIFrame
    if f then
        local pt, rel, rp, x, y = f:GetPoint(1)
        p(string.format("  Fenster: %s an %s (%s) %.0f/%.0f", tostring(pt), rel and rel.GetName and tostring(rel:GetName()) or "?", tostring(rp), x or 0, y or 0))
    end
end

function Dock:IsActive()
    local v = ns.DB and ns.DB.view
    return (v and v.dock and Dock:Available()) and true or false
end

function Dock:IsSkinned()
    local v = ns.DB and ns.DB.view
    return (Dock:IsActive() and v.dockSkin) and true or false
end

local function ArtColor()
    local sui = _G.SUI
    local r, g, b, a = 1, 1, 1, 1
    if sui and sui.ThemeRegistry and sui.ThemeRegistry.GetSetting then
        local ok, c = pcall(sui.ThemeRegistry.GetSetting, sui.ThemeRegistry, "Classic", "Color.Art")
        if ok and type(c) == "table" then r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
    end
    return r, g, b, a
end

-- Fenster an die Platte setzen (nur außerhalb des Kampfes aufrufen)
function Dock:Place(frame)
    local v = ns.DB.view
    local s = SPOTS[v.dockSide] or SPOTS.left
    frame:ClearAllPoints()
    frame:SetPoint(s[1], _G.Classic_ActionBarPlate, s[2], s[3] + (v.dockX or 0), s[4] + (v.dockY or 0))
end

-- Classic-Hintergrund ein-/ausblenden
function Dock:Skin(frame, on)
    if on and not frame.dockBG then
        frame.dockBG = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        frame.dockBG:SetPoint("TOPLEFT", 1, -1)
        frame.dockBG:SetPoint("BOTTOMRIGHT", -1, 1)
        frame.dockBG:SetTexture(CLASSIC_BG)
        frame.dockBG:SetTexCoord(unpack(CLASSIC_TC))
    end
    if frame.dockBG then
        if on then
            frame.dockBG:SetVertexColor(ArtColor())
            frame.dockBG:Show()
        else
            frame.dockBG:Hide()
        end
    end
end

-- Zustand prüfen und bei Änderung (Theme-Wechsel, Option) neu anwenden
local lastSig
function Dock:Sync()
    if InCombatLockdown() or not ns.UI then return end
    local v = ns.DB.view
    local sig = table.concat({ tostring(Dock:IsActive()), tostring(Dock:IsSkinned()), tostring(v.dockSide),
        tostring(v.dockX), tostring(v.dockY), tostring(SUIStyle()) }, "|")
    if sig ~= lastSig then
        lastSig = sig
        ns.UI:ApplySettings()
    end
end
