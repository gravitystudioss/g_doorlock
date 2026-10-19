Logs = {}

local function actorOf(src)
    if not src or src == 0 then return 'system' end
    local ident = Bridge.getIdentifier(src) or GetPlayerIdentifierByType(tostring(src), 'license') or '?'
    return ('%s [%d] (%s)'):format(GetPlayerName(src) or '?', src, ident):sub(1, 128)
end

local function sendDiscord(action, doorId, actor, details)
    local url = ServerConfig.Logs.discordWebhook
    if not url or url == '' then return end
    if not ServerConfig.Logs.discordActions[action] then return end
    local payload = json.encode({
        username = 'Gravity Doorlock',
        embeds = { {
            title = ('%s - %s'):format(action, doorId or '-'),
            description = details ~= '' and details or nil,
            color = 0x7C5CFF,
            fields = { { name = 'Actor', value = actor, inline = false } },
            footer = { text = 'Gravity Studios - g_doorlock' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    })
    PerformHttpRequest(url, function(status)
        if status < 200 or status >= 300 then
            print(('^3[g_doorlock] Discord webhook returned HTTP %s^0'):format(tostring(status)))
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

function Logs.add(action, src, doorId, details)
    local provider = Config.Bridge.logs
    if provider == 'none' then return end
    details = details or ''
    local actor = actorOf(src)
    if provider == 'ox_lib' then
        local ok, err = pcall(function()
            lib.logger(src or 0, action, ('%s | %s | %s'):format(doorId or '-', actor, details))
        end)
        if ok then return end
        print(('^3[g_doorlock] ox_lib logger failed (%s); using console^0'):format(tostring(err)))
        Config.Bridge.logs = 'console'
        provider = 'console'
    elseif provider ~= 'console' and provider ~= 'discord' then
        print(('^3[g_doorlock] Unknown log provider "%s"; using console^0'):format(tostring(provider)))
        Config.Bridge.logs = 'console'
        provider = 'console'
    end
    if provider == 'console' or Config.Debug then
        print(('[g_doorlock] %s | %s | %s %s'):format(action, doorId or '-', actor, details))
    end
    if provider == 'discord' then sendDiscord(action, doorId, actor, details) end
end
