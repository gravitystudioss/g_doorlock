-- doorbell, remote control and the update check

local function distTo(src, id)
    return #(GetEntityCoords(GetPlayerPed(src)) - Doors.center(id))
end

-- doorbell ----------------------------------------------------------------

local lastKnock = {}

lib.callback.register('g_doorlock:bell', function(src, id)
    if not RateLimit.check(src, 'bell') then return { ok = false, reason = 'rate' } end
    local door = type(id) == 'string' and Doors.list[id]
    if not door or not door.bell then return { ok = false, reason = 'not_found' } end
    if GetPlayerRoutingBucket(src) ~= door.bucket then return { ok = false, reason = 'distance' } end
    if distTo(src, id) > door.interactDistance + Config.Doors.distances.serverTolerance then
        return { ok = false, reason = 'distance' }
    end

    local now = os.time()
    if lastKnock[src] and now - lastKnock[src] < Config.Extras.bell.cooldown then
        return { ok = false, reason = 'rate' }
    end
    lastKnock[src] = now

    local center = Doors.center(id)
    -- wait for the knocking player to turn and raise the hand
    SetTimeout(900, function()
        TriggerClientEvent('g_doorlock:knockSound', -1, center, door.bucket)
    end)

    local access = Doors.getAccess(id)
    local told = 0
    for _, p in ipairs(GetPlayers()) do
        local other = tonumber(p)
        if other ~= src and GetPlayerRoutingBucket(other) == door.bucket and distTo(other, id) <= Config.Extras.bell.range then
            if Access.evaluate(other, door, access, nil, nil, false).granted then
                TriggerClientEvent('g_doorlock:knock', other, door.name)
                told = told + 1
            end
        end
    end
    return { ok = true, told = told }
end)

-- remote control ----------------------------------------------------------

lib.callback.register('g_doorlock:remote', function(src, id)
    if not RateLimit.check(src, 'remote') then return { ok = false, reason = 'rate' } end
    local door = type(id) == 'string' and Doors.list[id]
    if not door or not door.remote then return { ok = false, reason = 'not_found' } end
    if GetPlayerRoutingBucket(src) ~= door.bucket then return { ok = false, reason = 'distance' } end
    if distTo(src, id) > Config.Extras.remote.range + Config.Doors.distances.serverTolerance then
        return { ok = false, reason = 'distance' }
    end
    if Config.Extras.remote.item and not Bridge.findKey(src, Config.Extras.remote.item, nil) then
        return { ok = false, reason = 'no_remote' }
    end
    if not Access.evaluate(src, door, Doors.getAccess(id), nil, nil, false).granted then
        return { ok = false, reason = 'no_access' }
    end

    local locked = not Doors.state[id].locked
    if locked and Doors.broken[id] then return { ok = false, reason = 'broken' } end
    Doors.setState(id, locked, src, 'remote')
    Logs.add('state', src, id, (locked and 'locked' or 'unlocked') .. ' (remote)')
    return { ok = true, locked = locked }
end)

-- update check ------------------------------------------------------------

local function versionNumber(v)
    local a, b, c = tostring(v or ''):match('(%d+)%.(%d+)%.?(%d*)')
    if not a then return nil end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end

CreateThread(function()
    local cfg = ServerConfig.UpdateCheck
    if not cfg or not cfg.enabled or not cfg.repo or cfg.repo == '' then return end
    Wait(5000)
    local current = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
    PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(cfg.repo), function(status, body)
        if status ~= 200 or not body then
            print(('^3[g_doorlock] update check failed (HTTP %s)^0'):format(tostring(status)))
            return
        end
        local ok, data = pcall(json.decode, body)
        local latest = ok and data and data.tag_name
        if versionNumber(latest) and versionNumber(current) and versionNumber(latest) > versionNumber(current) then
            print(('^3[g_doorlock] new version %s available (you have %s): %s^0'):format(latest, current, data.html_url or ''))
        else
            print(('[g_doorlock] up to date (%s)'):format(current))
        end
    end, 'GET', '', { ['User-Agent'] = 'g_doorlock', ['Accept'] = 'application/vnd.github+json' })
end)

AddEventHandler('playerDropped', function()
    lastKnock[source] = nil
end)
