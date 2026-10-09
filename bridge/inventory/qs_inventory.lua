GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

GravityBridges.inventories['qs-inventory'] = {
    resource = 'qs-inventory',
    supportsMetadata = true,

    findKey = function(src, itemName, metaValue)
        local items = exports['qs-inventory']:GetInventory(src)
        for slot, item in pairs(items or {}) do
            if item and item.name == itemName and (item.amount or item.count or 1) > 0
                and Utils.keyMatches(item.info, metaValue) then
                return item.slot or slot
            end
        end
        return nil
    end,


    removeItem = function(src, itemName, slot)
        return exports['qs-inventory']:RemoveItem(src, itemName, 1, slot) == true
    end,

    listItems = function()
        local list = {}
        for name, item in pairs(exports['qs-inventory']:GetItemList() or {}) do
            list[#list + 1] = { name = name, label = item.label }
        end
        return list
    end,
}
