GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

local ESX

local function getPlayer(src)
    if not ESX then ESX = exports.es_extended:getSharedObject() end
    return ESX.GetPlayerFromId(src)
end

-- the default esx inventory has no metadata: items that need one never match
GravityBridges.inventories.esx = {
    resource = 'es_extended',
    supportsMetadata = false,

    findKey = function(src, itemName, metaValue)
        if metaValue ~= nil then return nil end
        local xPlayer = getPlayer(src)
        if not xPlayer then return nil end
        local item = xPlayer.getInventoryItem(itemName)
        if item and (item.count or 0) > 0 then return 0 end
        return nil
    end,


    removeItem = function(src, itemName)
        local xPlayer = getPlayer(src)
        if not xPlayer then return false end
        xPlayer.removeInventoryItem(itemName, 1)
        return true
    end,

    listItems = function()
        if not ESX then ESX = exports.es_extended:getSharedObject() end
        local list = {}
        for name, item in pairs(ESX.Items or {}) do
            list[#list + 1] = { name = name, label = item.label }
        end
        return list
    end,
}
