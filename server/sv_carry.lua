-- server/sv_carry.lua
-- Tragen nur bei gefesseltem Ziel. Server hält die Pairings & stoppt verlässlich.

local REQUIRE_CUFFED        = true
local MAX_DIST_BETWEEN_PEDS = 3.0

-- einfache Zustandsverwaltung
local carryingOf = {}  -- [carrierId] = carriedId
local carriedBy  = {}  -- [carriedId] = carrierId

local function isOnline(id)
    return id and GetPlayerPing(id) and GetPlayerPing(id) > 0
end

local function clearPair(carrierId, carriedId)
    if carrierId then carryingOf[carrierId] = nil end
    if carriedId then carriedBy[carriedId] = nil end
    if carrierId or carriedId then
        if carrierId then TriggerClientEvent('g5g:carry:stop', carrierId) end
        if carriedId then TriggerClientEvent('g5g:carry:stop', carriedId) end
    end
end

-- Sicherheits-Stopp, wenn einer leavt
AddEventHandler('playerDropped', function()
    local src = source
    local cBy = carriedBy[src]
    if cBy then clearPair(cBy, src) end
    local cOf = carryingOf[src]
    if cOf then clearPair(src, cOf) end
end)

-- Start tragen anfragen
RegisterNetEvent('g5g:carry:request', function(targetId)
    local src = source
    if not isOnline(targetId) or src == targetId then return end

    -- Darf niemand sonst tragen/getragen werden
    if carryingOf[src] or carriedBy[src] then
        TriggerClientEvent('okokNotify:Alert', src, 'Tragen', 'Du trägst bereits oder wirst getragen.', 3000, 'warning', false)
        return
    end
    if carryingOf[targetId] or carriedBy[targetId] then
        TriggerClientEvent('okokNotify:Alert', src, 'Tragen', 'Ziel ist bereits in einer Trage-Interaktion.', 3000, 'warning', false)
        return
    end

    -- Distanz & Fußgängercheck
    local sp, tp = GetPlayerPed(src), GetPlayerPed(targetId)
    if not sp or not tp then return end
    local sc, tc = GetEntityCoords(sp), GetEntityCoords(tp)
    if #(sc - tc) > MAX_DIST_BETWEEN_PEDS then
        TriggerClientEvent('okokNotify:Alert', src, 'Tragen', 'Zu weit entfernt.', 2500, 'warning', false)
        return
    end
    -- Server: NICHT IsPedInAnyVehicle, sondern GetVehiclePedIsIn ~= 0
    if GetVehiclePedIsIn(sp, false) ~= 0 or GetVehiclePedIsIn(tp, false) ~= 0 then
        TriggerClientEvent('okokNotify:Alert', src, 'Tragen', 'Nicht möglich im/ins Fahrzeug.', 3000, 'warning', false)
        return
    end

    -- Cuffed-Pflicht
    if REQUIRE_CUFFED then
        local ok, cuffed = pcall(function()
            return exports['g5g_interactions']:IsCuffed(targetId) -- Ressourcename ggf. anpassen!
        end)
        if not ok then
            print('[g5g] WARN: IsCuffed-Export nicht erreichbar:', cuffed)
        elseif not cuffed then
            TriggerClientEvent('okokNotify:Alert', src, 'Tragen', 'Ziel ist nicht gefesselt.', 3000, 'warning', false)
            return
        end
    end

    -- NetID des Ziels für Client-Attach (optional hilfreich; Attach geht auch mit ServerId)
    local carriedPed = GetPlayerPed(targetId)
    local carriedNetId = NetworkGetNetworkIdFromEntity(carriedPed)

    -- Status setzen
    carryingOf[src] = targetId
    carriedBy[targetId] = src

    -- Beide Clients starten
    TriggerClientEvent('g5g:carry:start', src, src, targetId, carriedNetId)
    TriggerClientEvent('g5g:carry:start', targetId, src, targetId, carriedNetId)

    -- Kleines Refresh nach 1s, falls Stream/NetID noch nicht da
    SetTimeout(1000, function()
        if carriedBy[targetId] == src then
            TriggerClientEvent('g5g:carry:refreshAttach', targetId, src, targetId)
        end
    end)
end)

-- Stop durch Carrier (oder failsafe)
RegisterNetEvent('g5g:carry:stopRequest', function()
    local src = source
    local tgt = carryingOf[src]
    if tgt then
        clearPair(src, tgt)
        return
    end
    local carr = carriedBy[src]
    if carr then
        clearPair(carr, src)
        return
    end
end)

-- Sicherheits-Stopps bei Sonderfällen
-- 1) Wenn Carrier in ein Fahrzeug geht: Stopp
CreateThread(function()
    while true do
        for carrierId, carriedId in pairs(carryingOf) do
            if isOnline(carrierId) and isOnline(carriedId) then
                local cp = GetPlayerPed(carrierId)
                if cp and GetVehiclePedIsIn(cp, false) ~= 0 then
                    clearPair(carrierId, carriedId)
                end
            else
                clearPair(carrierId, carriedId)
            end
        end
        Wait(500)
    end
end)
