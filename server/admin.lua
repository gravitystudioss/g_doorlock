Trash = {} -- id -> { door, pin, expires }, deleted doors that can still be restored

local function canAdmin(src)
    if not Access.isEditorAdmin(src) then
        Logs.add('denied', src, nil, 'editor callback without permission')
        return false
    end
    return RateLimit.check(src, 'admin')
end

local function adminDoor(id)
    local door = Utils.deepCopy(Doors.list[id])
    door.hasPin = Doors.pins[id] ~= nil
    door.rev = Doors.revs[id]
    door.state = Doors.state[id].locked
    door.tempAccess = Doors.temp[id] ~= nil
    door.broken = Doors.broken[id] == true
    return door
end

local function adminList()
    local list = {}
    for id in pairs(Doors.list) do
        list[#list + 1] = adminDoor(id)
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function summary(door)
    local a = door.access
    return ('type=%s leaves=%d mode=%s public=%s admin=%s pin=%s jobs=%d gangs=%d ids=%d items=%d locked=%s persist=%s autoLock=%d')
        :format(door.type, #door.doors, a.mode, tostring(a.public), tostring(a.admin), tostring(a.pin),
            #a.jobs, #a.gangs, #a.identifiers, #a.items, tostring(door.locked), tostring(door.persist), door.autoLock)
end

-- door packs shipped in examples/packs
function listPacks()
    local out = {}
    local dir = io.readdir and io.readdir(GetResourcePath(GetCurrentResourceName()) .. '/examples/packs')
    if not dir then return out end
    for name in dir:lines() do
        if name:match('^[%w_%-]+%.json$') then
            local text = LoadResourceFile(GetCurrentResourceName(), 'examples/packs/' .. name)
            local ok, data = pcall(json.decode, text or '')
            local count = ok and type(data) == 'table' and type(data.doors) == 'table' and #data.doors or 0
            out[#out + 1] = { file = name, label = ok and type(data) == 'table' and data.label or name, count = count }
        end
    end
    dir:close()
    table.sort(out, function(a, b) return a.file < b.file end)
    return out
end

RegisterCommand(Config.Admin.command, function(src)
    if src == 0 then
        print('[g_doorlock] /' .. Config.Admin.command .. ' can only be used in game')
        return
    end
    if not Access.isEditorAdmin(src) then
        TriggerClientEvent('g_doorlock:notify', src, L('no_permission'), 'error')
        return
    end
    TriggerClientEvent('g_doorlock:openEditor', src)
end, false)

lib.callback.register('g_doorlock:admin:open', function(src)
    if not canAdmin(src) then return nil end
    return {
        doors = adminList(),
        groups = Doors.groupList(),
        templates = Templates.list(),
        packs = listPacks(),
        supportsGangs = Bridge.fw.supportsGangs,
        supportsMetadata = Bridge.inv.supportsMetadata,
        items = Bridge.listItems(),
        framework = Bridge.name,
        inventory = Bridge.inventoryName,
    }
end)

-- pinAction: nil = keep, { set = '1234' } or { clear = true }
function SaveDoor(raw, opts, src)
    local door, err, detail = DoorSchema.normalize(raw)
    if not door then return false, err, detail end

    local exists = Doors.list[door.id] ~= nil
    if opts.isNew and exists then return false, 'err_id_exists', door.id end
    if not opts.isNew and not exists then return false, 'err_not_found', door.id end
    if not opts.isNew and opts.rev ~= nil and opts.rev ~= Doors.revs[door.id] then
        return false, 'err_conflict', door.id
    end

    local dup = Doors.findPhysicalDuplicate(door)
    if dup then return false, 'err_duplicate_physical', dup end

    local pinHash = nil
    local pinAction = opts.pin
    if type(pinAction) == 'table' and pinAction.set ~= nil then
        local pin = Access.sanitizePin(pinAction.set)
        if not pin then return false, 'err_pin_format', ('%d-%d'):format(Config.Access.pin.minLength, Config.Access.pin.maxLength) end
        pinHash = Access.hashPin(pin)
        door.access.pin = true
    elseif type(pinAction) == 'table' and pinAction.clear then
        pinHash = false
        door.access.pin = false
    end
    local finalHash = pinHash
    if finalHash == nil then finalHash = Doors.pins[door.id] end
    if door.access.pin and not finalHash then return false, 'err_pin_required' end
    if not DoorSchema.hasCriteria(door.access) then return false, 'err_no_criteria' end

    -- check again after the await in hashPin
    if opts.isNew and Doors.list[door.id] then return false, 'err_id_exists', door.id end

    local rev = (Doors.revs[door.id] or 0) + 1
    if opts.memoryOnly then
        Doors.revs[door.id] = rev
    else
        DB.saveDoor(door, rev, pinHash)
    end
    if pinHash ~= nil then
        Doors.pins[door.id] = pinHash or nil
    end
    Doors.ensureGroup(door.group)
    Doors.put(door, rev, not opts.isNew)
    if opts.isNew and door.persist and not opts.memoryOnly then
        DB.saveState(door.id, door.locked, Doors.state[door.id].rev)
    end

    pcall(Hooks.onDoorSaved, Utils.deepCopy(door), src, opts.isNew)
    return true, door
end

lib.callback.register('g_doorlock:admin:save', function(src, payload)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    if type(payload) ~= 'table' or type(payload.door) ~= 'table' then
        return { ok = false, err = 'err_invalid_data' }
    end
    local isNew = payload.isNew == true
    local ok, res, detail = SaveDoor(payload.door, {
        isNew = isNew,
        rev = tonumber(payload.rev),
        pin = payload.pin,
    }, src)
    if not ok then return { ok = false, err = res, detail = detail } end

    local pinNote = ''
    if type(payload.pin) == 'table' then
        pinNote = payload.pin.clear and ' pin=removed' or ' pin=changed'
    end
    Logs.add(isNew and 'create' or 'update', src, res.id, summary(res) .. pinNote)
    return { ok = true, door = adminDoor(res.id), groups = Doors.groupList() }
end)

lib.callback.register('g_doorlock:admin:delete', function(src, id)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    if type(id) ~= 'string' or not Doors.list[id] then return { ok = false, err = 'err_not_found' } end
    local door = Doors.list[id]
    Trash[id] = { door = Utils.deepCopy(door), pin = Doors.pins[id], expires = os.time() + Config.Admin.undoSeconds }
    DB.deleteDoor(id)
    if Doors.list[id] then
        Doors.remove(id)
        Logs.add('delete', src, id, summary(door))
        pcall(Hooks.onDoorDeleted, id, src)
    end
    return { ok = true }
end)

lib.callback.register('g_doorlock:admin:setState', function(src, id, locked)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    if type(id) ~= 'string' or not Doors.list[id] or type(locked) ~= 'boolean' then
        return { ok = false, err = 'err_not_found' }
    end
    Doors.setState(id, locked, src, 'admin')
    Logs.add('admin_state', src, id, locked and 'locked' or 'unlocked')
    return { ok = true }
end)

lib.callback.register('g_doorlock:admin:goto', function(src, id)
    if not canAdmin(src) then return false end
    if type(id) ~= 'string' or not Doors.list[id] then return false end
    local door = Doors.list[id]
    local ped = GetPlayerPed(src)
    if GetPlayerRoutingBucket(src) ~= door.bucket then
        SetPlayerRoutingBucket(src, door.bucket)
    end
    local c = Doors.center(id)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    return true
end)

lib.callback.register('g_doorlock:admin:identifier', function(src, target)
    if not canAdmin(src) then return nil end
    target = tonumber(target) or src
    if not GetPlayerName(target) then return nil end
    return { identifier = Bridge.getIdentifier(target), name = Bridge.getName(target) }
end)

local function buildExport(ids)
    local out = {}
    local wanted = nil
    if type(ids) == 'table' and #ids > 0 then
        wanted = {}
        for _, id in ipairs(ids) do wanted[tostring(id)] = true end
    end
    for _, door in ipairs(adminList()) do
        if not wanted or wanted[door.id] then
            local copy = Utils.deepCopy(Doors.list[door.id])
            out[#out + 1] = copy
        end
    end
    return out
end

lib.callback.register('g_doorlock:admin:export', function(src, ids)
    if not canAdmin(src) then return nil end
    local doors = buildExport(ids)
    local text = json.encode({ format = 'g_doorlock', version = 1, doors = doors }, { indent = true })
    local fileName = ('doors_export_%s.json'):format(os.date('%Y%m%d_%H%M%S'))
    local saved = SaveResourceFile(GetCurrentResourceName(), fileName, text, -1)
    Logs.add('export', src, nil, ('%d doors -> %s'):format(#doors, saved and fileName or 'not saved'))
    return { json = text, count = #doors, file = saved and fileName or nil }
end)

local function importText(src, text, overwrite)
    if type(text) ~= 'string' or #text > 2000000 then return { ok = false, err = 'err_invalid_json' } end

    local okJson, data = pcall(json.decode, text)
    if not okJson or type(data) ~= 'table' then return { ok = false, err = 'err_invalid_json' } end
    local list = data.doors or data
    if type(list) ~= 'table' or #list == 0 then return { ok = false, err = 'err_import_empty' } end
    if #list > 500 then return { ok = false, err = 'err_import_too_big' } end

    local report = { created = {}, updated = {}, skipped = {}, errors = {} }
    local valid = {}
    local seenIds = {}

    for i, raw in ipairs(list) do
        local door, err, detail = DoorSchema.normalize(raw)
        if not door then
            report.errors[#report.errors + 1] = { index = i, id = type(raw) == 'table' and tostring(raw.id) or '?', err = err, detail = detail }
        elseif seenIds[door.id] then
            report.errors[#report.errors + 1] = { index = i, id = door.id, err = 'err_duplicate_in_file' }
        else
            seenIds[door.id] = true
            -- physical duplicate inside the file itself
            local clash = nil
            for _, v in ipairs(valid) do
                for _, a in ipairs(door.doors) do
                    for _, b in ipairs(v.door.doors) do
                        if a.model == b.model and Utils.dist3(a.coords.x, a.coords.y, a.coords.z, b.coords.x, b.coords.y, b.coords.z) < 0.1 then
                            clash = v.door.id
                        end
                    end
                end
            end
            if clash then
                report.errors[#report.errors + 1] = { index = i, id = door.id, err = 'err_duplicate_physical', detail = clash }
            elseif Doors.list[door.id] and not overwrite then
                report.skipped[#report.skipped + 1] = { id = door.id, err = 'err_id_exists' }
            else
                local pin = type(raw) == 'table' and raw.pin_code or nil
                valid[#valid + 1] = { door = door, pin = pin }
            end
        end
    end

    for _, v in ipairs(valid) do
        local isNew = Doors.list[v.door.id] == nil
        local pinAction = nil
        if v.pin ~= nil then pinAction = { set = tostring(v.pin) } end
        local ok, res, detail = SaveDoor(v.door, { isNew = isNew, pin = pinAction }, src)
        if ok then
            local target = isNew and report.created or report.updated
            target[#target + 1] = res.id
        else
            report.errors[#report.errors + 1] = { id = v.door.id, err = res, detail = detail }
        end
    end

    Logs.add('import', src, nil, ('created=%d updated=%d skipped=%d errors=%d'):format(
        #report.created, #report.updated, #report.skipped, #report.errors))
    report.ok = true
    report.doors = adminList()
    report.groups = Doors.groupList()
    return report
end

lib.callback.register('g_doorlock:admin:import', function(src, text, overwrite)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    return importText(src, text, overwrite)
end)

-- groups

local function cleanGroupName(name)
    if type(name) ~= 'string' then return nil end
    name = name:lower():match('^%s*(.-)%s*$')
    if name == '' or #name > 32 or not name:match('^[%w_%-%.]+$') then return nil end
    return name
end

local function groupResult()
    return { ok = true, groups = Doors.groupList(), doors = adminList() }
end

lib.callback.register('g_doorlock:admin:groupSave', function(src, name, label)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    name = cleanGroupName(name)
    if not name then return { ok = false, err = 'err_invalid_group' } end
    if type(label) ~= 'string' or label:match('^%s*$') then label = name end
    label = label:sub(1, 64)
    Doors.ensureGroup(name, label)
    Logs.add('group', src, nil, ('saved group %s (%s)'):format(name, label))
    return groupResult()
end)

-- deleting a group keeps the doors, they just lose the group
lib.callback.register('g_doorlock:admin:groupDelete', function(src, name)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    name = cleanGroupName(name)
    if not name or not Doors.groups[name] then return { ok = false, err = 'err_invalid_group' } end

    for id, door in pairs(Doors.list) do
        if door.group == name then
            local copy = Utils.deepCopy(door)
            copy.group = nil
            SaveDoor(copy, { isNew = false }, src)
        end
    end
    Doors.groups[name] = nil
    DB.deleteGroup(name)
    Logs.add('group', src, nil, 'deleted group ' .. name)
    return groupResult()
end)

lib.callback.register('g_doorlock:admin:groupState', function(src, name, locked)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    name = cleanGroupName(name)
    if not name or type(locked) ~= 'boolean' then return { ok = false, err = 'err_invalid_group' } end

    local n = 0
    for id, door in pairs(Doors.list) do
        if door.group == name then
            if Doors.state[id].locked ~= locked then
                Doors.setState(id, locked, src, 'admin')
            end
            n = n + 1
        end
    end
    Logs.add('admin_state', src, nil, ('group %s %s (%d doors)'):format(name, locked and 'locked' or 'unlocked', n))
    local res = groupResult()
    res.count = n
    return res
end)

-- import from other doorlocks
lib.callback.register('g_doorlock:admin:migrate', function(src, from, overwrite)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    local report = Migrate.run(from, overwrite == true, src)
    if report.ok then
        report.doors = adminList()
        report.groups = Doors.groupList()
    end
    return report
end)

-- quick lock / unlock of the nearest door, no editor needed
RegisterCommand(Config.Admin.quickCommand, function(src)
    if src == 0 then return end
    if not Access.isEditorAdmin(src) then
        TriggerClientEvent('g_doorlock:notify', src, L('no_permission'), 'error')
        return
    end
    TriggerClientEvent('g_doorlock:quickToggle', src)
end, false)

lib.callback.register('g_doorlock:admin:quickToggle', function(src, id)
    if not canAdmin(src) then return nil end
    local door = type(id) == 'string' and Doors.list[id]
    if not door then return nil end
    local dist = #(GetEntityCoords(GetPlayerPed(src)) - Doors.center(id))
    if dist > 10.0 then return nil end
    local locked = not Doors.state[id].locked
    Doors.setState(id, locked, src, 'admin')
    Logs.add('admin_state', src, id, (locked and 'locked' or 'unlocked') .. ' (quick command)')
    return locked
end)

-- restore a deleted door

lib.callback.register('g_doorlock:admin:restore', function(src, id)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    local t = type(id) == 'string' and Trash[id]
    if not t or t.expires < os.time() then
        Trash[id or ''] = nil
        return { ok = false, err = 'err_restore_expired' }
    end
    if Doors.list[id] then return { ok = false, err = 'err_id_exists', detail = id } end
    local dup = Doors.findPhysicalDuplicate(t.door)
    if dup then return { ok = false, err = 'err_duplicate_physical', detail = dup } end

    Trash[id] = nil
    DB.saveDoor(t.door, 1, t.pin)
    Doors.pins[id] = t.pin
    Doors.ensureGroup(t.door.group)
    Doors.put(t.door, 1, false)
    Logs.add('restore', src, id, 'restored after delete')
    return { ok = true, doors = adminList(), groups = Doors.groupList() }
end)

-- edit many doors at once

local function applyBulk(door, patch)
    if patch.group ~= nil then door.group = patch.group ~= '' and patch.group or nil end
    if type(patch.addJob) == 'table' and patch.addJob.name then
        local list = {}
        for _, j in ipairs(door.access.jobs) do
            if j.name ~= patch.addJob.name then list[#list + 1] = j end
        end
        list[#list + 1] = { name = patch.addJob.name, grade = tonumber(patch.addJob.grade) or 0 }
        door.access.jobs = list
    end
    if type(patch.removeJob) == 'string' then
        local list = {}
        for _, j in ipairs(door.access.jobs) do
            if j.name ~= patch.removeJob then list[#list + 1] = j end
        end
        door.access.jobs = list
    end
    if type(patch.sounds) == 'table' then
        door.sounds = door.sounds or {}
        for _, kind in ipairs({ 'lock', 'unlock' }) do
            local v = patch.sounds[kind]
            if v == 'default' then door.sounds[kind] = nil elseif v then door.sounds[kind] = v end
        end
    end
    if type(patch.template) == 'table' then
        local keepPin = door.access.pin
        door.access = Utils.deepCopy(patch.template)
        door.access.pin = keepPin
    end
    if patch.lockpick ~= nil then door.lockpick = patch.lockpick and { enabled = true, difficulty = patch.difficulty or 'medium' } or nil end
    for _, key in ipairs({ 'breach', 'alarm', 'bell', 'remote', 'hackable' }) do
        if patch[key] ~= nil then
            if key == 'breach' then
                door.breach = patch.breach and { enabled = true } or nil
            else
                door[key] = patch[key] == true or nil
            end
        end
    end
end

lib.callback.register('g_doorlock:admin:bulk', function(src, ids, patch)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    if type(ids) ~= 'table' or type(patch) ~= 'table' or #ids == 0 or #ids > 200 then
        return { ok = false, err = 'err_invalid_data' }
    end
    if type(patch.templateName) == 'string' then
        patch.template = Templates.get(patch.templateName)
        if not patch.template then return { ok = false, err = 'err_not_found' } end
    end

    local done, errors = 0, {}
    for _, id in ipairs(ids) do
        local door = type(id) == 'string' and Doors.list[id]
        if door then
            local copy = Utils.deepCopy(door)
            applyBulk(copy, patch)
            local ok, res, detail = SaveDoor(copy, { isNew = false }, src)
            if ok then
                done = done + 1
            else
                errors[#errors + 1] = { id = id, err = res, detail = detail }
            end
        end
    end
    Logs.add('bulk', src, nil, ('%d doors edited, %d errors'):format(done, #errors))
    return { ok = true, done = done, errors = errors, doors = adminList(), groups = Doors.groupList() }
end)

-- permission templates

lib.callback.register('g_doorlock:admin:templateSave', function(src, name, access)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    local ok, err = Templates.save(name, access)
    if not ok then return { ok = false, err = err } end
    return { ok = true, templates = Templates.list() }
end)

lib.callback.register('g_doorlock:admin:templateDelete', function(src, name)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    Templates.delete(name)
    return { ok = true, templates = Templates.list() }
end)

-- door packs

lib.callback.register('g_doorlock:admin:importPack', function(src, file, overwrite)
    if not canAdmin(src) then return { ok = false, err = 'no_permission' } end
    if type(file) ~= 'string' or not file:match('^[%w_%-]+%.json$') then return { ok = false, err = 'err_invalid_data' } end
    local text = LoadResourceFile(GetCurrentResourceName(), 'examples/packs/' .. file)
    if not text then return { ok = false, err = 'err_not_found' } end
    return importText(src, text, overwrite == true)
end)
