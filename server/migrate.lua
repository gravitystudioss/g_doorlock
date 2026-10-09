-- import doors from ox_doorlock (database) and qb-doorlock (config files).
-- converted doors go through SaveDoor like a normal import, existing ids are skipped

Migrate = {}

local function slug(str)
    str = tostring(str or ''):lower():gsub('[^%w_%-]+', '_'):gsub('_+', '_'):gsub('^_', ''):gsub('_$', '')
    return str:sub(1, 56)
end

local function vec(v)
    if not v then return nil end
    return { x = v.x or v[1], y = v.y or v[2], z = v.z or v[3] }
end

-- { police = 0 } or { 'police' } -> { { name, grade } }
local function groupsFrom(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        if type(k) == 'number' then
            out[#out + 1] = { name = tostring(v), grade = 0 }
        else
            out[#out + 1] = { name = tostring(k), grade = tonumber(v) or 0 }
        end
    end
    return out
end

-- { 'ABC' } or { ABC = true } -> { 'ABC' }
local function listFrom(t)
    local out = {}
    if type(t) ~= 'table' then return out end
    for k, v in pairs(t) do
        out[#out + 1] = type(k) == 'number' and tostring(v) or tostring(k)
    end
    return out
end

-- ox_doorlock -------------------------------------------------------------

function Migrate.oxDoor(rowId, rowName, d)
    local leaves = {}
    if type(d.doors) == 'table' and #d.doors > 0 then
        for _, l in ipairs(d.doors) do
            leaves[#leaves + 1] = { model = l.model, coords = vec(l.coords), heading = l.heading }
        end
    else
        leaves[1] = { model = d.model, coords = vec(d.coords), heading = d.heading }
    end

    local items = {}
    for _, it in ipairs(type(d.items) == 'table' and d.items or {}) do
        if type(it) == 'table' then
            local meta = type(it.metadata) == 'table' and it.metadata[Config.Access.keys.metadataField] or it.metadata
            items[#items + 1] = { name = it.name, metadata = type(meta) == 'string' and meta or nil, remove = it.remove == true }
        elseif type(it) == 'string' then
            items[#items + 1] = { name = it }
        end
    end

    local doorType = #leaves == 2 and 'double' or 'single'
    if d.auto then doorType = #leaves == 2 and 'gate' or 'garage' end

    return {
        id = 'ox_' .. slug(rowId),
        name = d.name or rowName,
        type = doorType,
        doors = leaves,
        locked = d.state == 1 or d.state == true,
        persist = true,
        autoLock = tonumber(d.autolock) or 0,
        interactDistance = tonumber(d.maxDistance) or Config.Doors.distances.defaultInteract,
        autoDistance = d.auto and 8.0 or 0,
        hideIndicator = d.hideUi == true,
        lockpick = d.lockpick and { enabled = true, difficulty = 'medium' } or nil,
        access = {
            mode = 'any',
            admin = true,
            jobs = groupsFrom(d.groups),
            identifiers = listFrom(d.characters),
            items = items,
        },
        pin_code = d.passcode,
    }
end

function Migrate.loadOx()
    local exists = MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'ox_doorlock'")
    if not exists or tonumber(exists) == 0 then
        return nil, 'err_migrate_ox_missing'
    end
    local list = {}
    for _, row in ipairs(MySQL.query.await('SELECT `id`, `name`, `data` FROM `ox_doorlock`') or {}) do
        local ok, d = pcall(json.decode, row.data)
        if ok and type(d) == 'table' then
            list[#list + 1] = Migrate.oxDoor(row.id, row.name, d)
        end
    end
    return list
end

-- qb-doorlock -------------------------------------------------------------

local qbTypes = { door = 'single', double = 'double', sliding = 'gate', doublesliding = 'gate', garage = 'garage' }

function Migrate.qbDoor(key, entry, group)
    local leaves = {}
    if type(entry.doors) == 'table' and #entry.doors > 0 then
        for _, l in ipairs(entry.doors) do
            leaves[#leaves + 1] = { model = l.objName or l.objHash, coords = vec(l.objCoords), heading = l.objYaw }
        end
    else
        leaves[1] = { model = entry.objName or entry.objHash, coords = vec(entry.objCoords), heading = entry.objYaw }
    end

    local doorType = qbTypes[entry.doorType or ''] or (#leaves == 2 and 'double' or 'single')
    if doorType == 'double' and #leaves ~= 2 then doorType = 'single' end

    return {
        id = 'qb_' .. slug(key),
        name = tostring(key),
        group = group,
        type = doorType,
        doors = leaves,
        locked = entry.locked ~= false,
        persist = true,
        autoLock = tonumber(entry.autoLock) or 0,
        interactDistance = tonumber(entry.distance) or Config.Doors.distances.defaultInteract,
        autoDistance = (doorType == 'gate' or doorType == 'garage') and (tonumber(entry.distance) or 6.0) or 0,
        lockpick = entry.pickable and { enabled = true, difficulty = 'medium' } or nil,
        access = {
            mode = 'any',
            admin = true,
            jobs = groupsFrom(entry.authorizedJobs),
            gangs = groupsFrom(entry.authorizedGangs),
            identifiers = listFrom(entry.authorizedCitizenIDs),
            items = listFrom(entry.items),
        },
    }
end

local function runQbFile(path, group, list)
    local file = io.open(path, 'r')
    if not file then return end
    local code = file:read('a')
    file:close()

    local env = {
        Config = { DoorList = {} },
        vector3 = vector3, vec3 = vec3, vector4 = vector4, vec4 = vec4,
        joaat = joaat, GetHashKey = GetHashKey,
        pairs = pairs, ipairs = ipairs, tonumber = tonumber, tostring = tostring,
        math = math, string = string, table = table, type = type, print = function() end,
    }
    local chunk = load(code, '@' .. path, 't', env)
    if not chunk or not pcall(chunk) then
        print(('^3[g_doorlock] could not read %s^0'):format(path))
        return
    end
    for key, entry in pairs(env.Config.DoorList or {}) do
        if type(entry) == 'table' then
            list[#list + 1] = Migrate.qbDoor(key, entry, group)
        end
    end
end

function Migrate.loadQb()
    if GetResourceState('qb-doorlock') == 'missing' then
        return nil, 'err_migrate_qb_missing'
    end
    local base = GetResourcePath('qb-doorlock')
    local list = {}
    runQbFile(base .. '/config.lua', nil, list)

    local dir = io.readdir and io.readdir(base .. '/configs')
    if dir then
        for name in dir:lines() do
            if name:match('%.lua$') then
                runQbFile(base .. '/configs/' .. name, slug(name:gsub('%.lua$', '')), list)
            end
        end
        dir:close()
    end
    return list
end

-- run ---------------------------------------------------------------------

function Migrate.run(from, overwrite, src)
    local list, err
    if from == 'ox' then
        list, err = Migrate.loadOx()
    elseif from == 'qb' then
        list, err = Migrate.loadQb()
    else
        return { ok = false, err = 'err_invalid_data' }
    end
    if not list then return { ok = false, err = err } end
    if #list == 0 then return { ok = false, err = 'err_import_empty' } end

    local report = { ok = true, created = {}, updated = {}, skipped = {}, errors = {} }
    for _, raw in ipairs(list) do
        local id = raw.id
        local isNew = not Doors.list[id]
        if not isNew and not overwrite then
            report.skipped[#report.skipped + 1] = { id = id, err = 'err_id_exists' }
        else
            local pin = raw.pin_code
            raw.pin_code = nil
            local pinAction = nil
            if pin and Access.sanitizePin(pin) then
                pinAction = { set = tostring(pin) }
                raw.access.pin = true
            end
            local ok, res, detail = SaveDoor(raw, { isNew = isNew, pin = pinAction }, src)
            if ok then
                local target = isNew and report.created or report.updated
                target[#target + 1] = res.id
            else
                report.errors[#report.errors + 1] = { id = id, err = res, detail = detail }
            end
        end
    end

    Logs.add('import', src, nil, ('migrate %s: created=%d updated=%d skipped=%d errors=%d'):format(
        from, #report.created, #report.updated, #report.skipped, #report.errors))
    return report
end
