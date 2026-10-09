Interact = {
    nearby = {},      -- id -> true (doors inside nearbyRadius)
    zones = {},       -- id -> ox_target zone id
    current = nil,    -- closest door in interact range
    busy = false,
    keypadDoor = nil,
    autoCooldown = {},
    access = {},      -- id -> true when the player can open it without break-in
}

local useTarget = false

local function shownState(door)
    if not door then return nil end
    return door.id .. ':' .. tostring(door.locked) .. ':' .. tostring(door.broken)
end

local lastShown = nil

local function updateIndicator()
    local system = Config.TextUI.system
    if not system then return end
    local door = Interact.current
    if door and door.hideIndicator then door = nil end
    local key = shownState(door)
    if key == lastShown then return end
    lastShown = key

    if not door then
        TextUI.hide()
    else
        local state = door.broken and L('ed_broken') or L(door.locked and 'locked' or 'unlocked')
        local text = ('%s - %s'):format(state, door.name)
        if not useTarget then
            text = ('[%s] %s'):format(Config.Interaction.key, text)
            local action = Breakin.actionLabel(door)
            if action then text = ('%s | [%s] %s'):format(text, Config.Interaction.actionKey, action) end
        end
        if TextUI.show(text, door.locked) then return end
    end

    if not door then
        Nui.send('indicator', { show = false })
        return
    end
    Nui.send('indicator', {
        show = true,
        locked = door.locked,
        broken = door.broken,
        name = door.name,
        key = not useTarget and Config.Interaction.key or nil,
        actionKey = not useTarget and Config.Interaction.actionKey or nil,
        action = not useTarget and Breakin.actionLabel(door) or nil,
    })
end

local function playUseAnim()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) then return end
    local dict = 'anim@heists@keycard@'
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        local t = GetGameTimer() + 1000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    end
    if HasAnimDictLoaded(dict) then
        TaskPlayAnim(ped, dict, 'exit', 8.0, 8.0, 900, 48, 0.0, false, false, false)
        RemoveAnimDict(dict)
    end
end

local showDenied

-- remote control: nearest door with the remote option in range
function Interact.useRemote()
    if Nui.focus or Editor.selecting then return end
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, door in ipairs(ClientDoors.nearby(pos, Config.Extras.remote.range)) do
        local dist = #(pos - door.center)
        if door.remote and (not bestDist or dist < bestDist) then best, bestDist = door, dist end
    end
    if not best then return end
    CreateThread(function()
        local res = lib.callback.await('g_doorlock:remote', false, best.id)
        if res and res.ok then
            Nui.playSoundKey('beep', nil)
        elseif res then
            showDenied(best, res)
        end
    end)
end

-- item use: ox_inventory calls the export, the other inventories send the event
exports('useRemote', function() Interact.useRemote() end)
RegisterNetEvent('g_doorlock:useRemote', function() Interact.useRemote() end)

function showDenied(door, res)
    local text
    if res.reason == 'pin_wrong' then
        text = L('pin_wrong', res.attemptsLeft or 0)
    elseif res.reason == 'pin_locked' then
        text = L('pin_locked')
    elseif res.reason == 'distance' then
        text = L('too_far')
    elseif res.reason == 'rate' then
        text = L('slow_down')
    elseif res.reason == 'hook' and res.message then
        text = res.message
    elseif res.reason == 'not_found' then
        text = L('door_missing')
    elseif res.reason == 'broken' then
        text = L('door_broken')
    elseif res.reason == 'no_remote' then
        text = L('no_remote')
    else
        text = L('access_denied')
    end
    Notify(text, 'error')
    Nui.send('indicatorDenied', {})
    Nui.playSound('denied', nil)
end

-- ask the server to lock/unlock. pin only when the keypad sends it
local lastUse = 0

function Interact.use(door, pin)
    if Interact.busy or not door then return end
    -- spamming the key makes the door fight its own physics
    if not pin and GetGameTimer() - lastUse < 800 then return end
    lastUse = GetGameTimer()
    Interact.busy = true
    local want = not door.locked
    local res = lib.callback.await('g_doorlock:toggle', false, door.id, want, pin)
    Interact.busy = false
    if not res then return end

    if res.needPin then
        Interact.openKeypad(door)
        return
    end
    if res.ok then
        if pin then Interact.closeKeypad(true) end
        playUseAnim()
        return
    end
    if pin and res.reason == 'pin_wrong' then
        Nui.send('keypad:error', { text = L('pin_wrong', res.attemptsLeft or 0) })
        Nui.playSound('denied', nil)
        return
    end
    if pin then Interact.closeKeypad(true) end
    showDenied(door, res)
