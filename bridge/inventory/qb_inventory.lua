GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

local QBCore

local function getPlayer(src)
    if not QBCore then QBCore = exports['qb-core']:GetCoreObject() end
    return QBCore.Functions.GetPlayer(src)
end

GravityBridges.inventories['qb-inventory'] = {
    resource = 'qb-inventory',
    alternatives = { 'ps-inventory', 'lj-inventory' },
    supportsMetadata = true,

    findKey = function(src, itemName, metaValue)
        local player = getPlayer(src)
        if not player then return nil end
        for slot, item in pairs(player.PlayerData.items or {}) do
            if item and item.name == itemName and (item.amount or item.count or 1) > 0
                and Utils.keyMatches(item.info, metaValue) then
                return item.slot or slot
            end
        end
        return nil
    end,


    removeItem = function(src, itemName, slot)
        local player = getPlayer(src)
        return player and player.Functions.RemoveItem(itemName, 1, slot) == true or false
    end,

    listItems = function()
        if not QBCore then QBCore = exports['qb-core']:GetCoreObject() end
        local list = {}
        for name, item in pairs(QBCore.Shared.Items or {}) do
            list[#list + 1] = { name = name, label = item.label }
        end
        return list
    end,
}
