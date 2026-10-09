-- checks and cleans door data before the server saves it

DoorSchema = {}

-- how many leaves each type can have
DoorSchema.TYPES = {
    single = { min = 1, max = 1 },
    double = { min = 2, max = 2 },
    gate = { min = 1, max = 2 },
    garage = { min = 1, max = 1 },
}

local MAX_ENTRIES = 50
local NAME_PATTERN = '^[%w_%-%.]+$'
local ID_PATTERN = '^[%w_%-]+$'
local IDENTIFIER_PATTERN = '^[%w_%-%.:]+$'

local function toText(value, maxLen, pattern)
    if type(value) == 'number' then
        value = tostring(value)
    end
    if type(value) ~= 'string' then
        return nil
    end

    value = value:match('^%s*(.-)%s*$')
    if value == '' or #value > maxLen then
        return nil
    end
    if pattern and not value:match(pattern) then
        return nil
    end
    return value
end

local function toNumber(value, min, max)
    value = tonumber(value)
    if not value or value ~= value or value < min or value > max then
        return nil
    end
    return value
end

local function isCoords(c)
    local t = type(c)
    return t == 'table' or t == 'vector3' or t == 'vector4'
end

local function readModel(model)
    if type(model) == 'string' then
        model = tonumber(model) or joaat(model)
    end
    model = toNumber(model, -2147483648, 4294967295)
    if not model then
        return nil
    end

    model = math.floor(model)
    if model > 2147483647 then
        model = model - 4294967296
    end
    return model
end

local function readLeaves(raw)
    if type(raw.doors) ~= 'table' then
        return nil, 'err_invalid_leaves'
    end

    local leaves = {}
    for i, leaf in ipairs(raw.doors) do
        if i > 2 or type(leaf) ~= 'table' or not isCoords(leaf.coords) then
            return nil, 'err_invalid_leaves'
        end

        local model = readModel(leaf.model)
        if not model then
            return nil, 'err_invalid_model', tostring(leaf.model)
        end

        local x = toNumber(leaf.coords.x, -20000, 20000)
        local y = toNumber(leaf.coords.y, -20000, 20000)
        local z = toNumber(leaf.coords.z, -2000, 5000)
        if not x or not y or not z then
            return nil, 'err_invalid_coords'
        end

        local heading = toNumber(leaf.heading, -720, 720) or 0.0

        leaves[i] = {
            model = model,
            coords = { x = Utils.round(x, 4), y = Utils.round(y, 4), z = Utils.round(z, 4) },
            heading = Utils.round(heading % 360, 3),
        }
    end

    local limits = DoorSchema.TYPES[raw.type]
    if #leaves < limits.min or #leaves > limits.max then
        return nil, 'err_leaf_count', raw.type .. ': ' .. limits.min .. '-' .. limits.max
    end

    if #leaves == 2 then
        local a, b = leaves[1].coords, leaves[2].coords
        local dist = Utils.dist3(a.x, a.y, a.z, b.x, b.y, b.z)
        if dist < 0.05 then
            return nil, 'err_same_leaf'
        end
        if dist > 20.0 then
            return nil, 'err_leaves_far'
        end
    end

    return leaves
end

-- jobs and gangs: { { name = 'police', grade = 0 } } or just { 'police' }
local function readGroups(list)
    local out = {}
    if list == nil then
        return out
    end
    if type(list) ~= 'table' then
        return nil
    end

    local seen = {}
    for _, entry in ipairs(list) do
        local name, grade
        if type(entry) == 'table' then
            name = toText(entry.name, 32, NAME_PATTERN)
            grade = toNumber(entry.grade or 0, 0, 1000)
        else
            name = toText(entry, 32, NAME_PATTERN)
            grade = 0
        end

        if not name or not grade or #out >= MAX_ENTRIES then
            return nil
        end
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = { name = name, grade = math.floor(grade) }
        end
    end
    return out
end

