-- client/cl_cuff.lua
-- Cuffs mit Winkel-Logik:
--  - angle "back": komplett immobil (keine Bewegung)
--  - angle "front": Gehen erlaubt (Prisoner-Moveclip)
-- Officer spielt IMMER ND-Officer-Anim (mp_arresting:a_uncuff) bei Cuff/Uncuff/Angle-Change.

local LABEL_TOGGLE   = 'Fesseln / Entfesseln'
local LABEL_TO_FRONT = 'Fesseln nach vorne legen'
local LABEL_TO_BACK  = 'Fesseln nach hinten legen (&Fußfesseln)'

_G.G5G_IS_CUFFED = false
local G5G_CUFF_ANGLE = nil -- "back" | "front" | nil

-- Animsets
local pairDict   = 'mp_arrest_paired'        -- nur für Ziel (crook) beim Anlegen
local pairCrook  = 'crook_p2_back_right'

local cuffAnims = {
    back  = { dict = 'mp_arresting',                name = 'idle' },
    front = { dict = 'anim@move_m@prisoner_cuffed', name = 'idle' }
}
local moveClip = 'move_m@prisoner_cuffed'

local disableThread, ensureThread, immobilizeThread = nil, nil, nil

-- ========================= Hilfsfunktionen =========================

local function requestDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do Wait(0) end
    end
end

local function requestClipset(set)
    if not HasAnimSetLoaded(set) then
        RequestAnimSet(set)
        while not HasAnimSetLoaded(set) do Wait(0) end
    end
end

local function stopIfPlaying(ped, dict, name, blendOut)
    if IsEntityPlayingAnim(ped, dict, name, 3) then
        StopAnimTask(ped, dict, name, blendOut or 2.0)
        return true
    end
    return false
end

