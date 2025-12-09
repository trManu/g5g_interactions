-- client/cl_puttinveh.lua
-- "Ins Fahrzeug setzen (hinten)" + "Aus Fahrzeug holen (Drag-Out)"
-- Zusätzlich: Drag-Out über Fahrzeug-Hintertüren (ox_target Vehicle Bones).

local LABEL_PUT        = 'Ins Fahrzeug setzen'
local LABEL_PULL       = 'Aus Fahrzeug holen'
local LABEL_PULL_LEFT  = 'Aus Fahrzeug holen'
local LABEL_PULL_RIGHT = 'Aus Fahrzeug holen'

-- =========================================================
-- Hilfsfunktionen
-- =========================================================

local function getServerIdFromPed(ped)
    if not ped or ped == 0 then return nil end
    local idx = NetworkGetPlayerIndexFromPed(ped)
    if not idx or idx == -1 then return nil end
    return GetPlayerServerId(idx)
end

local function getClosestVehicle(maxDist)
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local handle, veh = FindFirstVehicle()
    local closestVeh, closestDist = 0, (maxDist or 6.0) + 0.001
    local success = true
    repeat
        if DoesEntityExist(veh) and not IsEntityDead(veh) then
            local pos = GetEntityCoords(veh)
            local dist = #(origin - pos)
            if dist < closestDist then
                local cls = GetVehicleClass(veh)
                if cls ~= 8 and cls ~= 13 and cls ~= 14 and cls ~= 15 and cls ~= 16 and cls ~= 21 then
                    closestVeh = veh
                    closestDist = dist
                end
            end
        end
        success, veh = FindNextVehicle(handle)
    until not success
    EndFindVehicle(handle)

    if closestVeh ~= 0 and closestDist <= (maxDist or 6.0) then
        return closestVeh, closestDist
    end
    return nil, nil
end

-- Standard-Rearseat-Picker (ohne Seitenbezug)
local function pickRearSeatAny(veh)
    if IsVehicleSeatFree(veh, 1) then return 1 end -- HL
    if IsVehicleSeatFree(veh, 2) then return 2 end -- HR
    if IsVehicleSeatFree(veh, 3) then return 3 end
    if IsVehicleSeatFree(veh, 4) then return 4 end
    return nil
end

-- Bestimme anhand der Distanz zur linken/rechten Hintertür (Bones), welcher Rücksitz gewünscht ist.
local function pickRearSeatByOfficerSide(veh)
    local ped = PlayerPedId()
    local myPos = GetEntityCoords(ped)
    -- Hol Bone-Index
    local boneL = GetEntityBoneIndexByName(veh, 'door_dside_r')  -- HL
    local boneR = GetEntityBoneIndexByName(veh, 'door_pside_r')  -- HR

    local hasL = boneL ~= -1
    local hasR = boneR ~= -1

    -- Falls Fahrzeug die Bones nicht hat, abbrechen -> später Fallback
    if not hasL and not hasR then return nil end

    local distL, distR = 9999.0, 9999.0
    if hasL then
        local posL = GetWorldPositionOfEntityBone(veh, boneL)
        distL = #(myPos - posL)
    end
    if hasR then
        local posR = GetWorldPositionOfEntityBone(veh, boneR)
        distR = #(myPos - posR)
    end

    local preferLeft = distL <= distR
    -- Zuerst den näheren Rücksitz nehmen, wenn frei; sonst den anderen; sonst Fallback
    if preferLeft then
        if IsVehicleSeatFree(veh, 1) then return 1 end
        if IsVehicleSeatFree(veh, 2) then return 2 end
    else
        if IsVehicleSeatFree(veh, 2) then return 2 end
        if IsVehicleSeatFree(veh, 1) then return 1 end
    end
    -- Fallback auf weitere Rücksitze
    if IsVehicleSeatFree(veh, 3) then return 3 end
    if IsVehicleSeatFree(veh, 4) then return 4 end
    return nil
end

local function doorIndexForSeat(seat)
    -- GTA Door Indizes: 0 FL, 1 FR, 2 RL, 3 RR (Standard)
    if seat == 1 then return 2 end -- HL -> Rear Left
    if seat == 2 then return 3 end -- HR -> Rear Right
    -- Fallback: wähle eine Tür, die plausibel ist
    return 2
end

-- =========================================================
-- Put in vehicle (hinten)
-- =========================================================

