local ADDON, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Kompatibilität (Forever = Midnight-Engine, 'secret values' im Kampf)
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or function(id) return select(3, GetSpellInfo(id)) end
local IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

local function IsKnown(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    return false
end

local function Print(...)
    print("|cff33ff99GroupBuff SUI|r:", ...)
end

local function Debug(...)
    if ns.DB and ns.DB.debug then Print("|cff999999[debug]|r", ...) end
end

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------
local defaults = {
    locked = false,
    shown = true,
    scale = 1,
    warn = 120,          -- Sekunden Restzeit, ab denen ein Buff als "läuft aus" zählt
    members = true,      -- Mitgliederübersicht
    hideWhenOk = false,  -- Fenster ausblenden, wenn alles gebufft ist
    sound = true,        -- Warnton beim Bereitschaftscheck
    timers = true,       -- Restzeit der Buffs anzeigen
    roleFilter = true,   -- Buffs nur für passende Gruppenrollen prüfen
    expireAlert = true,  -- Hinweis, wenn ein Buff bei mehr als der Hälfte der Gruppe bald ausläuft
    pets = false,        -- Pets/Begleiter der Gruppe in die Prüfung einbeziehen
    consumables = true,  -- eigene Verbrauchsgüter prüfen (nur Kategorien mit eingetragenen IDs)
    weaponCheck = false, -- Waffenverstärkung (Öl/Stein) prüfen
    autoReport = false,  -- beim Bereitschaftscheck fehlende Buffs automatisch in den Gruppenchat schreiben
    collapsed = false,   -- Mitgliederliste eingeklappt
    cons = { flask = {}, food = {}, armor = {} }, -- [Kategorie][SpellID] = true
    roleOverride = {},   -- [Schlüssel] = { TANK = true, ... } überschreibt Data.lua
    debug = false,
    custom = {},         -- [spellID] = { mana = bool }
    point = { "CENTER", "UIParent", "CENTER", 0, 150 },
    -- Ansicht-Optionen: Standardwerte = das bisherige Aussehen
    view = {
        accent = "gold",       -- gold | silver | blue | green | rose
        bgAlpha = 92,          -- Hintergrund-Deckkraft in %
        combatAlpha = 35,      -- Deckkraft im Kampf in %
        iconSize = 36,         -- Größe der Cast-Icons
        rowSize = 22,          -- Zeilenhöhe / Icon-Größe in der Gruppenliste
        nameWidth = 90,        -- Breite der Namensspalte
        corners = true,        -- goldene Eckzierden
        sectionFrames = true,  -- Rahmen um die Bereiche
        sectionTitles = true,  -- Bereichsüberschriften
        credits = true,        -- "by Solomon" im Titel
        classColors = true,    -- Namen in Klassenfarbe
        zebra = true,          -- Zeilenstreifen
        pulse = true,          -- pulsierender Rahmen bei fehlendem Buff
        badges = true,         -- Anzahl-Zahl auf den Cast-Icons
        gear = true,           -- Zahnrad in der Kopfzeile (öffnet die Optionen)
        dock = true,           -- an SpartanUI (Classic-Artwork) andocken, wenn vorhanden
        dockSkin = true,       -- Classic-Hintergrund von SpartanUI verwenden
        dockSide = "left",     -- left | right | center
        dockX = 0,             -- Feinabstimmung
        dockY = 0,
        rows = "auto",         -- auto | all | missing
        sort = "missing",      -- missing | name | class
    },
}
ns.DefaultView = defaults.view

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                MergeDefaults(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "custom" and k ~= "point" then
            MergeDefaults(dst[k], v)
        end
    end
end

---------------------------------------------------------------------------
-- Aktive Buff-Familien (nur Zauber, die DER SPIELER wirklich kennt)
---------------------------------------------------------------------------
local active = {}

local function BuildFamilies()
    local list = {}
    for _, f in ipairs(ns.FAMILIES) do list[#list + 1] = f end
    for id, c in pairs(ns.DB.custom) do
        list[#list + 1] = { key = "c" .. id, cast = { id }, mana = c.mana, roles = c.roles, pets = c.pets }
    end

    wipe(active)
    for _, f in ipairs(list) do
        local castId
        for _, id in ipairs(f.cast) do
            if IsKnown(id) then castId = id; break end
        end
        if castId then
            local name = GetSpellName(castId)
            if name then
                local names, ids = { [name] = true }, {}
                for _, id in ipairs(f.cast) do
                    ids[id] = true
                    local n = GetSpellName(id)
                    if n then names[n] = true end
                end
                for _, id in ipairs(f.alt or {}) do
                    ids[id] = true
                    local n = GetSpellName(id)
                    if n then names[n] = true end
                end
                active[#active + 1] = {
                    key = f.key, castId = castId, name = name,
                    icon = GetSpellTexture(castId), names = names, ids = ids, mana = f.mana, roles = f.roles, pets = f.pets,
                }
            end
        end
    end
    Debug("aktive Buff-Familien:", #active)
end

---------------------------------------------------------------------------
-- Gruppe scannen
---------------------------------------------------------------------------
local function IsPetUnit(unit)
    return unit:find("pet", 1, true) ~= nil
end

-- liefert (Spieler-Einheiten, Pet-Einheiten)
local function GroupUnits()
    local units, pets = {}, {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = "raid" .. i
            pets[#pets + 1] = "raidpet" .. i
        end
    else
        units[1] = "player"
        pets[1] = "pet"
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
            pets[#pets + 1] = "partypet" .. i
        end
    end
    return units, pets
end

local function Eligible(unit, fam)
    if not UnitExists(unit) or not UnitIsConnected(unit) or not UnitIsVisible(unit) then return false end
    if UnitIsDeadOrGhost(unit) or not UnitIsFriend("player", unit) then return false end
    if IsPetUnit(unit) and not fam.pets then return false end
    if fam.mana and (UnitPowerMax(unit, 0) or 0) <= 0 then return false end
    if ns.DB.roleFilter then
        local roles = ns.DB.roleOverride[fam.key] or fam.roles
        if roles then
            local role = UnitGroupRolesAssigned(unit)
            if role and role ~= "NONE" and not roles[role] then return false end
        end
    end
    return true
end

-- liefert found[key] = { rem = Restsekunden (math.huge = permanent), dur = Gesamtdauer }
local function ScanUnit(unit)
    local found, secret = {}, false
    for i = 1, 80 do
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        local name, sid = a.name, a.spellId
        if issecret(name) or issecret(sid) then
            secret = true
        else
            local exp, dur = a.expirationTime, a.duration
            local rem = math.huge
            if exp and not issecret(exp) and exp > 0 then rem = exp - GetTime() end
            if issecret(dur) then dur = nil end
            for _, f in ipairs(active) do
                if (name and f.names[name]) or (sid and f.ids[sid]) then
                    local prev = found[f.key]
                    if not prev or rem > prev.rem then
                        found[f.key] = { rem = rem, dur = dur }
                    end
                end
            end
        end
    end
    return found, secret
end

local function InRange(famInfo, unit)
    if UnitIsUnit(unit, "player") then return true end
    if not IsSpellInRange then return true end
    local r = IsSpellInRange(famInfo.castId, unit)
    return r ~= false
end

---------------------------------------------------------------------------
-- Verbrauchsgüter (nur der eigene Charakter)
---------------------------------------------------------------------------
local CONS_KEYS = { "flask", "food", "armor" }

local function ConsLabel(key)
    return L.CONS[key] or key
end

local function ConsLabels(list)
    local t = {}
    for _, e in ipairs(list) do t[#t + 1] = ConsLabel(e.key) end
    return table.concat(t, ", ")
end

-- Liefert { missing = { {key=} }, expiring = { {key=, rem=} } }
local function CheckConsumables()
    local res = { missing = {}, expiring = {} }
    local DB = ns.DB
    if not DB.consumables then return res end

    -- Nachschlagetabellen je Kategorie (nur Kategorien mit mindestens einer ID)
    local cats = {}
    for _, key in ipairs(CONS_KEYS) do
        local set = DB.cons[key]
        if set and next(set) then
            local ids, names = {}, {}
            for id in pairs(set) do
                ids[id] = true
                local n = GetSpellName(id)
                if n then names[n] = true end
            end
            cats[key] = { ids = ids, names = names }
        end
    end

    local best = {} -- [Kategorie] = größte Restzeit
    if next(cats) then
        for i = 1, 80 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            local name, sid = a.name, a.spellId
            if not issecret(name) and not issecret(sid) then
                local exp = a.expirationTime
                local rem = math.huge
                if exp and not issecret(exp) and exp > 0 then rem = exp - GetTime() end
                for key, c in pairs(cats) do
                    if (name and c.names[name]) or (sid and c.ids[sid]) then
                        if not best[key] or rem > best[key] then best[key] = rem end
                    end
                end
            end
        end
    end

    for _, key in ipairs(CONS_KEYS) do
        if cats[key] then
            local rem = best[key]
            if not rem then
                res.missing[#res.missing + 1] = { key = key }
            elseif rem ~= math.huge and rem <= DB.warn then
                res.expiring[#res.expiring + 1] = { key = key, rem = rem }
            end
        end
    end

    -- Waffenverstärkung über die Waffen-API (keine Spell-IDs nötig)
    if DB.weaponCheck and GetWeaponEnchantInfo and GetInventoryItemID("player", 16) then
        local hasMH, mhExp = GetWeaponEnchantInfo()
        if not issecret(hasMH) then
            if not hasMH then
                res.missing[#res.missing + 1] = { key = "weapon" }
            elseif mhExp and not issecret(mhExp) and mhExp / 1000 <= DB.warn then
                res.expiring[#res.expiring + 1] = { key = "weapon", rem = mhExp / 1000 }
            end
        end
    end
    return res
end

local alertAt = {} -- [Schlüssel] = Zeitpunkt der letzten Meldung

local model = { missing = {}, rows = {}, fams = {}, groupSize = 0, expiring = {}, cons = { missing = {}, expiring = {} } }
ns.model = model

local function Refresh()
    if InCombatLockdown() then
        ns.pending = true
        if ns.UI then ns.UI:SetCombat(true) end
        return
    end
    ns.pending = false

    local units, petUnits = GroupUnits()
    local scanList = {}
    for _, u in ipairs(units) do scanList[#scanList + 1] = u end
    if ns.DB.pets then
        for _, u in ipairs(petUnits) do scanList[#scanList + 1] = u end
    end
    local missingByKey, famOrder = {}, {}
    local rows = {}
    local elig, expc, minr = {}, {}, {}

    for _, unit in ipairs(scanList) do
        if UnitExists(unit) then
            local found, secret = ScanUnit(unit)
            local row = {
                unit = unit,
                name = (UnitName(unit) or unit) .. (IsPetUnit(unit) and L.PET or ""),
                class = select(2, UnitClass(unit)),
                status = {}, rem = {}, missing = 0,
            }
            for _, f in ipairs(active) do
                local st
                if not Eligible(unit, f) then
                    st = "na"
                elseif secret then
                    st = "unknown"
                else
                    local r = found[f.key]
                    local thr = ns.DB.warn
                    if r and r.dur and r.dur < 600 then thr = math.min(thr, 30) end
                    if not r then
                        st = "missing"
                    elseif r.rem <= thr then
                        st = "expiring"
                    else
                        st = "ok"
                    end
                    -- Restzeit merken (permanente Buffs haben math.huge und bekommen keinen Timer)
                    if r and r.rem ~= math.huge then row.rem[f.key] = r.rem end
                end
                row.status[f.key] = st
                if st ~= "na" and st ~= "unknown" then
                    elig[f.key] = (elig[f.key] or 0) + 1
                    if st == "expiring" then
                        expc[f.key] = (expc[f.key] or 0) + 1
                        local rr = row.rem[f.key]
                        if rr and (not minr[f.key] or rr < minr[f.key]) then minr[f.key] = rr end
                    end
                end
                if st == "missing" or st == "expiring" then
                    row.missing = row.missing + 1
                    local m = missingByKey[f.key]
                    if not m then
                        m = { fam = f, units = {} }
                        missingByKey[f.key] = m
                        famOrder[#famOrder + 1] = m
                    end
                    m.units[#m.units + 1] = {
                        unit = unit, name = row.name, class = row.class,
                        state = st, inRange = InRange(f, unit), rem = row.rem[f.key],
                    }
                end
            end
            rows[#rows + 1] = row
        end
    end

    -- Cast-Ziel pro fehlendem Buff: erster Spieler in Reichweite
    for _, m in ipairs(famOrder) do
        local pick
        for _, u in ipairs(m.units) do
            if u.inRange then pick = u; break end
        end
        pick = pick or m.units[1]
        m.target, m.targetName, m.inRange = pick.unit, pick.name, pick.inRange
        -- kürzeste Restzeit unter den auslaufenden Buffs (für den Cast-Button)
        for _, u in ipairs(m.units) do
            if u.state == "expiring" and u.rem and (not m.minRem or u.rem < m.minRem) then
                m.minRem = u.rem
            end
        end
    end

    -- Mitgliederübersicht: im 5er alle, im Schlachtzug nur Betroffene
    local view = ns.DB.view or ns.DefaultView
    local showAll = view.rows == "all" or (view.rows ~= "missing" and #units <= 5)
    local shown = {}
    for _, r in ipairs(rows) do
        if showAll or r.missing > 0 then shown[#shown + 1] = r end
    end
    local sortMode = view.sort
    table.sort(shown, function(a, b)
        if sortMode == "name" then
            return a.name < b.name
        elseif sortMode == "class" then
            local ca, cb = a.class or "", b.class or ""
            if ca ~= cb then return ca < cb end
            return a.name < b.name
        end
        if a.missing ~= b.missing then return a.missing > b.missing end
        return a.name < b.name
    end)

    -- Buffs, die bei mehr als der Hälfte der Gruppe bald auslaufen
    local expiring, nowExpiring = {}, {}
    for _, f in ipairs(active) do
        local n, total = expc[f.key] or 0, elig[f.key] or 0
        if total >= 2 and n * 2 > total then
            expiring[#expiring + 1] = { fam = f, n = n, total = total, minRem = minr[f.key] }
            nowExpiring[f.key] = true
        end
    end
    for key in pairs(alertAt) do
        if not nowExpiring[key] then alertAt[key] = nil end -- darf später erneut melden
    end

    model.missing, model.rows, model.fams, model.groupSize = famOrder, shown, active, #units
    model.expiring = expiring
    model.cons = CheckConsumables()
    ns.UI:Render(model)

    if ns.DB.expireAlert then
        local now = GetTime()
        for _, e in ipairs(expiring) do
            if not alertAt[e.fam.key] then
                alertAt[e.fam.key] = now
                local t = e.minRem and ns.FormatTime(e.minRem) or "?"
                local msg = string.format(L.EXPIRE_ALERT, e.fam.name, e.n, e.total, t)
                Print("|cffffb347" .. msg .. "|r")
                if RaidNotice_AddMessage and RaidWarningFrame then
                    pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
                end
            end
        end
    end
end

local scheduled = false
local function Run()
    scheduled = false
    local ok, err = pcall(Refresh)
    if not ok then
        Debug("Fehler:", err)
        if ns.DB.debug then geterrorhandler()(err) end
    end
end

local function Schedule(delay)
    if scheduled then return end
    scheduled = true
    C_Timer.After(delay or 0.3, Run)
end
ns.Schedule = Schedule
ns.BuildFamilies = BuildFamilies

---------------------------------------------------------------------------
-- Berichte / Bereitschaftscheck
---------------------------------------------------------------------------
local function MissingSummary(withNames)
    local parts = {}
    for _, m in ipairs(model.missing) do
        if withNames then
            local names = {}
            for i, u in ipairs(m.units) do
                if i > 5 then names[#names + 1] = string.format(L.MORE, #m.units - 5); break end
                names[#names + 1] = u.name
            end
            parts[#parts + 1] = m.fam.name .. " (" .. table.concat(names, ", ") .. ")"
        else
            parts[#parts + 1] = m.fam.name
        end
    end
    return table.concat(parts, ", ")
end

local Report -- Vorwärtsdeklaration (unten definiert)
local lastAutoReport = 0

local function OnReadyCheck()
    C_Timer.After(0.4, function()
        Run()
        local cons = model.cons
        if cons and #cons.missing > 0 then
            Print("|cffff5555" .. string.format(L.READY_CONS, ConsLabels(cons.missing)) .. "|r")
        end
        if #model.missing > 0 then
            local msg = string.format(L.READY_CHECK_MISSING, MissingSummary(false))
            Print("|cffff5555" .. msg .. "|r")
            if RaidNotice_AddMessage and RaidWarningFrame then
                pcall(RaidNotice_AddMessage, RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
            end
            if ns.DB.sound and SOUNDKIT then PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3) end

            -- Automatische Chat-Meldung: nur als Leiter/Assistent, höchstens einmal pro Minute
            if ns.DB.autoReport and IsInGroup()
                and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
                and GetTime() - lastAutoReport > 60 then
                lastAutoReport = GetTime()
                Report()
            end
        end
    end)
end

function Report()
    if #model.missing == 0 then Print(L.ALL_OK); return end
    local text = "GroupBuff SUI: " .. MissingSummary(true)
    if #text > 250 then
        -- Chat-Limit 255 Bytes; an einer Zeichengrenze kürzen (Umlaute sind mehrbytig)
        text = text:sub(1, 247):gsub("[\192-\255][\128-\191]*$", "") .. "..."
    end
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = "INSTANCE_CHAT"
    elseif IsInRaid() then channel = "RAID"
    elseif IsInGroup() then channel = "PARTY" end
    if channel then
        local ok = pcall(SendChatMessage, text, channel)
        if ok then return end
    end
    Print(text)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        GroupBuffSUIDB = GroupBuffSUIDB or {}
        MergeDefaults(GroupBuffSUIDB, defaults)
        ns.DB = GroupBuffSUIDB
        ev:UnregisterEvent("ADDON_LOADED")
        ev:RegisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGIN" then
        ns.UI:Create()
        BuildFamilies()
        if ns.Config then ns.Config:Create() end
        Print(L.WELCOME)
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("UNIT_AURA")
        ev:RegisterEvent("SPELLS_CHANGED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("READY_CHECK")
        ev:RegisterEvent("UNIT_PET")
        ev:RegisterEvent("PLAYER_ALIVE")
        ev:RegisterEvent("PLAYER_UNGHOST")
        C_Timer.NewTicker(10, function()
            if not InCombatLockdown() then Schedule(0) end
        end)
        Schedule(1)

    elseif event == "UNIT_AURA" then
        if InCombatLockdown() then return end
        local unit = arg1
        if unit == "player" or unit == "pet" or (type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d")
            or unit:find("^partypet%d") or unit:find("^raidpet%d"))) then
            Schedule(0.5)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.UI:SetCombat(true)

    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.UI:SetCombat(false)
        Schedule(0.5)

    elseif event == "SPELLS_CHANGED" then
        if not InCombatLockdown() then
            BuildFamilies()
            Schedule(0.3)
        end

    elseif event == "READY_CHECK" then
        OnReadyCheck()

    else -- GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD, PLAYER_ALIVE, PLAYER_UNGHOST
        Schedule(0.5)
    end
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------
local ROLE_WORDS = { tank = "TANK", heal = "HEALER", healer = "HEALER", dps = "DAMAGER", damage = "DAMAGER" }

local function ParseFlags(str)
    local mana, roles, pets
    for w in (str or ""):lower():gmatch("%S+") do
        if w == "mana" then
            mana = true
        elseif w == "pets" or w == "pet" then
            pets = true
        elseif ROLE_WORDS[w] then
            roles = roles or {}
            roles[ROLE_WORDS[w]] = true
        end
    end
    return mana, roles, pets
end

local function RolesText(roles)
    if not roles then return "alle" end
    local t = {}
    if roles.TANK then t[#t + 1] = "Tank" end
    if roles.HEALER then t[#t + 1] = "Heiler" end
    if roles.DAMAGER then t[#t + 1] = "Schaden" end
    return table.concat(t, "/")
end

local function FamilyKnown(key)
    for _, f in ipairs(ns.FAMILIES) do
        if f.key == key then return true end
    end
    local id = tonumber(key:match("^c(%d+)$"))
    return id ~= nil and ns.DB.custom[id] ~= nil
end

local function Scan()
    local unit = UnitExists("target") and "target" or "player"
    Print("Buffs auf " .. (UnitName(unit) or unit) .. ":")
    for i = 1, 80 do
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        if issecret(a.name) or issecret(a.spellId) then
            print("  (secret)")
        else
            print(string.format("  [%d] %s", a.spellId or 0, a.name or "?"))
        end
    end
end

local ACCENT_OK = { gold = true, silver = true, blue = true, green = true, rose = true }

SLASH_GROUPBUFFSSUI1 = "/gbs"
SLASH_GROUPBUFFSSUI2 = "/groupbuffsui"
SlashCmdList["GROUPBUFFSSUI"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local DB = ns.DB

    if cmd == "" or cmd == "toggle" then
        DB.shown = not DB.shown
        if InCombatLockdown() then Print(L.COMBAT_NOTE) else ns.UI:ApplySettings(); Schedule(0) end

    elseif cmd == "lock" then
        DB.locked = true; Print(L.LOCKED)
    elseif cmd == "unlock" then
        DB.locked = false; Print(L.UNLOCKED)

    elseif cmd == "scale" then
        local s = tonumber(rest)
        if s and s >= 0.5 and s <= 2 then
            DB.scale = s
            if not InCombatLockdown() then ns.UI:ApplySettings() end
        end

    elseif cmd == "warn" then
        local s = tonumber(rest)
        if s and s >= 0 and s <= 3600 then DB.warn = s; Schedule(0) end

    elseif cmd == "members" then
        DB.members = not DB.members; Schedule(0)
    elseif cmd == "hide" then
        DB.hideWhenOk = not DB.hideWhenOk; Schedule(0)
    elseif cmd == "timers" then
        DB.timers = not DB.timers
        Print("Timer: " .. (DB.timers and "an" or "aus"))
        Schedule(0)
    elseif cmd == "alert" then
        DB.expireAlert = not DB.expireAlert
        Print("Ablauf-Hinweis: " .. (DB.expireAlert and "an" or "aus"))
        Schedule(0)
    elseif cmd == "sound" then
        DB.sound = not DB.sound
        Print("Sound: " .. (DB.sound and "an" or "aus"))
    elseif cmd == "debug" then
        DB.debug = not DB.debug
        Print("Debug: " .. (DB.debug and "an" or "aus"))

    elseif cmd == "scan" then
        Scan()

    elseif cmd == "add" then
        local idStr, flags = rest:match("^(%d+)%s*(.-)$")
        local id = tonumber(idStr)
        local name = id and GetSpellName(id)
        if not name then Print(string.format(L.BAD_ID, rest)); return end
        local mana, roles, pets = ParseFlags(flags)
        DB.custom[id] = { mana = mana, roles = roles, pets = pets }
        Print(string.format(L.ADDED, name, id))
        if not IsKnown(id) then Print("|cffffaa00" .. name .. ": Zauber ist dir nicht bekannt – wird erst aktiv, wenn du ihn gelernt hast.|r") end
        BuildFamilies(); Schedule(0)

    elseif cmd == "del" then
        local id = tonumber(rest)
        if id and DB.custom[id] then
            DB.custom[id] = nil
            Print(string.format(L.REMOVED, id))
            BuildFamilies(); Schedule(0)
        end

    elseif cmd == "list" then
        if #active == 0 then Print(L.NO_SPELLS) end
        for _, f in ipairs(active) do
            print(string.format("  |T%s:14|t %s  Schlüssel: %s  ID: %d%s  Rollen: %s",
                f.icon or 134400, f.name, f.key, f.castId, f.mana and "  [mana]" or "",
                RolesText(DB.roleOverride[f.key] or f.roles)))
        end

    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        if ns.Config then ns.Config:Open() end

    elseif cmd == "autoreport" then
        DB.autoReport = not DB.autoReport
        Print("Auto-Meldung im Chat: " .. (DB.autoReport and "an" or "aus"))

    elseif cmd == "cons" then
        local sub1, cat, idStr = rest:match("^(%S*)%s*(%S*)%s*(%S*)$")
        sub1, cat = (sub1 or ""):lower(), (cat or ""):lower()
        if sub1 == "" then
            DB.consumables = not DB.consumables
            Print("Verbrauchsgüter: " .. (DB.consumables and "an" or "aus"))
            Schedule(0)
        elseif sub1 == "weapon" then
            DB.weaponCheck = not DB.weaponCheck
            Print("Waffenverstärkung: " .. (DB.weaponCheck and "an" or "aus"))
            Schedule(0)
        elseif sub1 == "list" then
            for _, key in ipairs(CONS_KEYS) do
                local ids = {}
                for id in pairs(DB.cons[key] or {}) do ids[#ids + 1] = tostring(id) end
                table.sort(ids)
                print(string.format("  %s: %s", ConsLabel(key), #ids > 0 and table.concat(ids, ", ") or "-"))
            end
        elseif (sub1 == "add" or sub1 == "del") and DB.cons[cat] then
            local id = tonumber(idStr)
            local name = id and GetSpellName(id)
            if not name then Print(string.format(L.BAD_ID, idStr)); return end
            DB.cons[cat][id] = (sub1 == "add") or nil
            Print(string.format(sub1 == "add" and L.CONS_ADDED or L.CONS_REMOVED, name, ConsLabel(cat)))
            Schedule(0)
        else
            Print(L.CONS_USAGE)
        end

    elseif cmd == "pets" then
        DB.pets = not DB.pets
        Print("Pets: " .. (DB.pets and "an" or "aus"))
        Schedule(0)

    elseif cmd == "roles" then
        DB.roleFilter = not DB.roleFilter
        Print("Rollen-Filter: " .. (DB.roleFilter and "an" or "aus"))
        Schedule(0)

    elseif cmd == "role" then
        local keyArg, roleArgs = rest:match("^(%S+)%s*(.-)$")
        if not keyArg then Print(L.ROLE_USAGE); return end
        local key = tonumber(keyArg) and ("c" .. keyArg) or keyArg:lower()
        if not FamilyKnown(key) then Print(string.format(L.ROLE_UNKNOWN, keyArg)); return end
        local word = roleArgs:lower()
        if word == "default" or word == "" then
            DB.roleOverride[key] = nil
        elseif word == "all" or word == "alle" then
            DB.roleOverride[key] = { TANK = true, HEALER = true, DAMAGER = true }
        else
            local _, roles = ParseFlags(roleArgs)
            if not roles then Print(L.ROLE_USAGE); return end
            DB.roleOverride[key] = roles
        end
        Print(string.format(L.ROLE_SET, key, RolesText(DB.roleOverride[key])))
        Schedule(0)

    elseif cmd == "report" then
        Report()

    elseif cmd == "dock" then
        local key, val = rest:match("^(%S*)%s*(.-)$")
        key = key:lower()
        if InCombatLockdown() then Print(L.COMBAT_NOTE); return end
        local v = DB.view
        if key == "debug" then
            if ns.Dock then ns.Dock:Debug() end
            return
        end
        if key == "" or key == "help" then
            Print(ns.Dock and ns.Dock:Available() and L.DOCK.STATUS_OK or L.DOCK.STATUS_NO)
            for _, line in ipairs(L.DOCK.HELP) do print(line) end
            return
        elseif key == "on" then v.dock = true
        elseif key == "off" then v.dock = false
        elseif key == "skin" then v.dockSkin = not v.dockSkin
        elseif key == "left" or key == "right" or key == "center" then v.dockSide = key
        elseif key == "x" and tonumber(val) then v.dockX = math.max(-300, math.min(300, math.floor(tonumber(val))))
        elseif key == "y" and tonumber(val) then v.dockY = math.max(-300, math.min(300, math.floor(tonumber(val))))
        elseif key == "reset" then
            for _, k in ipairs({ "dock", "dockSkin", "dockSide", "dockX", "dockY" }) do v[k] = ns.DefaultView[k] end
        else
            for _, line in ipairs(L.DOCK.HELP) do print(line) end
            return
        end
        ns.UI:ApplySettings(); Schedule(0)
        if ns.Config and ns.Config.RefreshDock then ns.Config:RefreshDock() end

    elseif cmd == "view" then
        local key, val = rest:match("^(%S*)%s*(.-)$")
        key = key:lower()
        if InCombatLockdown() then Print(L.COMBAT_NOTE); return end
        local v = DB.view
        local num = { bgalpha = "bgAlpha", combatalpha = "combatAlpha", iconsize = "iconSize",
            rowsize = "rowSize", namewidth = "nameWidth" }
        local lim = { bgAlpha = { 0, 100 }, combatAlpha = { 0, 100 }, iconSize = { 24, 56 },
            rowSize = { 16, 30 }, nameWidth = { 60, 150 } }
        local bool = { corners = "corners", frames = "sectionFrames", titles = "sectionTitles",
            credits = "credits", gear = "gear", classcolors = "classColors", zebra = "zebra", pulse = "pulse", badges = "badges" }
        if key == "reset" then
            for k, d in pairs(ns.DefaultView) do v[k] = d end
        elseif num[key] then
            local n, f = tonumber(val), num[key]
            if n and n >= lim[f][1] and n <= lim[f][2] then v[f] = math.floor(n) end
        elseif bool[key] then
            v[bool[key]] = not v[bool[key]]
        elseif key == "accent" and ACCENT_OK and ACCENT_OK[val:lower()] then
            v.accent = val:lower()
        elseif key == "rows" and (val == "auto" or val == "all" or val == "missing") then
            v.rows = val
        elseif key == "sort" and (val == "missing" or val == "name" or val == "class") then
            v.sort = val
        else
            for _, line in ipairs(L.VIEW.HELP) do print(line) end
            return
        end
        ns.UI:ApplySettings(); Schedule(0)
        if ns.Config and ns.Config.RefreshView then ns.Config:RefreshView() end

    elseif cmd == "reset" then
        if InCombatLockdown() then Print(L.COMBAT_NOTE); return end
        for k in pairs(DB) do DB[k] = nil end
        MergeDefaults(DB, defaults)
        BuildFamilies(); ns.UI:ApplySettings(); Schedule(0)

    else
        for _, line in ipairs(L.HELP) do print(line) end
    end
end
