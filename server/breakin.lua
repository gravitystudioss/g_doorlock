-- lockpick, breach and repair. the client only plays the skill check / progress bar,
-- the server gives a one-time token and checks time, distance, item and job again at the end

local pending = {}  -- src -> { id, kind, token, started }
local tokenCounter = 0

local function nearDoor(src, door)
    if GetPlayerRoutingBucket(src) ~= door.bucket then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local dist = #(GetEntityCoords(ped) - Doors.center(door.id))
    return dist <= door.interactDistance + Config.Doors.distances.serverTolerance
end

-- jobs = { police = 0 }. empty table = anyone
local function hasJob(src, jobs)
    if next(jobs) == nil then return true end
    local job = Bridge.getJob(src)
    if not job then return false end
    local minGrade = jobs[job.name]
    return minGrade ~= nil and job.grade >= minGrade
end

local function hasItem(src, item)
    return not item or Bridge.findKey(src, item, nil) ~= nil
end

local function duration(kind)
    if kind == 'breach' then return Config.Breach.duration end
    if kind == 'repair' then return Config.Breach.damage.repairTime end
    return nil
end

local function start(src, id, kind)
    if not RateLimit.check(src, 'breakin') then return { ok = false, reason = 'rate' } end
    local door = type(id) == 'string' and Doors.list[id]
    if not door then return { ok = false, reason = 'not_found' } end
    if not nearDoor(src, door) then return { ok = false, reason = 'distance' } end

    if kind == 'repair' then
        if not Doors.broken[id] then return { ok = false, reason = 'not_broken' } end
        if not hasJob(src, Config.Breach.damage.repairJobs) then return { ok = false, reason = 'repair_no_job' } end
        if not hasItem(src, Config.Breach.damage.repairItem) then return { ok = false, reason = 'repair_no_item' } end
    else
        if not Doors.state[id].locked then return { ok = false, reason = 'already_open' } end
        if kind == 'lockpick' then
            if not door.lockpick then return { ok = false, reason = 'not_allowed' } end
            if not hasItem(src, Config.Lockpick.item) then return { ok = false, reason = 'no_lockpick' } end
        elseif kind == 'hack' then
            if not door.hackable then return { ok = false, reason = 'not_allowed' } end
            if not hasItem(src, Config.Hack.item) then return { ok = false, reason = 'no_hack_item' } end
        else
            if not door.breach then return { ok = false, reason = 'not_allowed' } end
            if not hasJob(src, Config.Breach.jobs) then return { ok = false, reason = 'no_access' } end
            if not hasItem(src, Config.Breach.item) then return { ok = false, reason = 'no_item' } end
        end
    end

    tokenCounter = tokenCounter + 1
    local token = tokenCounter .. ':' .. math.random(100000, 999999)
    pending[src] = { id = id, kind = kind, token = token, started = GetGameTimer() }

    if kind == 'lockpick' then
        return { ok = true, token = token, checks = Config.Lockpick.difficulty[door.lockpick.difficulty] }
    end
    if kind == 'hack' then
        return { ok = true, token = token, checks = Config.Hack.checks, keys = Config.Hack.keys }
    end
    return { ok = true, token = token, duration = duration(kind) }
end

-- checks the token and returns the door, or nil
local function finish(src, token, kind)
    local p = pending[src]
    pending[src] = nil
    if not p or p.token ~= token or p.kind ~= kind then return nil end

    local door = Doors.list[p.id]
    if not door or not nearDoor(src, door) then return nil end

    local elapsed = GetGameTimer() - p.started
    local minTime
    if kind == 'lockpick' then
        minTime = Config.Lockpick.minTime
    elseif kind == 'hack' then
        minTime = Config.Hack.minTime
    else
        minTime = duration(kind) - 500
    end
    if elapsed < minTime then
        Logs.add('denied', src, door.id, ('%s finished too fast (%d ms)'):format(kind, elapsed))
        return nil
    end
    return door
end

lib.callback.register('g_doorlock:breakin:start', function(src, id, kind)
    if kind ~= 'lockpick' and kind ~= 'breach' and kind ~= 'repair' and kind ~= 'hack' then return { ok = false } end
    return start(src, id, kind)
end)

lib.callback.register('g_doorlock:lockpick:finish', function(src, token, success)
    local door = finish(src, token, 'lockpick')
    if not door then return { ok = false } end

    if success ~= true then
        if math.random(100) <= Config.Lockpick.removeChance then
            Bridge.removeItem(src, Config.Lockpick.item)
        end
        if Config.Alarm.onLockpickFail then Alarm.trigger(door, 'lockpick') end
        pcall(Hooks.onLockpick, src, Utils.deepCopy(door), false)
        Logs.add('lockpick', src, door.id, 'failed')
        return { ok = false, reason = 'lockpick_failed' }
    end

    if Doors.state[door.id].locked then
        Doors.setState(door.id, false, src, 'lockpick', { autoLock = Config.Lockpick.relockAfter })
    end
    Alarm.trigger(door, 'lockpick')
    pcall(Hooks.onLockpick, src, Utils.deepCopy(door), true)
    Logs.add('lockpick', src, door.id, 'success')
    return { ok = true }
end)

lib.callback.register('g_doorlock:hack:finish', function(src, token, success)
    local door = finish(src, token, 'hack')
    if not door then return { ok = false } end

    if success ~= true then
        if math.random(100) <= Config.Hack.removeChance then
            Bridge.removeItem(src, Config.Hack.item)
        end
        Alarm.trigger(door, 'hack')
        Logs.add('hack', src, door.id, 'failed')
        return { ok = false, reason = 'hack_failed' }
    end

    if Doors.state[door.id].locked then
        Doors.setState(door.id, false, src, 'hack', { autoLock = Config.Hack.relockAfter })
    end
    Alarm.trigger(door, 'hack')
    Logs.add('hack', src, door.id, 'success')
    return { ok = true }
end)

lib.callback.register('g_doorlock:breach:finish', function(src, token)
    local door = finish(src, token, 'breach')
    if not door or not hasJob(src, Config.Breach.jobs) then return { ok = false } end

    if Config.Breach.item then
        if not hasItem(src, Config.Breach.item) then return { ok = false, reason = 'no_item' } end
        if Config.Breach.removeItem then Bridge.removeItem(src, Config.Breach.item) end
    end

    -- broken doors stay open until repaired, otherwise they relock after a while
    local broken = Config.Breach.damage.enabled
    if Doors.state[door.id].locked then
        Doors.setState(door.id, false, src, 'breach', { autoLock = broken and 0 or Config.Breach.relockAfter })
    end
    if broken then Doors.setBroken(door.id, true) end

    Alarm.trigger(door, 'breach')
    pcall(Hooks.onBreach, src, Utils.deepCopy(door))
    Logs.add('breach', src, door.id, broken and 'door breached (broken)' or 'door breached')
    return { ok = true }
end)

lib.callback.register('g_doorlock:repair:finish', function(src, token)
    local door = finish(src, token, 'repair')
    if not door or not Doors.broken[door.id] then return { ok = false } end

    local dmg = Config.Breach.damage
    if not hasJob(src, dmg.repairJobs) then return { ok = false, reason = 'repair_no_job' } end
    if dmg.repairItem then
        if not hasItem(src, dmg.repairItem) then return { ok = false, reason = 'repair_no_item' } end
        if dmg.removeRepairItem then Bridge.removeItem(src, dmg.repairItem) end
    end

    Doors.setState(door.id, true, src, 'repair')
    Logs.add('repair', src, door.id, 'door repaired')
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)