local function onSelectPutInVeh(data)
    if _G.G5G_IS_CUFFED then return end
    if not data or not data.entity or not IsPedAPlayer(data.entity) then return end

    local targetId = getServerIdFromPed(data.entity)
    if not targetId then return end

    local veh = getClosestVehicle(6.0)
    if not veh then
        exports['okokNotify']:Alert('Ins Fahrzeug', 'Kein geeignetes Fahrzeug in der Nähe.', 3000, 'warning', false)
        return
    end

    -- Sitz anhand Tür-Seite wählen
    local seat = pickRearSeatByOfficerSide(veh)
    if not seat then
        seat = pickRearSeatAny(veh)
    end
    if not seat then
        exports['okokNotify']:Alert('Ins Fahrzeug', 'Kein Rücksitz frei.', 3000, 'warning', false)
        return
    end

    local lock = GetVehicleDoorLockStatus(veh)
    if lock and lock >= 2 then
        exports['okokNotify']:Alert('Ins Fahrzeug', 'Fahrzeug ist versperrt.', 3000, 'error', false)
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then
        exports['okokNotify']:Alert('Ins Fahrzeug', 'Fahrzeug ist nicht netzwerktauglich.', 3000, 'error', false)
        return
    end

    TriggerServerEvent('g5g:interact:putinveh:request', targetId, netId, seat)
end

