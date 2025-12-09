-- client/cl_search.lua
-- Öffnet via ox_target den Eintrag "Durchsuchen" auf Spielers und bittet den Server um Öffnen des Zielinventars.

local LABEL = 'Durchsuchen'

local function getServerIdFromPed(ped)
    if not ped or ped == 0 then return nil end
    local idx = NetworkGetPlayerIndexFromPed(ped)
    if not idx or idx == -1 then return nil end
    return GetPlayerServerId(idx)
end

local function onSelectSearch(data)
    if not data or not data.entity or not IsPedAPlayer(data.entity) then return end
    local targetId = getServerIdFromPed(data.entity)
    if not targetId then return end
    -- Anfrage an den Server: prüft Distanz, Cuff-Status etc. und öffnet dann das Inventar
    TriggerServerEvent('g5g:interact:search:open', targetId)
end

CreateThread(function()
    while not exports.ox_target do Wait(100) end
    exports.ox_target:addGlobalPlayer({
        {
            name = 'g5g_playersearch_open',
            icon = 'fa-solid fa-magnifying-glass',
            label = LABEL,
            distance = 3.0,
            canInteract = function(entity, distance, coords, name, bone)
                -- Optional: Selbst gesperrt, wenn man gefesselt ist (falls du den Global-State setzt)
                if _G.G5G_IS_CUFFED then return false end
                return IsPedAPlayer(entity)
            end,
            onSelect = onSelectSearch
        }
    })
end)
