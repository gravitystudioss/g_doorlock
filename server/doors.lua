Doors = {
    list = {},     -- id -> door
    state = {},    -- id -> { locked = bool, rev = number }
    pins = {},     -- id -> bcrypt hash (never sent to clients)
    revs = {},     -- id -> config revision (editor conflict check)
    temp = {},     -- id -> { access = {...}, token = n }
    timers = {},   -- id -> autolock token
    groups = {},   -- name -> label
    broken = {},   -- id -> true after a breach, until repaired
    tempPins = {}, -- id -> { { hash, expires, token } } from exports
    ready = false,
}

local stateCounter = os.time() * 1000
local timerCounter = 0

local function nextStateRev()
    stateCounter = stateCounter + 1
    return stateCounter
end

-- what clients get. no access lists, no pin
function Doors.clientData(id)
    local door = Doors.list[id]
    if not door then return nil end
    local st = Doors.state[id]
    local access = Doors.getAccess(id)
    return {
        id = door.id,
        name = door.name,
        group = door.group,
        type = door.type,
        doors = door.doors,
        interactDistance = door.interactDistance,
        autoDistance = door.autoDistance,
        bucket = door.bucket,
        hideIndicator = door.hideIndicator,
        sounds = door.sounds,
        canLockpick = door.lockpick ~= nil,
        canBreach = door.breach ~= nil,
        canHack = door.hackable == true,
        bell = door.bell == true,
        remote = door.remote == true,
        hasPin = #Doors.pinHashes(id) > 0,
        broken = Doors.broken[id] == true,
        locked = st.locked,
        stateRev = st.rev,
    }
end

function Doors.allClientData()
    local out = {}
    for id in pairs(Doors.list) do
        out[#out + 1] = Doors.clientData(id)
    end
    return out
end

-- door.access with temporary overrides from exports on top
function Doors.getAccess(id)
    local door = Doors.list[id]
    local temp = Doors.temp[id]
    if not temp then return door.access end
    local merged = {}
    for k, v in pairs(door.access) do merged[k] = v end
    for k, v in pairs(temp.access) do merged[k] = v end
    return merged
end

-- every PIN hash that can open the door right now (main + temporary)
function Doors.pinHashes(id)
    local list = {}
    local access = Doors.getAccess(id)
    if access.pin and Doors.pins[id] then
        list[#list + 1] = Doors.pins[id]
    end
    local now = os.time()
    for _, p in ipairs(Doors.tempPins[id] or {}) do
        if p.expires > now then
            list[#list + 1] = p.hash
        end
    end
    return list
end

function Doors.center(id)
    local x, y, z = Utils.doorCenter(Doors.list[id])
    return vector3(x, y, z)
end

local function cancelAutoLock(id)
    Doors.timers[id] = nil
end

local function scheduleAutoLock(id, seconds)
    timerCounter = timerCounter + 1
    local token = timerCounter
    Doors.timers[id] = token
    SetTimeout(seconds * 1000, function()
        if Doors.timers[id] ~= token then return end
        Doors.timers[id] = nil
        if Doors.list[id] and Doors.state[id] and not Doors.state[id].locked then
            Doors.setState(id, true, nil, 'autolock')
        end
    end)
end

-- the only place where a door state changes
-- opts.autoLock overrides the door autolock (seconds, 0 = none)
function Doors.setState(id, locked, src, reason, opts)
    local door = Doors.list[id]
    if not door then return false end
    opts = opts or {}

    -- a broken door can't be locked until it is repaired (admins can force it)
    if locked and Doors.broken[id] then
        if reason ~= 'admin' and reason ~= 'repair' then return false end
        Doors.setBroken(id, false)
    end

    local rev = nextStateRev()
    Doors.state[id] = { locked = locked, rev = rev }
    TriggerClientEvent('g_doorlock:state', -1, id, locked, rev, src)

    if door.persist then
        DB.saveState(id, locked, rev)
    end

    cancelAutoLock(id)
    if not locked then
        local seconds = opts.autoLock
        if seconds == nil then seconds = door.autoLock end
        if seconds and seconds > 0 then
            scheduleAutoLock(id, seconds)
        end
    end

    pcall(Hooks.onStateChanged, Utils.deepCopy(door), locked, src, reason)
    TriggerEvent('g_doorlock:stateChanged', id, locked, src, reason)
    return true
end

function Doors.put(door, rev, keepState)
    local old = Doors.list[door.id]
    Doors.list[door.id] = door
    Doors.revs[door.id] = rev
    if not keepState or not Doors.state[door.id] then
        Doors.state[door.id] = { locked = door.locked, rev = nextStateRev() }
    end
    if old and not door.persist and old.persist then
        DB.clearState(door.id)
    end
    TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(door.id))
end

function Doors.remove(id)
    Doors.list[id] = nil
    Doors.state[id] = nil
    Doors.pins[id] = nil
    Doors.broken[id] = nil
    Doors.tempPins[id] = nil
    Doors.revs[id] = nil
    Doors.temp[id] = nil
    Doors.timers[id] = nil
    TriggerClientEvent('g_doorlock:remove', -1, id)
end

function Doors.load()
    local rows = DB.loadAll()
    local count, bad = 0, 0
    for _, row in ipairs(rows) do
        local ok, raw = pcall(json.decode, row.data)
        local door, err = nil, nil
        if ok and raw then
            door, err = DoorSchema.normalize(raw)
        end
        if door and door.id == row.id then
            Doors.list[door.id] = door
            Doors.revs[door.id] = tonumber(row.rev) or 1
            Doors.pins[door.id] = row.pin_hash
            local locked = door.locked
            if door.persist and row.state ~= nil then
                locked = row.state == 1 or row.state == true
            end
            Doors.state[door.id] = { locked = locked, rev = nextStateRev() }
            count = count + 1
        else
            bad = bad + 1
            print(('^1[g_doorlock] door "%s" in database is invalid (%s), skipped^0'):format(tostring(row.id), tostring(err)))
        end
    end
    for _, row in ipairs(DB.loadGroups()) do
        Doors.groups[row.name] = row.label
    end
    -- doors saved before groups existed: create their group
    for _, door in pairs(Doors.list) do
        if door.group and not Doors.groups[door.group] then
            Doors.ensureGroup(door.group)
        end
    end

    Doors.ready = true
    print(('[g_doorlock] loaded %d doors%s'):format(count, bad > 0 and (' (%d invalid)'):format(bad) or ''))
end

-- same physical door already used by another id?
function Doors.findPhysicalDuplicate(door)
    for otherId, other in pairs(Doors.list) do
        if otherId ~= door.id then
            for _, a in ipairs(door.doors) do
                for _, b in ipairs(other.doors) do
                    if a.model == b.model and Utils.dist3(a.coords.x, a.coords.y, a.coords.z, b.coords.x, b.coords.y, b.coords.z) < 0.1 then
                        return otherId
                    end
                end
            end
        end
    end
    return nil
end

function Doors.setTempAccess(id, patch, seconds)
    timerCounter = timerCounter + 1
    local token = timerCounter
    Doors.temp[id] = { access = patch, token = token }
    TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(id))
    if seconds and seconds > 0 then
        SetTimeout(seconds * 1000, function()
            if Doors.temp[id] and Doors.temp[id].token == token then
                Doors.temp[id] = nil
                if Doors.list[id] then
                    TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(id))
                end
            end
        end)
    end
    return token
