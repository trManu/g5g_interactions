-- server/sv_puttinveh.lua
-- Put-In und Drag-Out: prüft Distanz, Cuff-Status, Türschloss. Sitz-Checks laufen clientseitig.

local MAX_DIST_PED_TO_VEH   = 6.0
local MAX_DIST_BETWEEN_PEDS = 4.0
local REQUIRE_CUFFED        = true   -- Ziel muss gefesselt sein

local function isOnline(id)
    return id and GetPlayerPing(id) and GetPlayerPing(id) > 0
end

-- ====== PUT IN VEH ======
RegisterNetEvent('g5g:interact:putinveh:request', function(targetId, vehNetId, seat)
    local src = source
    if not isOnline(targetId) or src == targetId then
        TriggerClientEvent('okokNotify:Alert', src, 'Ins Fahrzeug', 'Ziel nicht verfügbar.', 3000, 'error', false)
        return
    end
    if not vehNetId or vehNetId == 0 then return end

    local srcPed, tgtPed = GetPlayerPed(src), GetPlayerPed(targetId)
    if not srcPed or not tgtPed then return end

    local srcCoords, tgtCoords = GetEntityCoords(srcPed), GetEntityCoords(tgtPed)
    if #(srcCoords - tgtCoords) > MAX_DIST_BETWEEN_PEDS then
        TriggerClientEvent('okokNotify:Alert', src, 'Ins Fahrzeug', 'Zu weit vom Ziel entfernt.', 2500, 'warning', false)
        return
    end

    local veh = NetworkGetEntityFromNetworkId(vehNetId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        TriggerClientEvent('okokNotify:Alert', src, 'Ins Fahrzeug', 'Fahrzeug nicht verfügbar.', 3000, 'error', false)
        return
    end

    local vehCoords = GetEntityCoords(veh)
    if #(srcCoords - vehCoords) > MAX_DIST_PED_TO_VEH then
        TriggerClientEvent('okokNotify:Alert', src, 'Ins Fahrzeug', 'Fahrzeug ist zu weit entfernt.', 2500, 'warning', false)
        return
    end

    if REQUIRE_CUFFED then
        local ok, cuffed = pcall(function()
            return exports['g5g_interactions']:IsCuffed(targetId) -- ggf. Ressourcename anpassen
        end)
        if not ok then
            print('[g5g] WARN: IsCuffed-Export nicht erreichbar:', cuffed)
        elseif not cuffed then
            TriggerClientEvent('okokNotify:Alert', src, 'Ins Fahrzeug', 'Ziel ist nicht gefesselt.', 3000, 'warning', false)
            return
        end
    end

    local lock = GetVehicleDoorLockStatus(veh)
    if lock and lock >= 2 then
        TriggerClientEvent('okokNotify:Alert', src, 'Ins Fahrzeug', 'Fahrzeug ist versperrt.', 3000, 'error', false)
        return
    end

    TriggerClientEvent('g5g:interact:putinveh:client', targetId, vehNetId, seat)
end)

-- ====== DRAG OUT ======
RegisterNetEvent('g5g:interact:dragout:request', function(targetId, vehNetId)
    local src = source
    if not isOnline(targetId) or src == targetId then
        TriggerClientEvent('okokNotify:Alert', src, 'Aus Fahrzeug holen', 'Ziel nicht verfügbar.', 3000, 'error', false)
        return
    end
    if not vehNetId or vehNetId == 0 then return end

    local srcPed, tgtPed = GetPlayerPed(src), GetPlayerPed(targetId)
    if not srcPed or not tgtPed then return end

    local srcCoords, tgtCoords = GetEntityCoords(srcPed), GetEntityCoords(tgtPed)
    if #(srcCoords - tgtCoords) > MAX_DIST_BETWEEN_PEDS then
        TriggerClientEvent('okokNotify:Alert', src, 'Aus Fahrzeug holen', 'Zu weit vom Ziel entfernt.', 2500, 'warning', false)
        return
    end

    local veh = NetworkGetEntityFromNetworkId(vehNetId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        TriggerClientEvent('okokNotify:Alert', src, 'Aus Fahrzeug holen', 'Fahrzeug nicht verfügbar.', 3000, 'error', false)
        return
    end

    local vehCoords = GetEntityCoords(veh)
    if #(srcCoords - vehCoords) > MAX_DIST_PED_TO_VEH then
        TriggerClientEvent('okokNotify:Alert', src, 'Aus Fahrzeug holen', 'Fahrzeug ist zu weit entfernt.', 2500, 'warning', false)
        return
    end

    if REQUIRE_CUFFED then
        local ok, cuffed = pcall(function()
            return exports['g5g_interactions']:IsCuffed(targetId)
        end)
        if not ok then
            print('[g5g] WARN: IsCuffed-Export nicht erreichbar:', cuffed)
        elseif not cuffed then
            TriggerClientEvent('okokNotify:Alert', src, 'Aus Fahrzeug holen', 'Ziel ist nicht gefesselt.', 3000, 'warning', false)
            return
        end
    end

    local lock = GetVehicleDoorLockStatus(veh)
    if lock and lock >= 2 then
        TriggerClientEvent('okokNotify:Alert', src, 'Aus Fahrzeug holen', 'Fahrzeug ist versperrt.', 3000, 'error', false)
        return
    end

    -- Ziel-Client aussteigen lassen
    TriggerClientEvent('g5g:interact:dragout:client', targetId, vehNetId)
end)