end

function Interact.openKeypad(door)
    Interact.keypadDoor = door.id
    Nui.send('keypad:open', { name = door.name, locked = door.locked })
    Nui.setFocus('keypad')
end

function Interact.closeKeypad(fromLua)
    Interact.keypadDoor = nil
    if fromLua then
        Nui.send('keypad:close', {})
        if Nui.focus == 'keypad' then Nui.setFocus(nil) end
    end
end

RegisterNUICallback('keypad:submit', function(data, cb)
    cb(true)
    local door = Interact.keypadDoor and ClientDoors.list[Interact.keypadDoor]
    if not door then
        Interact.closeKeypad(true)
        return
    end
    if type(data.pin) ~= 'string' then return end
    Interact.use(door, data.pin)
end)

local function addZone(door)
    if not useTarget or Interact.zones[door.id] then return end
    local id = door.id
    local radius = (door.type == 'gate' or door.type == 'garage') and 2.5 or 1.2
    Interact.zones[id] = exports.ox_target:addSphereZone({
        coords = door.center,
        radius = radius,
        debug = Config.Debug,
        options = {
            {
                name = 'gdl_unlock_' .. id,
                icon = Config.Interaction.targetIcon,
                label = L('target_unlock'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and d.locked
                end,
                onSelect = function()
                    Interact.use(ClientDoors.list[id])
                end,
            },
            {
                name = 'gdl_lock_' .. id,
                icon = Config.Interaction.targetIcon,
                label = L('target_lock'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and not d.locked and not d.broken
                end,
                onSelect = function()
                    Interact.use(ClientDoors.list[id])
                end,
            },
            {
                name = 'gdl_lockpick_' .. id,
                icon = Config.Interaction.lockpickIcon,
                label = L('target_lockpick'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and d.locked and d.canLockpick and not Interact.access[id] and not Breakin.busy
                end,
                onSelect = function()
                    Breakin.lockpick(ClientDoors.list[id])
                end,
            },
            {
                name = 'gdl_knock_' .. id,
                icon = Config.Interaction.bellIcon,
                label = L('target_knock'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and d.locked and d.bell and not Interact.access[id]
                end,
                onSelect = function()
                    Breakin.knock(ClientDoors.list[id])
                end,
            },
            {
                name = 'gdl_hack_' .. id,
                icon = Config.Interaction.hackIcon,
                label = L('target_hack'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and d.locked and d.canHack and not Interact.access[id] and not Breakin.busy
                end,
                onSelect = function()
                    Breakin.hack(ClientDoors.list[id])
                end,
            },
            {
                name = 'gdl_repair_' .. id,
                icon = Config.Interaction.repairIcon,
                label = L('target_repair'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and d.broken and not Breakin.busy
                end,
                onSelect = function()
                    Breakin.repair(ClientDoors.list[id])
                end,
            },
            {
                name = 'gdl_breach_' .. id,
                icon = Config.Interaction.breachIcon,
                label = L('target_breach'),
                distance = door.interactDistance,
                canInteract = function()
                    local d = ClientDoors.list[id]
                    return d ~= nil and d.locked and d.canBreach and not Interact.access[id] and not Breakin.busy
                end,
                onSelect = function()
                    Breakin.breach(ClientDoors.list[id])
                end,
            },
        },
    })
end

local function removeZone(id)
    if Interact.zones[id] then
        exports.ox_target:removeZone(Interact.zones[id], true)
        Interact.zones[id] = nil
    end
end

function Interact.removeAllZones()
    for id in pairs(Interact.zones) do
        removeZone(id)
    end
end

function Interact.onDoorChanged(id)
    removeZone(id)
    Interact.nearby[id] = nil
    if Interact.current and Interact.current.id == id then
        Interact.current = ClientDoors.list[id]
        -- false never matches a real key, so the pill is always redrawn (or hidden if the door is gone)
        lastShown = false
        updateIndicator()
    end
    if Interact.keypadDoor == id and not ClientDoors.list[id] then
        Interact.closeKeypad(true)
    end
end

function Interact.refresh(door)
    if Interact.current and Interact.current.id == door.id then
        Interact.current = door
        updateIndicator()
    end
end

function Interact.checkAccess(ids)
    if #ids == 0 then return end
    CreateThread(function()
        local res = lib.callback.await('g_doorlock:access', false, ids) or {}
        for _, id in ipairs(ids) do Interact.access[id] = res[id] == true end
        lastShown = false
        updateIndicator()
    end)
end

local function recheckAccess()
    local ids = {}
    for id in pairs(Interact.nearby) do ids[#ids + 1] = id end
    Interact.checkAccess(ids)
end

-- job / gang changes
RegisterNetEvent('esx:setJob', recheckAccess)
RegisterNetEvent('QBCore:Client:OnJobUpdate', recheckAccess)
RegisterNetEvent('QBCore:Client:OnGangUpdate', recheckAccess)

local function tryAutoGate(door, dist, ped)
    if door.autoDistance <= 0 or not door.locked or dist > door.autoDistance then return end
    if Config.Doors.autoGate.requireVehicle and not IsPedInAnyVehicle(ped, false) then return end
    local now = GetGameTimer()
    if Interact.autoCooldown[door.id] and Interact.autoCooldown[door.id] > now then return end
    Interact.autoCooldown[door.id] = now + Config.Doors.autoGate.cooldown
    CreateThread(function()
        lib.callback.await('g_doorlock:auto', false, door.id)
    end)
end

-- slow loop: which doors are around (grid lookup, every 1s)
CreateThread(function()
    while true do
        if ClientDoors.loaded then
            local pos = GetEntityCoords(PlayerPedId())
            local found, added = {}, {}
            for _, door in ipairs(ClientDoors.nearby(pos, Config.Doors.distances.nearbyRadius)) do
                found[door.id] = true
                if not Interact.nearby[door.id] then
                    Interact.nearby[door.id] = true
                    added[#added + 1] = door.id
                    ClientDoors.apply(door)
                    addZone(door)
                end
            end
            for id in pairs(Interact.nearby) do
                if not found[id] then
                    Interact.nearby[id] = nil
                    Interact.access[id] = nil
                    removeZone(id)
                end
            end
            Interact.checkAccess(added)
        end
        Wait(1000)
    end
end)

-- fast loop only when there is something near
CreateThread(function()
    while true do
        local sleep = 1000
        if next(Interact.nearby) then
            sleep = 150
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local best, bestDist = nil, nil
            local gap = math.huge -- metres to the closest interaction / auto gate range
            for id in pairs(Interact.nearby) do
                local door = ClientDoors.list[id]
                if door then
                    local dist = #(pos - door.center)
                    if dist <= door.interactDistance and (not bestDist or dist < bestDist) then
                        best, bestDist = door, dist
                    end
                    gap = math.min(gap, dist - math.max(door.interactDistance, door.autoDistance))
                    tryAutoGate(door, dist, ped)
                end
            end
            Interact.current = best
            -- far from every door: check less often (cars move fast, keep a wider margin)
            if gap > (IsPedInAnyVehicle(ped, false) and 25.0 or 8.0) then sleep = 500 end
        else
            Interact.current = nil
        end
        updateIndicator()
        Wait(sleep)
    end
end)

function Interact.init()
    local mode = Config.Interaction.target
    if mode == 'auto' then
        useTarget = GetResourceState('ox_target') == 'started'
    else
        useTarget = mode == true
    end
    if useTarget and GetResourceState('ox_target') ~= 'started' then
        print('^1[g_doorlock] Config.Interaction.target = true but ox_target is not started, using key^0')
        useTarget = false
    end

    lib.addKeybind({
        name = 'g_doorlock_use',
        description = L('keybind_desc'),
        defaultKey = Config.Interaction.key,
        onPressed = function()
            if useTarget or Nui.focus or Editor.selecting then return end
            if Interact.current then
                Interact.use(Interact.current)
            end
        end,
    })

    if Config.Extras.remote.key then
        lib.addKeybind({
            name = 'g_doorlock_remote',
            description = L('keybind_remote_desc'),
            defaultKey = Config.Extras.remote.key,
            onPressed = Interact.useRemote,
        })
    end

    lib.addKeybind({
        name = 'g_doorlock_action',
        description = L('keybind_action_desc'),
        defaultKey = Config.Interaction.actionKey,
        onPressed = function()
            if useTarget or Nui.focus or Editor.selecting or Breakin.busy then return end
            Breakin.openMenu(Interact.current)
        end,
    })
end