end

function Doors.clearTempAccess(id)
    if Doors.temp[id] then
        Doors.temp[id] = nil
        TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(id))
    end
end

function Doors.ensureGroup(name, label)
    if not name then return end
    if Doors.groups[name] and not label then return end
    Doors.groups[name] = label or Doors.groups[name] or name
    DB.saveGroup(name, Doors.groups[name])
end

function Doors.groupList()
    local count = {}
    for _, door in pairs(Doors.list) do
        if door.group then count[door.group] = (count[door.group] or 0) + 1 end
    end
    local list = {}
    for name, label in pairs(Doors.groups) do
        list[#list + 1] = { name = name, label = label, count = count[name] or 0 }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Doors.setBroken(id, broken)
    if not Doors.list[id] then return end
    Doors.broken[id] = broken or nil
    TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(id))
end

function Doors.addTempPin(id, hash, seconds)
    timerCounter = timerCounter + 1
    local list = Doors.tempPins[id] or {}
    -- drop the expired ones
    local now, kept = os.time(), {}
    for _, p in ipairs(list) do
        if p.expires > now then kept[#kept + 1] = p end
    end
    kept[#kept + 1] = { hash = hash, expires = now + seconds, token = timerCounter }
    Doors.tempPins[id] = kept
    TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(id))
    return timerCounter
end

function Doors.removeTempPin(id, token)
    local list = Doors.tempPins[id]
    if not list then return false end
    for i, p in ipairs(list) do
        if p.token == token then
            table.remove(list, i)
            TriggerClientEvent('g_doorlock:update', -1, Doors.clientData(id))
            return true
        end
    end
    return false
end
