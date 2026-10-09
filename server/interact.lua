local function checkPresence(src, door, maxDist)
    if GetPlayerRoutingBucket(src) ~= door.bucket then
        return false, 'bucket'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'distance' end
    local dist = #(GetEntityCoords(ped) - Doors.center(door.id))
    if dist > maxDist + Config.Doors.distances.serverTolerance then
        return false, 'distance'
    end
    return true
end

local function denied(src, door, reason)
    pcall(Hooks.onAccessDenied, src, Utils.deepCopy(door), reason)
end

lib.callback.register('g_doorlock:getDoors', function(src)
    while not Doors.ready do Wait(100) end
    return Doors.allClientData()
end)

-- doors the player already has access to (PIN not counted), used to hide break-in options
lib.callback.register('g_doorlock:access', function(src, ids)
    local out = {}
    if type(ids) ~= 'table' then return out end
    for i = 1, math.min(#ids, 50) do
        local id = ids[i]
        local door = type(id) == 'string' and Doors.list[id]
        if door then
            out[id] = Access.evaluate(src, door, Doors.getAccess(id), nil, nil, false).granted == true
        end
    end
    return out
end)

lib.callback.register('g_doorlock:toggle', function(src, id, wantLocked, pin)
    if not RateLimit.check(src, 'toggle') then
        return { ok = false, reason = 'rate' }
    end
    if type(id) ~= 'string' or not Doors.list[id] then
        return { ok = false, reason = 'not_found' }
    end
    local door = Doors.list[id]

    local here, why = checkPresence(src, door, door.interactDistance)
    if not here then
        denied(src, door, why)
        return { ok = false, reason = why }
    end

    if type(wantLocked) ~= 'boolean' then
        wantLocked = not Doors.state[id].locked
    end
    if pin ~= nil and type(pin) ~= 'string' then pin = nil end

    local res = Access.evaluate(src, door, Doors.getAccess(id), Doors.pinHashes(id), pin, true)

    -- evaluate can yield (bcrypt, framework calls), door may be gone now
    door = Doors.list[id]
    if not door then return { ok = false, reason = 'not_found' } end

    if res.needPin then
        return { ok = false, needPin = true }
    end
    if not res.granted then
        denied(src, door, res.reason)
        return { ok = false, reason = res.reason, attemptsLeft = res.attemptsLeft }
    end

    local okHook, allowed, msg = pcall(Hooks.canInteract, src, Utils.deepCopy(door), wantLocked and 'lock' or 'unlock')
    if okHook and allowed == false then
        denied(src, door, 'hook')
        return { ok = false, reason = 'hook', message = type(msg) == 'string' and msg or nil }
    end

    if wantLocked and Doors.broken[id] then
        return { ok = false, reason = 'broken' }
    end

    if res.item and res.item.remove then
        Bridge.removeItem(src, res.item.name, res.item.slot)
    end

    if Doors.state[id].locked ~= wantLocked then
        Doors.setState(id, wantLocked, src, res.viaPin and 'pin' or 'player')
        Logs.add('state', src, id, wantLocked and 'locked' or 'unlocked')
    end
    return { ok = true, locked = wantLocked }
end)

lib.callback.register('g_doorlock:auto', function(src, id)
    if not RateLimit.check(src, 'auto') then return false end
    if type(id) ~= 'string' then return false end
    local door = Doors.list[id]
    if not door or door.autoDistance <= 0 then return false end
    if not Doors.state[id].locked then return true end

    if not checkPresence(src, door, door.autoDistance) then return false end
    if Config.Doors.autoGate.requireVehicle and GetVehiclePedIsIn(GetPlayerPed(src), false) == 0 then
        return false
    end

    local res = Access.evaluate(src, door, Doors.getAccess(id), Doors.pinHashes(id), nil, false)
    if not res.granted or not Doors.list[id] then return false end

    local okHook, allowed = pcall(Hooks.canInteract, src, Utils.deepCopy(door), 'auto')
    if okHook and allowed == false then return false end

    if Doors.state[id].locked then
        local relock = door.autoLock > 0 and door.autoLock or Config.Doors.autoGate.relockAfter
        Doors.setState(id, false, src, 'auto', { autoLock = relock })
        Logs.add('state', src, id, 'auto opened')
    end
    return true
end)
