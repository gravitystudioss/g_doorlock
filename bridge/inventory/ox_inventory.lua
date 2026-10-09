GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

GravityBridges.inventories.ox_inventory = {
    resource = 'ox_inventory',
    supportsMetadata = true,

    findKey = function(src, itemName, metaValue)
        local slots = exports.ox_inventory:Search(src, 'slots', itemName)
        if type(slots) ~= 'table' then return nil end
        for _, slot in pairs(slots) do
            if (slot.count or 1) > 0 and Utils.keyMatches(slot.metadata, metaValue) then
                return slot.slot
            end
        end
        return nil
    end,


    removeItem = function(src, itemName, slot)
        return exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot) == true
    end,

    listItems = function()
        local list = {}
        for name, item in pairs(exports.ox_inventory:Items() or {}) do
            list[#list + 1] = { name = name, label = item.label }
        end
        return list
    end,
}
