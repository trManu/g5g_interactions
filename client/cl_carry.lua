local LABEL_ESCORT     = 'Eskortieren'
local LABEL_RELEASE    = 'Freigeben'
local LABEL_PUT_IN_VEH = 'Ins Fahrzeug setzen'

local ICON_ESCORT   = 'fa-solid fa-user'
local ICON_RELEASE  = 'fa-solid fa-arrow-down'
local ICON_PUTVEH   = 'fa-solid fa-car-side'

local KEY_RELEASE   = 177 -- INPUT_CELLPHONE_CANCEL

local OFFICER_DICT  = "amb@world_human_drinking@coffee@female@base"
local OFFICER_CLIP  = "base"

local SUS_WALK_DICT = "anim@move_m@prisoner_cuffed"
local SUS_WALK_CLIP = "walk"
local SUS_RUN_DICT  = "anim@move_m@trash"
local SUS_RUN_CLIP  = "run"

-- (Suspect steht leicht rechts-vorne neben dem Officer)
local ATTACH_BONE   = 11816 -- SKEL_Pelvis
local ATTACH_POS    = vector3(0.38, 0.40, 0.0)
local ATTACH_ROT    = vector3(0.0, 0.0, 0.0)

-- Status
local escorting   = false   -- ich bin Officer und führe gerade
local escortedBy  = false   -- ich bin Suspect und werde geführt
local tgtServerId = nil     -- Ziel (Suspect) den ich führe
local offServerId = nil     -- Officer der mich führt

-- Utils
local function reqDict(d)
    if not HasAnimDictLoaded(d) then
        RequestAnimDict(d)
        while not HasAnimDictLoaded(d) do Wait(0) end
    end
end

local function getServerIdFromPed(ped)
    if not DoesEntityExist(ped) or not IsPedAPlayer(ped) then return nil end
    return GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
end

local function showHelpRelease()
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName('Drücke ~INPUT_CELLPHONE_CANCEL~ um freizugeben')
    EndTextCommandDisplayHelp(0, false, false, 1)
end

-- ========= Officer-Seite =========

local officerThread
local function startOfficerEscort(suspectId)
    escorting   = true
    tgtServerId = suspectId

    reqDict(OFFICER_DICT)
    TaskPlayAnim(PlayerPedId(), OFFICER_DICT, OFFICER_CLIP, 8.0, 8.0, -1, 50, 0, false, false, false)

    if officerThread then return end
    officerThread = CreateThread(function()
        while escorting do
            -- Eingaben etwas beschränken wie ND
            DisableControlAction(0, 23, true)  -- Enter vehicle
            DisableControlAction(0, 24, true)  -- Attack
            DisableControlAction(0, 25, true)  -- Aim
            DisableControlAction(0, 37, true)  -- Weapon wheel

            showHelpRelease()
            if IsControlJustPressed(0, KEY_RELEASE) then
                TriggerServerEvent('g5g:carry:stopRequest')
                break
            end

            -- Ziel nicht aus den Augen verlieren: wenn los/weg -> stoppen
            local target = GetPlayerFromServerId(tgtServerId)
            if target <= 0 then break end
            local tPed = GetPlayerPed(target)
            if not DoesEntityExist(tPed) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(tPed)) > 8.0 then
                TriggerServerEvent('g5g:carry:stopRequest')
                break
            end

            Wait(0)
        end
        officerThread = nil
    end)
end

local function stopOfficerEscort()
    escorting   = false
    tgtServerId = nil
    StopAnimTask(PlayerPedId(), OFFICER_DICT, OFFICER_CLIP, 2.0)
end

-- ========= Suspect-Seite =========

