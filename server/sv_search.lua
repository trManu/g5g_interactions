-- server/sv_search.lua
-- Serverseitige Prüfung + Öffnen des Zielinventars beim Anfragenden

local SEARCH_MAX_DIST = 3.0
local REQUIRE_CUFFED  = true   -- auf true lassen, wenn nur gefesselte Spieler durchsucht werden dürfen

local function isOnline(id)
    return id and GetPlayerPing(id) and GetPlayerPing(id) > 0
end

RegisterNetEvent('g5g:interact:search:open', function(targetId)
    local src = source
    if not isOnline(targetId) or src == targetId then
        TriggerClientEvent('okokNotify:Alert', src, 'Durchsuchen', 'Ziel nicht verfügbar.', 3000, 'error', false)
        return
    end

    -- Distanz prüfen (Server)
    local srcPed    = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)
    if not srcPed or not targetPed then return end

    local srcCoords    = GetEntityCoords(srcPed)
    local targetCoords = GetEntityCoords(targetPed)
    if #(srcCoords - targetCoords) > SEARCH_MAX_DIST then
        TriggerClientEvent('okokNotify:Alert', src, 'Durchsuchen', 'Zu weit weg.', 2500, 'error', false)
        return
    end

    -- Optional: nur gefesselte Ziele erlauben (nutzt Export aus deinem Cuff-Serverfile)
    if REQUIRE_CUFFED then
        local ok, cuffed = pcall(function()
            -- ACHTUNG: Ressourcename hier anpassen, falls abweichend!
            return exports['g5g_interactions']:IsCuffed(targetId)
        end)
        if not ok then
            -- Falls Export nicht gefunden: keine harte Sperre, aber Hinweis
            print(('[g5g] WARN: IsCuffed-Export nicht erreichbar (%s)'):format(cuffed))
        elseif not cuffed then
            TriggerClientEvent('okokNotify:Alert', src, 'Durchsuchen', 'Ziel ist nicht gefesselt.', 3000, 'warning', false)
            return
        end
    end

    -- Inventar öffnen (ox_inventory): öffnet beim Anfragenden das Inventar des Zielspielers
    -- Variante A: Serverseitig den Client-Event an den Anfragenden schicken:
    TriggerClientEvent('ox_inventory:openInventory', src, 'player', targetId)

    -- (Alternative Variante B – direkt per Server-Export, je nach Version:)
    -- exports.ox_inventory:OpenInventory(src, 'player', targetId)
end)
