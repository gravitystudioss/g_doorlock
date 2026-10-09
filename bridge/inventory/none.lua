GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

GravityBridges.inventories.none = {
    resource = nil,
    supportsMetadata = false,
    findKey = function() return nil end,
    removeItem = function() return false end,
}
