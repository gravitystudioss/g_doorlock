ClientDoors = { list = {}, grid = {}, loaded = false }

local CELL = 64.0

local function cellKey(cx, cy)
    return cx .. ':' .. cy
end

local function gridAdd(door)
    local cx, cy = math.floor(door.center.x / CELL), math.floor(door.center.y / CELL)
    local key = cellKey(cx, cy)
    ClientDoors.grid[key] = ClientDoors.grid[key] or {}
    ClientDoors.grid[key][door.id] = true
    door.cell = key
end

local function gridRemove(door)
    if door.cell and ClientDoors.grid[door.cell] then
        ClientDoors.grid[door.cell][door.id] = nil
        if next(ClientDoors.grid[door.cell]) == nil then
            ClientDoors.grid[door.cell] = nil
        end
    end
end

-- Apply state on registration, nearby entry and server updates only.
function ClientDoors.apply(door, snap)
    local state = door.locked and 1 or 0
    local gate = door.type == 'gate' or door.type == 'garage'
    for _, leaf in ipairs(door.doors) do
        if gate then
            DoorSystemSetAutomaticRate(leaf.hash, 1.5, false, false)
            if door.locked then DoorSystemSetHoldOpen(leaf.hash, false) end
            DoorSystemSetAutomaticDistance(leaf.hash, door.locked and 0.0 or door.autoDistance, false, false)
        end
        if snap and door.locked then
            DoorSystemSetOpenRatio(leaf.hash, 0.0, false, true)
        end
        DoorSystemSetDoorState(leaf.hash, state, false, true)
    end
end

local function unregister(door)
    for _, leaf in ipairs(door.doors) do
        if leaf.hash and IsDoorRegisteredWithSystem(leaf.hash) then
            RemoveDoorFromSystem(leaf.hash)
        end
    end
    gridRemove(door)
end

local function register(door)
    local x, y, z = Utils.doorCenter(door)
    door.center = vector3(x, y, z)
    for i, leaf in ipairs(door.doors) do
        leaf.hash = Utils.leafHash(door.id, i)
        leaf.vec = vector3(leaf.coords.x, leaf.coords.y, leaf.coords.z)
        if not IsDoorRegisteredWithSystem(leaf.hash) then
            AddDoorToSystem(leaf.hash, leaf.model, leaf.coords.x, leaf.coords.y, leaf.coords.z, false, false, false)
        end
    end
    gridAdd(door)
    ClientDoors.apply(door)
end

function ClientDoors.set(data)
    local old = ClientDoors.list[data.id]
    if old then
        if old.stateRev and data.stateRev and old.stateRev > data.stateRev then
            data.locked = old.locked
            data.stateRev = old.stateRev
        end
        unregister(old)
    end
    ClientDoors.list[data.id] = data
    register(data)
end

function ClientDoors.remove(id)
    local old = ClientDoors.list[id]
    if not old then return end
    unregister(old)
    ClientDoors.list[id] = nil
end

function ClientDoors.load(list)
    for id in pairs(ClientDoors.list) do
        ClientDoors.remove(id)
    end
    for _, data in ipairs(list or {}) do
        ClientDoors.set(data)
    end
    ClientDoors.loaded = true
end

function ClientDoors.clearAll()
    for id in pairs(ClientDoors.list) do
        ClientDoors.remove(id)
    end
end

function ClientDoors.nearby(coords, radius)
    local out = {}
    local minX, maxX = math.floor((coords.x - radius) / CELL), math.floor((coords.x + radius) / CELL)
    local minY, maxY = math.floor((coords.y - radius) / CELL), math.floor((coords.y + radius) / CELL)
    for cx = minX, maxX do
        for cy = minY, maxY do
            local cell = ClientDoors.grid[cellKey(cx, cy)]
            if cell then
                for id in pairs(cell) do
                    local door = ClientDoors.list[id]
                    if door and #(coords - door.center) <= radius then
                        out[#out + 1] = door
                    end
                end
            end
        end
    end
    return out
end

RegisterNetEvent('g_doorlock:state', function(id, locked, rev)
    local door = ClientDoors.list[id]
    if not door then return end
    if door.stateRev and rev <= door.stateRev then return end
    local changed = door.locked ~= locked
    door.locked = locked
    door.stateRev = rev
    ClientDoors.apply(door, changed)
    if changed then
        Nui.playSound(locked and 'lock' or 'unlock', door.center, door)
    end
    Interact.refresh(door)
end)

RegisterNetEvent('g_doorlock:update', function(data)
    if type(data) ~= 'table' or not data.id then return end
    ClientDoors.set(data)
    Interact.onDoorChanged(data.id)
end)

RegisterNetEvent('g_doorlock:remove', function(id)
    ClientDoors.remove(id)
    Interact.onDoorChanged(id)
end)
