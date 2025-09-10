--[[
    SpellbinderTimer – WoW 1.12.1 (Vanilla)

    FUNKTIONSÜBERSICHT
    -------------------
    • Startet einen 5:15-Timer (315 s) jedes Mal, wenn der Kampflog-Text
      "Scarlet Spellbinder dies." (EN) oder
      "Scharlachroter Zauberbinder stirbt." (DE)
      auftaucht – völlig egal, WER den Spellbinder getötet hat.
      → Spawn-/Respawn-Überwachung.

    • Erhöht den Anzeigezähler "Kills" NUR dann, wenn DER TEXT
      "You have slain Scarlet Spellbinder!"
      im Log erscheint — das ist deine persönliche "Du hast getötet"-Meldung.

    • UI ist verschiebbar; Position wird gespeichert; bis zu 10 parallele Timer.
]]

--------------------------------------------------
-- Allgemeine Addon-Parameter
--------------------------------------------------
local ADDON_NAME = "Rashock - Spellbinder Farm Timer"
local MAX_TIMERS  = 10
local DURATION    = 315 -- 5:15

-- Zonennamen exakt wie in 1.12
local TARGET_ZONE_DE = "Westliche Pestländer"
local TARGET_ZONE_EN = "Western Plaguelands"

--------------------------------------------------
-- SavedVariables (persistenter Speicher)
-- In der TOC MUSS stehen:  ## SavedVariables: Rashock_SpellbinderFarmTimerDB
--------------------------------------------------
if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then
    Rashock_SpellbinderFarmTimerDB = {}
end
-- Persistente Timerliste: Jeder Eintrag = { start = epochSekunden }
if type(Rashock_SpellbinderFarmTimerDB.timers) ~= "table" then
    Rashock_SpellbinderFarmTimerDB.timers = {}
end
-- Kills (eigene)
local killCount = 0
if type(Rashock_SpellbinderFarmTimerDB.kills) == "number" then
    killCount = Rashock_SpellbinderFarmTimerDB.kills
else
    Rashock_SpellbinderFarmTimerDB.kills = 0
end

--------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------
local function InTargetZone()
    local z = GetRealZoneText()
    return (z == TARGET_ZONE_DE) or (z == TARGET_ZONE_EN)
end

-- MM:SS formatter (Lua 5.0 → math.mod statt %)
local function fmt(mmss)
    local m = math.floor(mmss / 60)
    local s = math.floor(math.mod(mmss, 60))
    if m < 10 then m = "0"..m end
    if s < 10 then s = "0"..s end
    return tostring(m)..":"..tostring(s)
end

-- Todestext (Timer für alle Kills)
local function IsScarletSpellbinderDeath(msg)
    if msg == "Scarlet Spellbinder dies." then return true end
    if msg == "Scharlachroter Zauberbinder stirbt." then return true end
    return false
end

-- Eigener Kill (nur DEINE Zeile)
local function IsMyScarletSpellbinderKill(msg)
    if msg == "You have slain Scarlet Spellbinder!" then return true end
    -- falls DE-Client eine eigene Zeile liefert:
    -- if msg == "Ihr habt Scharlachroten Zauberbinder getötet!" then return true end
    return false
end

-- Epoch-Sekunden (für Persistenz)
local function NowEpoch()
    if type(time) == "function" then
        return time()
    else
        return nil
    end
end

