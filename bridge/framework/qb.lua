GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

local QBCore

local function getPlayerData(src)
    local player = QBCore.Functions.GetPlayer(src)
    return player and player.PlayerData or nil
end

GravityBridges.frameworks.qb = {
    resource = 'qb-core',

    init = function()
        QBCore = exports['qb-core']:GetCoreObject()
        return QBCore ~= nil
    end,

    getJob = function(src)
        local pd = getPlayerData(src)
        if not pd or not pd.job then return nil end
        local grade = type(pd.job.grade) == 'table' and pd.job.grade.level or pd.job.grade
        return { name = pd.job.name, grade = tonumber(grade) or 0, onduty = pd.job.onduty == true }
    end,

    getGang = function(src)
        local pd = getPlayerData(src)
        if not pd or not pd.gang then return nil end
        local grade = type(pd.gang.grade) == 'table' and pd.gang.grade.level or pd.gang.grade
        return { name = pd.gang.name, grade = tonumber(grade) or 0 }
    end,

    getIdentifier = function(src)
        local pd = getPlayerData(src)
        return pd and pd.citizenid or nil
    end,

    getName = function(src)
        local pd = getPlayerData(src)
        if pd and pd.charinfo then
            return ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '')
        end
        return GetPlayerName(src)
    end,

    -- QBCore permissions are ACE objects ("add_ace group.admin admin allow").
    registerUsable = function(item, cb)
        QBCore.Functions.CreateUseableItem(item, cb)
    end,

    isAdmin = function(src, groups)
        for _, g in ipairs(groups or {}) do
            if IsPlayerAceAllowed(src, g) then return true end
        end
        return false
    end,

    supportsGangs = true,
}
