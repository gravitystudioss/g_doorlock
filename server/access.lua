Access = { pinFails = {} }

function Access.isEditorAdmin(src)
    if not src or src <= 0 then return false end
    return IsPlayerAceAllowed(src, Config.Admin.ace) or Bridge.isFrameworkAdmin(src)
end

function Access.isDoorAdmin(src)
    return IsPlayerAceAllowed(src, Config.Admin.bypassAce) or Access.isEditorAdmin(src)
end

local function matchGroup(list, info)
    if #list == 0 then return nil end -- not configured
    if not info or not info.name then return false end
    for _, entry in ipairs(list) do
        if entry.name == info.name and (info.grade or 0) >= (entry.grade or 0) then
            return true
        end
    end
    return false
end

local function checkJob(src, access)
    if #access.jobs == 0 then return nil end
    local job = Bridge.getJob(src)
    if job and Config.Access.requireOnDuty and job.onduty == false then return false end
    return matchGroup(access.jobs, job)
end

local function checkGang(src, access)
    if #access.gangs == 0 then return nil end
    return matchGroup(access.gangs, Bridge.getGang(src))
end

local function checkIdentifier(src, access)
    if #access.identifiers == 0 then return nil end
    local ident = Bridge.getIdentifier(src)
    if not ident then return false end
    for _, v in ipairs(access.identifiers) do
        if v == ident then return true end
    end
    return false
end

local function checkItems(src, access)
    if #access.items == 0 then return nil end
    for _, item in ipairs(access.items) do
        local slot = Bridge.findKey(src, item.name, item.metadata)
        if slot then return true, { name = item.name, slot = slot, remove = item.remove } end
    end
    return false
end

local function failKey(src, doorId) return ('%d:%s'):format(src, doorId) end

function Access.pinLockedFor(src, doorId)
    local entry = Access.pinFails[failKey(src, doorId)]
    if entry and entry.lockedUntil and entry.lockedUntil > os.time() then
        return entry.lockedUntil - os.time()
    end
    return nil
end

local function registerPinFailure(src, doorId)
    local key = failKey(src, doorId)
    local now = os.time()
    local entry = Access.pinFails[key] or { times = {} }
    local kept = {}
    for _, t in ipairs(entry.times) do
        if now - t < Config.Access.pin.window then kept[#kept + 1] = t end
    end
    kept[#kept + 1] = now
    entry.times = kept
    local locked = false
    if #kept >= Config.Access.pin.maxAttempts then
        entry.lockedUntil = now + Config.Access.pin.lockout
        entry.times = {}
        locked = true
    end
    Access.pinFails[key] = entry
    return #kept, locked
end

function Access.clearPlayer(src)
    local prefix = tostring(src) .. ':'
    for key in pairs(Access.pinFails) do
        if key:sub(1, #prefix) == prefix then Access.pinFails[key] = nil end
    end
end

function Access.sanitizePin(pin)
    if type(pin) == 'number' then pin = tostring(math.floor(pin)) end
    if type(pin) ~= 'string' then return nil end
    if #pin < Config.Access.pin.minLength or #pin > Config.Access.pin.maxLength or not pin:match('^%d+$') then return nil end
    return pin
end

-- hashes = every PIN hash that can open the door (main + temporary)
function Access.evaluate(src, door, access, hashes, pinInput, allowPin)
    hashes = hashes or {}
    local hasPin = allowPin ~= false and #hashes > 0
    local results = {}
    local matchedItem

    if access.public then results[#results + 1] = true end
    if access.admin then results[#results + 1] = Access.isDoorAdmin(src) end

    local r = checkJob(src, access)
    if r ~= nil then results[#results + 1] = r end
    r = checkGang(src, access)
    if r ~= nil then results[#results + 1] = r end
    r = checkIdentifier(src, access)
    if r ~= nil then results[#results + 1] = r end

    local itemOk, item = checkItems(src, access)
    if itemOk ~= nil then results[#results + 1] = itemOk end
    if itemOk then matchedItem = item end

    local anyOk, allOk = false, true
    for _, v in ipairs(results) do
        if v then anyOk = true else allOk = false end
    end

    if access.mode == 'any' then
        if anyOk then return { granted = true, item = matchedItem } end
        if not hasPin then return { granted = false, reason = 'no_access' } end
    else
        -- 'all': every configured criterion must pass, the PIN only when the door has one
        if #results == 0 and not access.pin then return { granted = false, reason = 'no_access' } end
        if not allOk then return { granted = false, reason = 'no_access' } end
        if not access.pin then return { granted = true, item = matchedItem } end
        -- PIN configured but unusable here (auto gate) or missing hash: the criterion fails
        if not hasPin then return { granted = false, reason = 'no_access' } end
    end

    if Access.pinLockedFor(src, door.id) then return { granted = false, reason = 'pin_locked' } end
    if pinInput == nil then return { granted = false, needPin = true } end
    local pin = Access.sanitizePin(pinInput)
    local ok = false
    if pin then
        -- depending on the artifact this native gives back true or 1
        for _, hash in ipairs(hashes) do
            local res = VerifyPasswordHash(pin, hash)
            if res == true or res == 1 then
                ok = true
                break
            end
        end
        if Config.Debug then
            print(('[g_doorlock] pin check door=%s len=%d hashes=%d result=%s'):format(door.id, #pin, #hashes, tostring(ok)))
        end
    elseif Config.Debug then
        print(('[g_doorlock] pin rejected by format on door=%s (got %s)'):format(door.id, type(pinInput)))
    end
    if ok then
        Access.pinFails[failKey(src, door.id)] = nil
        return { granted = true, item = matchedItem, viaPin = true }
    end
    local attempts, lockedOut = registerPinFailure(src, door.id)
    pcall(Hooks.onPinFailed, src, Utils.deepCopy(door), attempts, lockedOut)
    if lockedOut then
        Logs.add('pin_lockout', src, door.id, ('%d wrong PIN attempts'):format(attempts))
        return { granted = false, reason = 'pin_locked' }
    end
    return { granted = false, reason = 'pin_wrong', attemptsLeft = Config.Access.pin.maxAttempts - attempts }
end

function Access.hashPin(pin)
    return GetPasswordHash(pin)
end