--------------------------------------------------
-- UI (Fenster)
--------------------------------------------------
local main = CreateFrame("Frame", "Rashock_SpellbinderFarmTimerFrame", UIParent)
main:SetClampedToScreen(true)
main:SetWidth(220); main:SetHeight(240)
main:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
main:EnableMouse(true); main:SetMovable(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", function() main:StartMoving() end)
main:SetScript("OnDragStop", function()
    main:StopMovingOrSizing()
    if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
    local point, _, relPoint, xOfs, yOfs = main:GetPoint()
    Rashock_SpellbinderFarmTimerDB.point    = point
    Rashock_SpellbinderFarmTimerDB.relPoint = relPoint
    Rashock_SpellbinderFarmTimerDB.xOfs     = xOfs
    Rashock_SpellbinderFarmTimerDB.yOfs     = yOfs
end)

main:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
main:SetBackdropColor(0, 0, 0, 0.7)

local title = main:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
title:SetPoint("TOP", 0, -8)
title:SetText("Rashock: Spellbinder Farm Timer")

local zoneInfo = main:CreateFontString(nil, "ARTWORK", "GameFontNormal")
zoneInfo:SetPoint("TOP", title, "BOTTOM", 0, -4)
zoneInfo:SetText("Nur in Westl. Pestl./Western Plaguelands aktiv")

local killInfo = main:CreateFontString(nil, "ARTWORK", "GameFontNormal")
killInfo:SetPoint("TOPLEFT", zoneInfo, "BOTTOMLEFT", 0, -4)
killInfo:SetText("Kills: "..killCount)

local rows = {}
for i = 1, MAX_TIMERS do
    local fs = main:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    if i == 1 then
        fs:SetPoint("TOPLEFT", killInfo, "BOTTOMLEFT", 8, -8)
    else
        fs:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -4)
    end
    fs:SetText("")
    rows[i] = fs
end

-- Slash-Commands
SlashCmdList["SPELLBINDER_TIMER"] = function()
    if main:IsShown() then main:Hide() else main:Show() end
end
SLASH_SPELLBINDER_TIMER1 = "/sbt"

SlashCmdList["SPELLBINDER_TIMER_RESET"] = function()
    killCount = 0
    if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
    Rashock_SpellbinderFarmTimerDB.kills = 0
    killInfo:SetText("Kills: 0")
end
SLASH_SPELLBINDER_TIMER_RESET1 = "/sbtreset"

--------------------------------------------------
-- Timer-Logik (EINMALIG!)
--------------------------------------------------
-- Eine gemeinsame aktive Liste
local active = {}
-- Entprellung für doppelte Todesevents
local lastTimerStart = 0

-- Neuen Timer hinzufügen (UI + Persistenz)
local function AddTimer()
    if table.getn(active) >= MAX_TIMERS then return end

    local nowSess = GetTime()
    if nowSess - lastTimerStart < 1.0 then return end  -- Entprellung 1s
    lastTimerStart = nowSess

    -- UI-Laufzeit
    table.insert(active, { expires = nowSess + DURATION })

    -- Persistenz absichern
    if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
    if type(Rashock_SpellbinderFarmTimerDB.timers) ~= "table" then Rashock_SpellbinderFarmTimerDB.timers = {} end

    local epochNow = NowEpoch()
    if epochNow then
        table.insert(Rashock_SpellbinderFarmTimerDB.timers, { start = epochNow })
    end
end

-- Abgelaufene Timer aus UI und DB entfernen
local function PruneTimers()
    local nowSess = GetTime()
    local nowAbs  = NowEpoch()

    -- UI-Liste
    local keep = {}
    for i = 1, table.getn(active) do
        local t = active[i]
        if t and t.expires > nowSess then
            table.insert(keep, t)
        end
    end
    active = keep

    -- DB-Liste
    if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
    if type(Rashock_SpellbinderFarmTimerDB.timers) ~= "table" then Rashock_SpellbinderFarmTimerDB.timers = {} end

    if nowAbs then
        local keepDB = {}
        for i = 1, table.getn(Rashock_SpellbinderFarmTimerDB.timers) do
            local rec = Rashock_SpellbinderFarmTimerDB.timers[i]
            if rec and type(rec.start) == "number" then
                local age = nowAbs - rec.start
                if age < DURATION then
                    table.insert(keepDB, rec)
                end
            end
        end
        Rashock_SpellbinderFarmTimerDB.timers = keepDB
    end
end

-- OnUpdate (gedrosselt ~10 Hz)
local accum = 0
local lastUpdate = GetTime()
main:SetScript("OnUpdate", function()
    local now = GetTime()
    local dt = now - lastUpdate
    if dt < 0 then dt = 0 end
    lastUpdate = now

    accum = accum + dt
    if accum < 0.1 then return end
    accum = 0

    PruneTimers()
    table.sort(active, function(a,b) return a.expires < b.expires end)

    for i = 1, MAX_TIMERS do
        local line = rows[i]
        local t = active[i]
        if t then
            local remain = math.max(0, t.expires - now)
            line:SetText(string.format("%d) %s", i, fmt(remain)))
        else
            line:SetText("")
        end
    end

    killInfo:SetText("Kills: "..killCount)
end)