local suspectThread
local function setEscorted(officerId)
    escortedBy  = true
    offServerId = officerId

    local dictWalk, clipWalk = SUS_WALK_DICT, SUS_WALK_CLIP
    local dictRun,  clipRun  = SUS_RUN_DICT,  SUS_RUN_CLIP

    while escortedBy do
        local player = GetPlayerFromServerId(offServerId)
        local ped = player > 0 and GetPlayerPed(player) or 0
        if ped == 0 then break end

        -- An Officer anhängen (Pelvis, wie ND_Police)
        if not IsEntityAttachedToEntity(PlayerPedId(), ped) then
            AttachEntityToEntity(
                PlayerPedId(), ped, ATTACH_BONE,
                ATTACH_POS.x, ATTACH_POS.y, ATTACH_POS.z,
                ATTACH_ROT.x, ATTACH_ROT.y, ATTACH_ROT.z,
                false, false, true, true, 2, true
            )
        end

        -- Lauf-/Run-Anim abhängig von Officer-Bewegung
        if IsPedWalking(ped) then
            if not IsEntityPlayingAnim(PlayerPedId(), dictWalk, clipWalk, 3) then
                reqDict(dictWalk)
                TaskPlayAnim(PlayerPedId(), dictWalk, clipWalk, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            end
        elseif IsPedRunning(ped) or IsPedSprinting(ped) then
            if not IsEntityPlayingAnim(PlayerPedId(), dictRun, clipRun, 3) then
                reqDict(dictRun)
                TaskPlayAnim(PlayerPedId(), dictRun, clipRun, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            end
        else
            -- stehen -> beide Bewegungsclips stoppen (wie ND)
            StopAnimTask(PlayerPedId(), dictWalk, clipWalk, -8.0)
            StopAnimTask(PlayerPedId(), dictRun,  clipRun,  -8.0)
        end

        Wait(0)
    end

    -- Aufräumen
    StopAnimTask(PlayerPedId(), SUS_WALK_DICT, SUS_WALK_CLIP, -8.0)
    StopAnimTask(PlayerPedId(), SUS_RUN_DICT,  SUS_RUN_CLIP,  -8.0)
    escortedBy  = false
    suspectThread = nil
    offServerId = nil
end

local function stopSuspectEscort()
    escortedBy  = false
    offServerId = nil
    if IsEntityAttached(PlayerPedId()) then
        DetachEntity(PlayerPedId(), true, false)
    end

    StopAnimTask(PlayerPedId(), SUS_WALK_DICT, SUS_WALK_CLIP, -8.0)
    StopAnimTask(PlayerPedId(), SUS_RUN_DICT,  SUS_RUN_CLIP,  -8.0)
    suspectThread = nil
end

-- ========= Events (Server nutzt weiterhin deine g5g:carry-Events) =========

RegisterNetEvent('g5g:carry:start', function(carrierId, carriedId, _carriedNetId)
    local myId = GetPlayerServerId(PlayerId())
    if myId == carrierId then
        startOfficerEscort(carriedId)
    elseif myId == carriedId then
        if suspectThread then return end
        suspectThread = CreateThread(function() setEscorted(carrierId) end)
    end
end)

-- Re-Attach falls Stream/NetID beim ersten Tick nicht bereit war
RegisterNetEvent('g5g:carry:refreshAttach', function(carrierId, carriedId)
    if not escortedBy or offServerId ~= carrierId then return end
    local player = GetPlayerFromServerId(offServerId)
    local ped = player > 0 and GetPlayerPed(player) or 0
    if ped ~= 0 and not IsEntityAttachedToEntity(PlayerPedId(), ped) then
        AttachEntityToEntity(
            PlayerPedId(), ped, ATTACH_BONE,
            ATTACH_POS.x, ATTACH_POS.y, ATTACH_POS.z,
            ATTACH_ROT.x, ATTACH_ROT.y, ATTACH_ROT.z,
            false, false, true, true, 2, true
        )
    end
end)

RegisterNetEvent('g5g:carry:stop', function()
    if escorting then stopOfficerEscort() end
    if escortedBy then stopSuspectEscort() end
end)

-- ========= ox_target Aktionen =========

-- kleine Helper
local function canEscortTarget(entity)
    return IsPedAPlayer(entity) and IsPedCuffed(entity) and not IsEntityAttachedToEntity(entity, PlayerPedId())
end

local function canReleaseTarget(entity)
    return IsPedAPlayer(entity) and IsPedCuffed(entity) 
        and IsEntityAttachedToEntity(entity, PlayerPedId())
end

-- Officer: Escort
local function onEscortSelect(data)
    if _G.G5G_IS_CUFFED then return end
    local ent = data and data.entity; if not ent then return end
    local sid = getServerIdFromPed(ent); if not sid then return end
    TriggerServerEvent('g5g:carry:request', sid)
end

-- Officer: Release
local function onReleaseSelect(data)
    if _G.G5G_IS_CUFFED then return end
    TriggerServerEvent('g5g:carry:stopRequest')
end

-- Officer: während Escort "Ins Fahrzeug setzen"
local function nearestRearSeat(veh, officerCoords)
    -- Wähle den näheren Rücksitz (HL = 1, HR = 2), mit Fallback auf 3/4, dann 0
    local leftBone  = GetEntityBoneIndexByName(veh, "seat_dside_r")
    local rightBone = GetEntityBoneIndexByName(veh, "seat_pside_r")
    local bestSeat, bestDist

    if leftBone ~= -1 and IsVehicleSeatFree(veh, 1) then
        local pos = GetWorldPositionOfEntityBone(veh, leftBone)
        local d = #(officerCoords - pos)
        bestSeat, bestDist = 1, d
    end
    if rightBone ~= -1 and IsVehicleSeatFree(veh, 2) then
        local pos = GetWorldPositionOfEntityBone(veh, rightBone)
        local d = #(officerCoords - pos)
        if not bestDist or d < bestDist then bestSeat, bestDist = 2, d end
    end
    if not bestSeat and IsVehicleSeatFree(veh, 3) then bestSeat = 3 end
    if not bestSeat and IsVehicleSeatFree(veh, 4) then bestSeat = 4 end
    if not bestSeat and IsVehicleSeatFree(veh, 0) then bestSeat = 0 end
    return bestSeat
end

local function onPutInVehWhileEscort(data)
    if not escorting or not tgtServerId then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        -- nächstes Fahrzeug vor dir suchen
        local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
        veh = GetClosestVehicle(pos.x, pos.y, pos.z, 3.5, 0, 70)
        if veh == 0 then return end
    end

    local seat = nearestRearSeat(veh, coords)
    if not seat then return end

    -- Server kümmert sich um das eigentliche Einsetzen
    TriggerServerEvent('g5g:interact:putinveh:request', tgtServerId, VehToNet(veh), seat)
end

-- ox_target Registrierung
CreateThread(function()
    local ox_target = exports.ox_target
    ox_target:addGlobalPlayer({
        {
            name = 'g5g_nd_escort',
            icon = ICON_ESCORT,
            label = LABEL_ESCORT,
            distance = 1.8,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                return canEscortTarget(entity)
            end,
            onSelect = onEscortSelect
        },
        {
            name = 'g5g_nd_release',
            icon = ICON_RELEASE,
            label = LABEL_RELEASE,
            distance = 1.8,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                return canReleaseTarget(entity)
            end,
            onSelect = onReleaseSelect
        },
        {
            name = 'g5g_nd_putinveh',
            icon = ICON_PUTVEH,
            label = LABEL_PUT_IN_VEH,
            distance = 2.2,
            canInteract = function(entity)
                if _G.G5G_IS_CUFFED then return false end
                -- nur sichtbar, wenn der Officer den Spieler gerade angeheftet hat
                return IsPedAPlayer(entity) and IsEntityAttachedToEntity(entity, PlayerPedId())
            end,
            onSelect = onPutInVehWhileEscort
        }
    })
end)
