Utils = {}

function Utils.deepCopy(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = Utils.deepCopy(v)
    end
    return copy
end

function Utils.round(n, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(n * mult + 0.5) / mult
end

function Utils.dist3(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- middle point between the leaves of a door
function Utils.doorCenter(door)
    local leaves = door.doors or {}
    if #leaves == 0 then
        return 0.0, 0.0, 0.0
    end

    local x, y, z = 0.0, 0.0, 0.0
    for _, leaf in ipairs(leaves) do
        x = x + leaf.coords.x
        y = y + leaf.coords.y
        z = z + leaf.coords.z
    end
    return x / #leaves, y / #leaves, z / #leaves
end

-- hash used in the GTA door system, built from the door id so it never changes
function Utils.leafHash(doorId, index)
    return joaat('g_doorlock:' .. doorId .. ':' .. index)
end

-- Match key metadata; a nil value accepts any key.
-- Expired keys are rejected.
function Utils.keyMatches(meta, value)
    if type(meta) == 'table' then
        local expires = tonumber(meta[Config.Access.keys.expiresField])
        if expires and expires < os.time() then
            return false
        end
    end
    if value == nil then
        return true
    end
    return type(meta) == 'table' and meta[Config.Access.keys.metadataField] ~= nil
        and tostring(meta[Config.Access.keys.metadataField]) == value
end
