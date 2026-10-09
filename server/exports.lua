-- server exports. the ones that change things are for trusted server resources only,
-- there is no client export that changes a door.

local function exists(id)
    return type(id) == 'string' and Doors.list[id] ~= nil
end

exports('getDoor', function(id)
    if not exists(id) then return nil end
    local door = Utils.deepCopy(Doors.list[id])
    door.locked = Doors.state[id].locked
    door.hasPin = Doors.pins[id] ~= nil
    return door
end)

exports('getDoors', function(group)
    local out = {}
    for id, door in pairs(Doors.list) do
        if not group or door.group == group then
            local copy = Utils.deepCopy(door)
            copy.locked = Doors.state[id].locked
            out[#out + 1] = copy
        end
    end
    return out
end)

exports('isLocked', function(id)
    if not exists(id) then return nil end
    return Doors.state[id].locked
end)

exports('getDoorState', function(id)
    if not exists(id) then return nil end
    return Doors.state[id].locked and 'locked' or 'unlocked'
end)

exports('setDoorState', function(id, locked, autoLockSeconds)
    if not exists(id) or type(locked) ~= 'boolean' then return false end
    return Doors.setState(id, locked, nil, 'export', { autoLock = tonumber(autoLockSeconds) })
end)

exports('lockDoor', function(id)
    if not exists(id) then return false end
    return Doors.setState(id, true, nil, 'export')
end)

exports('unlockDoor', function(id, autoLockSeconds)
    if not exists(id) then return false end
    return Doors.setState(id, false, nil, 'export', { autoLock = tonumber(autoLockSeconds) })
end)

exports('setGroupState', function(group, locked)
    if type(group) ~= 'string' or type(locked) ~= 'boolean' then return 0 end
    local n = 0
    for id, door in pairs(Doors.list) do
        if door.group == group then
            Doors.setState(id, locked, nil, 'export')
            n = n + 1
        end
    end
    return n
end)

-- check if a player could open a door (no pin asked, no distance check)
exports('canAccess', function(src, id)
    if not exists(id) or not GetPlayerName(src) then return false end
    local res = Access.evaluate(tonumber(src), Doors.list[id], Doors.getAccess(id), Doors.pinHashes(id), nil, false)
    return res.granted == true
end)

-- temporary access override, merged on top of the door access.
-- e.g. exports.g_doorlock:setTempAccess('bank_vault', { public = true }, 300)
-- or   { identifiers = { 'ABC12345' } } for a house guest
exports('setTempAccess', function(id, patch, seconds)
    if not exists(id) or type(patch) ~= 'table' then return nil end
    local base = Utils.deepCopy(Doors.list[id])
    for k, v in pairs(patch) do base.access[k] = v end
    local checked, err = DoorSchema.normalize(base)
    if not checked then
        print(('^1[g_doorlock] setTempAccess(%s) rejected: %s^0'):format(id, tostring(err)))
        return nil
    end
    local clean = {}
    for k in pairs(patch) do clean[k] = checked.access[k] end
    return Doors.setTempAccess(id, clean, tonumber(seconds))
end)

exports('clearTempAccess', function(id)
    if not exists(id) then return false end
    Doors.clearTempAccess(id)
    return true
end)

-- create or update a door from another resource.
-- persist = false keeps it only until restart (good for housing that spawns doors at runtime)
exports('createDoor', function(data, persist, pin)
    if type(data) ~= 'table' then return false, 'err_invalid_data' end
    local isNew = not (data.id and Doors.list[tostring(data.id):lower()])
    local ok, res, detail = SaveDoor(data, {
        isNew = isNew,
        memoryOnly = persist == false,
        pin = pin and { set = tostring(pin) } or nil,
    }, nil)
    if not ok then return false, res, detail end
    Logs.add(isNew and 'create' or 'update', nil, res.id, ('by resource %s'):format(GetInvokingResource() or '?'))
    return true, res.id
end)

exports('deleteDoor', function(id)
    if not exists(id) then return false end
    DB.deleteDoor(id)
    Doors.remove(id)
    Logs.add('delete', nil, id, ('by resource %s'):format(GetInvokingResource() or '?'))
    pcall(Hooks.onDoorDeleted, id, nil)
    return true
end)

-- temporary PIN, e.g. a code for a rented apartment. returns a token to remove it early
-- exports.g_doorlock:addTempPin('motel_12', '4821', 3600 * 24)
exports('addTempPin', function(id, pin, seconds)
    if not exists(id) then return nil end
    pin = Access.sanitizePin(pin)
    seconds = tonumber(seconds)
    if not pin or not seconds or seconds <= 0 then return nil end
    local token = Doors.addTempPin(id, Access.hashPin(pin), math.floor(seconds))
    Logs.add('temp_pin', nil, id, ('by resource %s, %d s'):format(GetInvokingResource() or '?', seconds))
    return token
end)

exports('removeTempPin', function(id, token)
    if not exists(id) then return false end
    return Doors.removeTempPin(id, token)
end)

exports('isBroken', function(id)
    if not exists(id) then return nil end
    return Doors.broken[id] == true
end)

-- repair a breached door and lock it
exports('repairDoor', function(id)
    if not exists(id) or not Doors.broken[id] then return false end
    return Doors.setState(id, true, nil, 'repair')
end)

-- ring the alarm of a door (only if the door has the alarm enabled)
exports('triggerAlarm', function(id)
    if not exists(id) then return false end
    Alarm.trigger(Doors.list[id], 'export')
    return true
end)
