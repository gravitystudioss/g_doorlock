GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

GravityBridges.frameworks.standalone = {
    resource = nil,

    init = function()
        return true
    end,

    getJob = function(src)
        return nil
    end,

    getGang = function(src)
        return nil
    end,

    getIdentifier = function(src)
        return GetPlayerIdentifierByType(tostring(src), 'license')
    end,

    getName = function(src)
        return GetPlayerName(src)
    end,

    isAdmin = function(src, groups)
        return false -- standalone relies on ACE only
    end,

    supportsGangs = false,
}