-- Ziel-Client: tatsächliches Einsteigen
RegisterNetEvent('g5g:interact:putinveh:client', function(netId, seat)
    local ped = PlayerPedId()
    local veh = NetToVeh(netId or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if IsPedInAnyVehicle(ped, false) then return end
    if IsEntityDead(veh) then return end

    ClearPedTasksImmediately(ped)
    SetEnableHandcuffs(ped, true)

    local lock = GetVehicleDoorLockStatus(veh)
    if lock and lock >= 2 then return end

    -- Öffne die passende Hintertür (optisch & Path-Hint)
    local door = doorIndexForSeat(seat or 1)
    SetVehicleDoorOpen(veh, door, false, false)

    -- Versuche normalen Einsteigeweg
    TaskEnterVehicle(ped, veh, 5000, seat or 1, 1.0, 1, 0)

    -- Warte kurz und prüfe, ob wirklich im gewünschten Sitz gelandet
    local t = GetGameTimer()
    local desired = seat or 1
    local gotSeat = -999
    while GetGameTimer() - t < 7000 do
        if IsPedInVehicle(ped, veh, false) then
            -- Finde aktuellen Sitz
            for i = -1, 8 do
                if GetPedInVehicleSeat(veh, i) == ped then gotSeat = i break end
            end
            if gotSeat == desired then
                -- passt -> Tür schließen und fertig
                SetVehicleDoorShut(veh, door, false)
                return
            end
        end
        Wait(50)
    end

    -- Fallback: Wenn falscher Sitz (z. B. vorne rechts) oder nicht eingestiegen -> hart korrigieren
    if not IsPedInVehicle(ped, veh, false) then
        if IsVehicleSeatFree(veh, desired) then
            TaskWarpPedIntoVehicle(ped, veh, desired)
        else
            -- Wenn gewünschter Sitz nicht frei, versuche den jeweils anderen Rücksitz
            local alt = (desired == 1 and 2 or 1)
            if IsVehicleSeatFree(veh, alt) then
                TaskWarpPedIntoVehicle(ped, veh, alt)
            end
        end
    else
        -- Sitzt drin, aber falscher Sitz -> einmal aussteigen und korrekt platzieren
        TaskLeaveVehicle(ped, veh, 0)
        local t2 = GetGameTimer()
        while GetGameTimer() - t2 < 2000 do
            if not IsPedInVehicle(ped, veh, false) then break end
            Wait(25)
        end
        if IsVehicleSeatFree(veh, desired) then
            TaskWarpPedIntoVehicle(ped, veh, desired)
        end
    end

    SetVehicleDoorShut(veh, door, false)
end)

-- =========================================================
-- Drag-Out (Player direkt)
-- =========================================================

local function onSelectDragOutPlayer(data)
    if _G.G5G_IS_CUFFED then return end
    if not data or not data.entity or not IsPedAPlayer(data.entity) then return end

    local targetId = getServerIdFromPed(data.entity)
    if not targetId then return end

    local targetVeh = GetVehiclePedIsIn(data.entity, false)
    if targetVeh == 0 then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Ziel sitzt in keinem Fahrzeug.', 3000, 'warning', false)
        return
    end

    local lock = GetVehicleDoorLockStatus(targetVeh)
    if lock and lock >= 2 then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Fahrzeug ist versperrt.', 3000, 'error', false)
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(targetVeh)
    if not netId or netId == 0 then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Fahrzeug ist nicht netzwerktauglich.', 3000, 'error', false)
        return
    end

    TriggerServerEvent('g5g:interact:dragout:request', targetId, netId)
end

-- Ziel-Client: aussteigen + kurzer Ragdoll für "ziehen"
RegisterNetEvent('g5g:interact:dragout:client', function(netId)
    local ped = PlayerPedId()
    local veh = NetToVeh(netId or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if not IsPedInVehicle(ped, veh, false) then return end

    -- Sitzseite grob schätzen und Tür öffnen
    local seatIdx = -2
    for i = -1, 6 do
        if GetPedInVehicleSeat(veh, i) == ped then seatIdx = i break end
    end
    local door = 1 -- default: vorn rechts
    if seatIdx == 1 or seatIdx == 3 or seatIdx == 5 then
        door = 3 -- HR Tür
    elseif seatIdx == 2 or seatIdx == 4 or seatIdx == 6 then
        door = 2 -- HL Tür
    elseif seatIdx == 0 then
        door = 1
    elseif seatIdx == -1 then
        door = 0
    end
    SetVehicleDoorOpen(veh, door, false, false)

    TaskLeaveVehicle(ped, veh, 0)
    local t = GetGameTimer()
    while GetGameTimer() - t < 4000 do
        if not IsPedInVehicle(ped, veh, false) then break end
        Wait(25)
    end

    if not IsPedInVehicle(ped, veh, false) then
        SetEnableHandcuffs(ped, true)
        SetPedToRagdoll(ped, 1200, 1200, 0, false, false, false)
        Wait(1300)
        SetEnableHandcuffs(ped, true)
        local forward = GetEntityForwardVector(veh)
        SetEntityCoordsNoOffset(ped, GetEntityCoords(ped) + forward * 0.6, false, false, false)
    end

    SetVehicleDoorShut(veh, door, false)
end)

-- =========================================================
-- Drag-Out über Fahrzeug-Hintertüren (Vehicle Bones)
-- =========================================================

local function getRearOccupantForDoor(veh, isLeftDoor)
    local seat = isLeftDoor and 1 or 2 -- 1 = HL, 2 = HR
    if not IsVehicleSeatFree(veh, seat) then
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped and ped ~= 0 then return ped, seat end
    end
    for _, s in ipairs(isLeftDoor and {3,5} or {4,6}) do
        if not IsVehicleSeatFree(veh, s) then
            local ped = GetPedInVehicleSeat(veh, s)
            if ped and ped ~= 0 then return ped, s end
        end
    end
    return nil, nil
end

local function onSelectDragOutViaDoor(data, isLeftDoor)
    if _G.G5G_IS_CUFFED then return end
    local ent = data and data.entity
    if not ent or ent == 0 or not IsEntityAVehicle(ent) then return end

    local veh = ent
    local lock = GetVehicleDoorLockStatus(veh)
    if lock and lock >= 2 then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Fahrzeug ist versperrt.', 3000, 'error', false)
        return
    end

    local ped, _seat = getRearOccupantForDoor(veh, isLeftDoor)
    if not ped then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Kein Insasse auf dieser Rückbankseite.', 3000, 'warning', false)
        return
    end

    if not IsPedAPlayer(ped) then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Insasse ist kein Spieler.', 3000, 'warning', false)
        return
    end

    local targetId = getServerIdFromPed(ped)
    if not targetId then return end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then
        exports['okokNotify']:Alert('Aus Fahrzeug holen', 'Fahrzeug ist nicht netzwerktauglich.', 3000, 'error', false)
        return
    end

    TriggerServerEvent('g5g:interact:dragout:request', targetId, netId)
end

-- =========================================================
-- ox_target Registrierungen (Player + Vehicle Bones)
-- =========================================================

CreateThread(function()
    while not exports.ox_target do Wait(100) end

    -- 1) Aktionen auf PLAYER
    exports.ox_target:addGlobalPlayer({
        {
            name = 'g5g_putinveh',
            icon = 'fa-solid fa-car-side',
            label = LABEL_PUT,
            distance = 3.0,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                return IsPedAPlayer(entity)
            end,
            onSelect = onSelectPutInVeh
        },
        {
            name = 'g5g_dragout_player',
            icon = 'fa-solid fa-person-praying',
            label = LABEL_PULL,
            distance = 3.0,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                return IsPedAPlayer(entity) and IsPedInAnyVehicle(entity, false)
            end,
            onSelect = onSelectDragOutPlayer
        }
    })

    -- 2) Aktionen auf VEHICLE (Hintertür-Bones)
    exports.ox_target:addGlobalVehicle({
        {
            name = 'g5g_dragout_left',
            icon = 'fa-solid fa-person-praying',
            label = LABEL_PULL_LEFT,
            bones = { 'door_dside_r' }, -- HL
            distance = 2.0,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                return IsEntityAVehicle(entity)
            end,
            onSelect = function(data) onSelectDragOutViaDoor(data, true) end
        },
        {
            name = 'g5g_dragout_right',
            icon = 'fa-solid fa-person-praying',
            label = LABEL_PULL_RIGHT,
            bones = { 'door_pside_r' }, -- HR
            distance = 2.0,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                return IsEntityAVehicle(entity)
            end,
            onSelect = function(data) onSelectDragOutViaDoor(data, false) end
        }
    })
end)
