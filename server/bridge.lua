Bridge = { name = 'standalone', inventoryName = 'none' }

local function started(res)
    return res ~= nil and GetResourceState(res) == 'started'
end

local function pickFramework()
    local wanted = Config.Framework
    if wanted ~= 'auto' then
        if not GravityBridges.frameworks[wanted] then
            print(('^1[g_doorlock] Unknown framework "%s", falling back to auto^0'):format(tostring(wanted)))
        else
            return wanted
        end
    end
    if started('qbx_core') then return 'qbx' end
    if started('qb-core') then return 'qb' end
    if started('es_extended') then return 'esx' end
    return 'standalone'
end

local function pickInventory()
    local wanted = Config.Inventory
    if wanted ~= 'auto' then
        if GravityBridges.inventories[wanted] then return wanted end
        print(('^1[g_doorlock] Unknown inventory "%s", falling back to auto^0'):format(tostring(wanted)))
    end
    if started('ox_inventory') then return 'ox_inventory' end
    if started('qs-inventory') then return 'qs-inventory' end
    local qb = GravityBridges.inventories['qb-inventory']
    if started(qb.resource) then return 'qb-inventory' end
    for _, alt in ipairs(qb.alternatives) do
        if started(alt) and (Bridge.name == 'qb' or Bridge.name == 'qbx') then return 'qb-inventory' end
    end
    if Bridge.name == 'esx' then return 'esx' end
    return 'none'
end

function Bridge.init()
    Bridge.name = pickFramework()
    local fw = GravityBridges.frameworks[Bridge.name]
    if fw.resource and GetResourceState(fw.resource) ~= 'started' then
        print(('^1[g_doorlock] Framework resource "%s" is not started. Start it before g_doorlock.^0'):format(fw.resource))
    end
    local ok, res = pcall(fw.init)
    if not ok or not res then
        print(('^1[g_doorlock] Failed to initialise "%s" bridge (%s). Using standalone.^0'):format(Bridge.name, tostring(res)))
        Bridge.name = 'standalone'
        fw = GravityBridges.frameworks.standalone
    end
    Bridge.fw = fw

    Bridge.inventoryName = pickInventory()
    Bridge.inv = GravityBridges.inventories[Bridge.inventoryName]
    print(('[g_doorlock] framework: ^2%s^0 | inventory: ^2%s^0'):format(Bridge.name, Bridge.inventoryName))
end

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        print(('^1[g_doorlock] bridge error: %s^0'):format(tostring(res)))
        return nil
    end
    return res
end

-- job / gang / identifier are read many times in a row (one per door), keep them for half a second
local cache = {}

local function cached(kind, src)
    local key = kind .. src
    local now = GetGameTimer()
    local hit = cache[key]
    if hit and hit.time > now then return hit.value end
    local value = safe(Bridge.fw[kind], src)
    cache[key] = { value = value, time = now + 500 }
    return value
end

function Bridge.getJob(src) return cached('getJob', src) end
function Bridge.getGang(src) return cached('getGang', src) end
function Bridge.getIdentifier(src) return cached('getIdentifier', src) end

function Bridge.clearCache(src)
    cache['getJob' .. src] = nil
    cache['getGang' .. src] = nil
    cache['getIdentifier' .. src] = nil
end
function Bridge.getName(src) return safe(Bridge.fw.getName, src) or GetPlayerName(src) or ('#' .. tostring(src)) end
function Bridge.findKey(src, name, meta) return safe(Bridge.inv.findKey, src, name, meta) end
function Bridge.removeItem(src, name, slot) return safe(Bridge.inv.removeItem, src, name, slot) end

-- items for the editor list: { { name, label } } sorted by name
function Bridge.listItems()
    local list = Bridge.inv.listItems and safe(Bridge.inv.listItems) or {}
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Bridge.isFrameworkAdmin(src)
    if not ServerConfig.UseFrameworkAdmin then return false end
    local groups = ServerConfig.AdminGroups[Bridge.name]
    if not groups then return false end
    return safe(Bridge.fw.isAdmin, src, groups) == true
end
