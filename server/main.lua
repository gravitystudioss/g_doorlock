CreateThread(function()
    Bridge.init()

    -- remote without a key: the item is used from the inventory (ox_inventory uses the client export)
    local remote = Config.Extras.remote
    if not remote.key and remote.item and Bridge.inventoryName ~= 'ox_inventory' and Bridge.fw.registerUsable then
        Bridge.fw.registerUsable(remote.item, function(src)
            TriggerClientEvent('g_doorlock:useRemote', src)
        end)
    end

    local ok, err = pcall(DB.ensureSchema)
    if not ok then
        print('^1[g_doorlock] database error, did you import sql/install.sql and start oxmysql first?^0')
        print(err)
        return
    end
    Doors.load()
    Templates.load()

    if GetConvar('onesync', 'off') == 'off' then
        print('^1[g_doorlock] OneSync is required (distance and bucket checks).^0')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    RateLimit.clear(src)
    Bridge.clearCache(src)
    Access.clearPlayer(src)
end)