local function playIdleForAngle(force)
    if not G5G_CUFF_ANGLE then return end
    local ped = PlayerPedId()
    local a = cuffAnims[G5G_CUFF_ANGLE]
    if not a then return end
    requestDict(a.dict)
    if force or not IsEntityPlayingAnim(ped, a.dict, a.name, 3) then
        TaskPlayAnim(ped, a.dict, a.name, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end
    SetEnableHandcuffs(ped, true)
    SetPedCanPlayGestureAnims(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
end

local function applyMoveClip()
    local ped = PlayerPedId()
    requestClipset(moveClip)
    SetPedMovementClipset(ped, moveClip, 0.20)
    SetEnableHandcuffs(ped, true)
end

local function clearCuffVisuals()
    local ped = PlayerPedId()
    stopIfPlaying(ped, pairDict, pairCrook, 2.0)
    for _,v in pairs(cuffAnims) do stopIfPlaying(ped, v.dict, v.name, 2.0) end
    stopIfPlaying(ped, 'mp_arresting', 'a_uncuff', 2.0)
    stopIfPlaying(ped, 'mp_arresting', 'b_uncuff', 2.0)

    ResetPedMovementClipset(ped, 0.25)
    ClearPedTasks(ped)
    SetEnableHandcuffs(ped, false)
    SetPedCanPlayGestureAnims(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, false)
end

-- ========================= Steuerungs-Blockade =========================

local function startDisableLoop()
    if disableThread then return end
    disableThread = CreateThread(function()
        while _G.G5G_IS_CUFFED do
            local pid = PlayerId()
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisablePlayerFiring(pid, true)
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(27, 75, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 20,  true)
            DisableControlAction(0, 244, true)
            if G5G_CUFF_ANGLE == 'back' then
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
            end
            Wait(0)
        end
        disableThread = nil
    end)
end

local function startEnsureLoop()
    if ensureThread then return end
    ensureThread = CreateThread(function()
        local tick = 0
        while _G.G5G_IS_CUFFED do
            local ped = PlayerPedId()
            if G5G_CUFF_ANGLE == 'front' then
                applyMoveClip()
            else
                ResetPedMovementClipset(ped, 0.25)
            end
            if G5G_CUFF_ANGLE then
                local a = cuffAnims[G5G_CUFF_ANGLE]
                if a and not IsEntityPlayingAnim(ped, a.dict, a.name, 3) then
                    playIdleForAngle(true)
                end
            end
            tick = tick + 1
            if tick >= 12 and G5G_CUFF_ANGLE then
                playIdleForAngle(true)
                tick = 0
            end
            Wait(250)
        end
        ensureThread = nil
    end)
end

local function startImmobilizeLoop()
    if immobilizeThread then return end
    immobilizeThread = CreateThread(function()
        while _G.G5G_IS_CUFFED and G5G_CUFF_ANGLE == 'back' do
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) and not IsEntityAttached(ped) then
                TaskStandStill(ped, 1000)
            end
            Wait(900)
        end
        immobilizeThread = nil
    end)
end

-- ========================= Events =========================

RegisterNetEvent('g5g:interact:cuff:pairAnim', function(role)
    local ped = PlayerPedId()
    if role == 'cop' then
        requestDict('mp_arresting')
        TaskPlayAnim(ped, 'mp_arresting', 'a_uncuff', 8.0, -8.0, 1000, 33, 0.0, false, false, false)
        Wait(1000)
        ClearPedTasks(ped)
        return
    end
    requestDict(pairDict)
    TaskPlayAnim(ped, pairDict, pairCrook, 8.0, -8.0, 3500, 16, 0.0, false, false, false)
end)

RegisterNetEvent('g5g:interact:cuff:set', function(state, angle)
    _G.G5G_IS_CUFFED = state and true or false
    G5G_CUFF_ANGLE   = angle
    local ped = PlayerPedId()
    if _G.G5G_IS_CUFFED then
        playIdleForAngle(true)
        startDisableLoop()
        startEnsureLoop()
        if G5G_CUFF_ANGLE == 'back' then startImmobilizeLoop() end
    else
        clearCuffVisuals()
        G5G_CUFF_ANGLE = nil
    end
end)

RegisterNetEvent('g5g:interact:cuff:updateAngle', function(angle)
    if not _G.G5G_IS_CUFFED then return end
    G5G_CUFF_ANGLE = angle
    local ped = PlayerPedId()
    playIdleForAngle(true)
    if angle == 'front' then
        applyMoveClip()
    else
        startImmobilizeLoop()
        ResetPedMovementClipset(ped, 0.25)
    end
end)

-- ========================= ox_target =========================

CreateThread(function()
    while not exports.ox_target do Wait(100) end

    local function getServerIdFromPed(ped)
        if not ped or ped == 0 then return nil end
        local idx = NetworkGetPlayerIndexFromPed(ped)
        if not idx or idx == -1 then return nil end
        return GetPlayerServerId(idx)
    end

    exports.ox_target:addGlobalPlayer({
        {
            name = 'g5g_cuff_toggle',
            icon = 'fa-solid fa-handcuffs',
            label = LABEL_TOGGLE,
            distance = 3.0,
            canInteract = function(entity)
                return (not _G.G5G_IS_CUFFED) and IsPedAPlayer(entity)
            end,
            onSelect = function(data)
                local sid = getServerIdFromPed(data.entity)
                if sid then TriggerServerEvent('g5g:interact:cuff:toggle', sid) end
            end
        },
        {
            name = 'g5g_cuff_to_front',
            icon = 'fa-solid fa-arrow-right-arrow-left',
            label = LABEL_TO_FRONT,
            distance = 2.5,
            canInteract = function(entity)
                if not IsPedAPlayer(entity) then return false end
                local sid = getServerIdFromPed(entity); if not sid then return false end
                local st  = Player(sid).state
                return st and st.isCuffed == true and st.cuffAngle == 'back'
            end,
            onSelect = function(data)
                local sid = getServerIdFromPed(data.entity)
                if sid then TriggerServerEvent('g5g:interact:cuff:setAngle', sid, 'front') end
            end
        },
        {
            name = 'g5g_cuff_to_back',
            icon = 'fa-solid fa-repeat',
            label = LABEL_TO_BACK,
            distance = 2.5,
            canInteract = function(entity)
                if not IsPedAPlayer(entity) then return false end
                local sid = getServerIdFromPed(entity); if not sid then return false end
                local st  = Player(sid).state
                return st and st.isCuffed == true and st.cuffAngle == 'front'
            end,
            onSelect = function(data)
                local sid = getServerIdFromPed(data.entity)
                if sid then TriggerServerEvent('g5g:interact:cuff:setAngle', sid, 'back') end
            end
        }
    })
end)
