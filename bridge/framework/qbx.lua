GravityBridges = GravityBridges or { frameworks = {}, inventories = {} }

local function getPlayerData(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData or nil
end

GravityBridges.frameworks.qbx = {
    resource = 'qbx_core',

    init = function()
        return GetResourceState('qbx_core') == 'started'
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

    registerUsable = function(item, cb)
        exports.qbx_core:CreateUseableItem(item, cb)
    end,

    isAdmin = function(src, groups)
        for _, g in ipairs(groups or {}) do
            if IsPlayerAceAllowed(src, g) then return true end
        end
        return false
    end,

    supportsGangs = true,
}
