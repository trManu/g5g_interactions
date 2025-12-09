-- server/sv_cuff.lua
-- Statebags + Cuff-System mit front/back-Winkel
-- Auto-Winkel: via Heading -> Forward-Vektor (serverseitig kompatibel)

local cuffed = {}
local cuffAngle = {}

local function isOnline(id) return id and GetPlayerPing(id) end

-- serverseitig: Heading -> Forward-Vektor (wie clientseitiges GetEntityForwardVector)
local function headingToForwardVec(headingDeg)
    local rad = math.rad(headingDeg)
    -- GTA: forward = (-sin(h), cos(h), 0)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

-- berechnet "front" / "back" anhand Officer-Position relativ zur Blickrichtung des Targets
local function computeAngle(src, targetId)
    local pedSrc    = GetPlayerPed(src)
    local pedTarget = GetPlayerPed(targetId)
    if pedSrc == 0 or pedTarget == 0 then return 'back' end

    local tCoords   = GetEntityCoords(pedTarget)
    local sCoords   = GetEntityCoords(pedSrc)

    -- Blickrichtung des Targets aus Heading ableiten
    local tHeading  = GetEntityHeading(pedTarget) or 0.0
    local fwd       = headingToForwardVec(tHeading)

    -- Vektor vom Target zum Officer
    local vec       = vector3(sCoords.x - tCoords.x, sCoords.y - tCoords.y, sCoords.z - tCoords.z)
    local len       = #(vec)
    if len < 0.001 then return 'back' end

    local nVec = vec / len
    local fLen = #(fwd)
    if fLen < 0.001 then return 'back' end
    local nFwd = fwd / fLen

    local dot = nVec.x * nFwd.x + nVec.y * nFwd.y + nVec.z * nFwd.z
    -- Officer steht VOR dem Target -> "front"; sonst "back"
    return (dot > 0.0) and 'front' or 'back'
end

-- Toggle Cuffs
RegisterNetEvent('g5g:interact:cuff:toggle', function(targetId)
    local src = source
    if not isOnline(targetId) or src == targetId then return end

    local becomingCuffed = not cuffed[targetId]
    cuffed[targetId] = becomingCuffed

    if becomingCuffed then
        -- Winkel anhand der relativen Position bestimmen (serverkompatibel)
        local angle = computeAngle(src, targetId)
        cuffAngle[targetId] = angle

        -- Officer- & Ziel-Animationen (Ziel nur beim ANLEGEN eine kurze paired-Reaktion)
        TriggerClientEvent('g5g:interact:cuff:pairAnim', src, 'cop')
        TriggerClientEvent('g5g:interact:cuff:pairAnim', targetId, 'crook')

        -- Statebags setzen
        local st = Player(targetId).state
        st:set('isCuffed', true,  true)
        st:set('cuffAngle', angle, true)

        -- Client-Visuals mit Winkel
        TriggerClientEvent('g5g:interact:cuff:set', targetId, true, angle)
    else
        -- Entfesseln: Officer-Anim, Ziel KEINE Anim
        TriggerClientEvent('g5g:interact:cuff:pairAnim', src, 'cop')

        cuffAngle[targetId] = nil
        local st = Player(targetId).state
        st:set('isCuffed', false, true)
        st:set('cuffAngle', false, true)

        TriggerClientEvent('g5g:interact:cuff:set', targetId, false, nil)
    end

    if not cuffed[targetId] then
        TriggerClientEvent('g5g:interact:carry:stopTarget', targetId)
    end
end)

-- Winkel manuell ändern (bleibt weiterhin möglich)
RegisterNetEvent('g5g:interact:cuff:setAngle', function(targetId, angle)
    local src = source
    if not isOnline(targetId) or src == targetId then return end
    if not cuffed[targetId] then return end
    if angle ~= 'back' and angle ~= 'front' then return end

    cuffAngle[targetId] = angle
    local st = Player(targetId).state
    st:set('cuffAngle', angle, true)

    TriggerClientEvent('g5g:interact:cuff:pairAnim', src, 'cop')
    TriggerClientEvent('g5g:interact:cuff:updateAngle', targetId, angle)
end)

-- Exports
exports('IsCuffed', function(id) return cuffed[id] == true end)
exports('GetCuffAngle', function(id) return cuffAngle[id] end)