local function readIdentifiers(list)
    local out = {}
    if list == nil then
        return out
    end
    if type(list) ~= 'table' then
        return nil
    end

    local seen = {}
    for _, value in ipairs(list) do
        local ident = toText(value, 96, IDENTIFIER_PATTERN)
        if not ident or #out >= MAX_ENTRIES then
            return nil, tostring(value)
        end
        if not seen[ident] then
            seen[ident] = true
            out[#out + 1] = ident
        end
    end
    return out
end

-- items: { { name = 'keycard', metadata = 'mrpd', remove = false } } or just { 'keycard' }
local function readItems(list)
    local out = {}
    if list == nil then
        return out
    end
    if type(list) ~= 'table' then
        return nil
    end

    for _, item in ipairs(list) do
        if type(item) == 'string' then
            item = { name = item }
        end
        if type(item) ~= 'table' or #out >= MAX_ENTRIES then
            return nil
        end

        local name = toText(item.name, 64, NAME_PATTERN)
        if not name then
            return nil, tostring(item.name)
        end

        local metadata = nil
        if item.metadata ~= nil and item.metadata ~= '' then
            metadata = toText(item.metadata, 64)
            if not metadata then
                return nil, name
            end
        end

        out[#out + 1] = { name = name, metadata = metadata, remove = item.remove == true }
    end
    return out
end

local function readAccess(raw)
    local a = type(raw) == 'table' and raw or {}

    local access = {
        mode = a.mode == 'all' and 'all' or 'any',
        public = a.public == true,
        admin = a.admin == true,
        pin = a.pin == true,
    }

    local detail
    access.jobs = readGroups(a.jobs)
    if not access.jobs then return nil, 'err_invalid_jobs' end

    access.gangs = readGroups(a.gangs)
    if not access.gangs then return nil, 'err_invalid_gangs' end

    access.identifiers, detail = readIdentifiers(a.identifiers)
    if not access.identifiers then return nil, 'err_invalid_identifiers', detail end

    access.items, detail = readItems(a.items)
    if not access.items then return nil, 'err_invalid_items', detail end

    return access
end

-- per door lock/unlock sound. unknown names fall back to the default
local function readSounds(raw)
    if type(raw) ~= 'table' then
        return nil
    end

    local out = {}
    for _, kind in ipairs({ 'lock', 'unlock' }) do
        local key = raw[kind]
        if key == 'none' or (type(key) == 'string' and Config.Sounds.library[key]) then
            out[kind] = key
        end
    end

    if next(out) == nil then
        return nil
    end
    return out
end

local function readLockpick(raw)
    if type(raw) ~= 'table' or raw.enabled ~= true then
        return nil
    end
    local difficulty = raw.difficulty
    if not Config.Lockpick.difficulty[difficulty] then
        difficulty = 'medium'
    end
    return { enabled = true, difficulty = difficulty }
end

local function readBreach(raw)
    if type(raw) ~= 'table' or raw.enabled ~= true then
        return nil
    end
    return { enabled = true }
end

local function readTime(value)
    if type(value) ~= 'string' then return nil end
    local h, m = value:match('^(%d%d?):(%d%d)$')
    h, m = tonumber(h), tonumber(m)
    if not h or h > 23 or m > 59 then return nil end
    return ('%02d:%02d'):format(h, m)
end

-- opening hours: { open = '08:00', close = '20:00', days = { 2, 3, 4, 5, 6 } }
-- days use os.date wday (1 = sunday). empty days = every day
local function readSchedule(raw)
    if type(raw) ~= 'table' or raw.enabled ~= true then
        return nil
    end
    local open, close = readTime(raw.open), readTime(raw.close)
    if not open or not close or open == close then
        return nil, 'err_invalid_schedule'
    end
    local days = {}
    if type(raw.days) == 'table' then
        local seen = {}
        for _, d in ipairs(raw.days) do
            d = math.floor(tonumber(d) or 0)
            if d >= 1 and d <= 7 and not seen[d] then
                seen[d] = true
                days[#days + 1] = d
            end
        end
        table.sort(days)
    end
    return { enabled = true, open = open, close = close, days = days }
end

-- returns the clean door, or nil + locale error key + detail
function DoorSchema.normalize(raw)
    if type(raw) ~= 'table' then
        return nil, 'err_invalid_data'
    end

    local id = toText(raw.id, 64, ID_PATTERN)
    if not id then
        return nil, 'err_invalid_id', tostring(raw.id)
    end
    id = id:lower()

    local group = nil
    if raw.group ~= nil and raw.group ~= '' then
        group = toText(raw.group, 32, NAME_PATTERN)
        if not group then
            return nil, 'err_invalid_group', tostring(raw.group)
        end
    end

    if not DoorSchema.TYPES[raw.type] then
        return nil, 'err_invalid_type', tostring(raw.type)
    end

    local leaves, err, detail = readLeaves(raw)
    if not leaves then
        return nil, err, detail
    end

    local access
    access, err, detail = readAccess(raw.access)
    if not access then
        return nil, err, detail
    end

    local schedule
    schedule, err = readSchedule(raw.schedule)
    if err then
        return nil, err
    end

    local dist = Config.Doors.distances

    return {
        id = id,
        name = toText(raw.name, 64) or id,
        group = group,
        type = raw.type,
        doors = leaves,
        locked = raw.locked ~= false,
        persist = raw.persist ~= false,
        autoLock = math.floor(toNumber(raw.autoLock, 0, 3600) or 0),
        interactDistance = Utils.round(toNumber(raw.interactDistance, 0.5, dist.maxInteract) or dist.defaultInteract, 2),
        autoDistance = Utils.round(toNumber(raw.autoDistance, 0, dist.maxAuto) or 0.0, 2),
        bucket = math.floor(toNumber(raw.bucket, 0, 2147483647) or 0),
        hideIndicator = raw.hideIndicator == true,
        sounds = readSounds(raw.sounds),
        lockpick = readLockpick(raw.lockpick),
        breach = readBreach(raw.breach),
        alarm = raw.alarm == true or nil,
        bell = raw.bell == true or nil,
        remote = raw.remote == true or nil,
        hackable = raw.hackable == true or nil,
        schedule = schedule,
        access = access,
    }
end

function DoorSchema.hasCriteria(access)
    return access.public or access.admin or access.pin
        or #access.jobs > 0
        or #access.gangs > 0
        or #access.identifiers > 0
        or #access.items > 0
end