--------------------------------------------------
-- Events
--------------------------------------------------
local function SavePosition()
    if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
    local point, _, relPoint, xOfs, yOfs = main:GetPoint()
    Rashock_SpellbinderFarmTimerDB.point = point
    Rashock_SpellbinderFarmTimerDB.relPoint = relPoint
    Rashock_SpellbinderFarmTimerDB.xOfs = xOfs
    Rashock_SpellbinderFarmTimerDB.yOfs = yOfs
end

local function EventHandler()
    if event == "PLAYER_LOGIN" then
        -- Fensterposition
        if type(Rashock_SpellbinderFarmTimerDB) == "table" and Rashock_SpellbinderFarmTimerDB.point then
            main:ClearAllPoints()
            main:SetPoint(Rashock_SpellbinderFarmTimerDB.point, UIParent, Rashock_SpellbinderFarmTimerDB.relPoint, Rashock_SpellbinderFarmTimerDB.xOfs, Rashock_SpellbinderFarmTimerDB.yOfs)
        end

        -- Zonenfarbe
        if InTargetZone() then zoneInfo:SetTextColor(0.4, 1.0, 0.4) else zoneInfo:SetTextColor(1.0, 0.4, 0.4) end

        -- Timer aus DB rekonstruieren
        do
            local nowAbs = NowEpoch()
            if nowAbs and type(Rashock_SpellbinderFarmTimerDB.timers) == "table" then
                active = {}
                for i = 1, table.getn(Rashock_SpellbinderFarmTimerDB.timers) do
                    local rec = Rashock_SpellbinderFarmTimerDB.timers[i]
                    if rec and type(rec.start) == "number" then
                        local age = nowAbs - rec.start
                        if age >= 0 and age < DURATION then
                            local remain = DURATION - age
                            table.insert(active, { expires = GetTime() + remain })
                        end
                    end
                end
                PruneTimers()
                table.sort(active, function(a,b) return a.expires < b.expires end)
            end
        end

        -- Kills laden
        killCount = (type(Rashock_SpellbinderFarmTimerDB.kills) == "number" and Rashock_SpellbinderFarmTimerDB.kills) or 0
        killInfo:SetText("Kills: "..killCount)

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        if InTargetZone() then zoneInfo:SetTextColor(0.4, 1.0, 0.4) else zoneInfo:SetTextColor(1.0, 0.4, 0.4) end

    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        local msg = arg1
        if not InTargetZone() then return end

        -- Timer für alle Kills
        if IsScarletSpellbinderDeath(msg) then
            AddTimer()
        end

        -- Eigener Kill (falls über dieses Event geliefert)
        if IsMyScarletSpellbinderKill(msg) then
            killCount = (killCount or 0) + 1
            if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
            Rashock_SpellbinderFarmTimerDB.kills = killCount
            killInfo:SetText("Kills: "..killCount)
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        -- Fallback: falls "You have slain ..." als Systemzeile kommt
        local msg = arg1
        if InTargetZone() and IsMyScarletSpellbinderKill(msg) then
            killCount = (killCount or 0) + 1
            if type(Rashock_SpellbinderFarmTimerDB) ~= "table" then Rashock_SpellbinderFarmTimerDB = {} end
            Rashock_SpellbinderFarmTimerDB.kills = killCount
            killInfo:SetText("Kills: "..killCount)
        end

    elseif event == "PLAYER_LOGOUT" then
        SavePosition()
    end
end

main:SetScript("OnEvent", EventHandler)
main:RegisterEvent("PLAYER_LOGIN")
main:RegisterEvent("PLAYER_ENTERING_WORLD")
main:RegisterEvent("ZONE_CHANGED")
main:RegisterEvent("ZONE_CHANGED_NEW_AREA")
main:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
main:RegisterEvent("CHAT_MSG_SYSTEM")   -- Fallback für "You have slain ..."
main:RegisterEvent("PLAYER_LOGOUT")


-- 17:32 Grand Inquisitor Isillien yells: You will not make it to the forest's edge, Fordring. 
-- 17:35 Highlord Taelan Fording yells: Isillien!


-- 21:06 Lord Tirion Fordring says: Look what they did to my boy. 
--26:35