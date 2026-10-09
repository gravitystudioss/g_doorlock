GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

local ESX

GravityBridges.frameworks.esx = {
    resource = 'es_extended',

    init = function()
        ESX = exports.es_extended:getSharedObject()
        return ESX ~= nil
    end,

    getJob = function(src)
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return nil end
        local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
        if not job then return nil end
        return { name = job.name, grade = tonumber(job.grade) or 0, onduty = job.onDuty ~= false }
    end,

    -- ESX has no native gangs.
    getGang = function(src)
        return nil
    end,

    -- Character identifier (e.g. "char1:abcdef..." with multicharacter).
    getIdentifier = function(src)
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and (xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier) or nil
    end,

    getName = function(src)
        local xPlayer = ESX.GetPlayerFromId(src)
        return xPlayer and xPlayer.getName and xPlayer.getName() or GetPlayerName(src)
    end,

    isAdmin = function(src, groups)
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        local group = xPlayer.getGroup and xPlayer.getGroup() or xPlayer.group
        for _, g in ipairs(groups or {}) do
            if g == group then return true end
        end
        return false
    end,

    registerUsable = function(item, cb)
        ESX.RegisterUsableItem(item, cb)
    end,

    supportsGangs = false,
}
