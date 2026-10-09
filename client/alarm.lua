-- alarm sound at the door + notification and blip for the jobs in Config.Alarm

local ringing = {} -- id -> end time

RegisterNetEvent('g_doorlock:alarm', function(id, coords, bucket)
    if ringing[id] then
        ringing[id] = GetGameTimer() + Config.Alarm.duration * 1000
        return
    end
    ringing[id] = GetGameTimer() + Config.Alarm.duration * 1000
    local pos = vector3(coords.x, coords.y, coords.z)

    CreateThread(function()
        while ringing[id] and GetGameTimer() < ringing[id] do
            local dist = #(GetEntityCoords(PlayerPedId()) - pos)
            if dist <= Config.Alarm.range then
                local volume = Config.Sounds.volume * (1.0 - (dist / Config.Alarm.range) * 0.8)
                Nui.send('sound', { type = 'synth', preset = 'alarm', volume = volume })
            end
            Wait(1300)
        end
        ringing[id] = nil
    end)
end)

RegisterNetEvent('g_doorlock:alarmNotify', function(data)
    Notify(L('alarm_text', data.name), 'error', L('alarm_title'), 8000)

    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.2)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('alarm_title'))
    EndTextCommandSetBlipName(blip)

    SetTimeout(Config.Alarm.blipTime * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

-- admin /doorlock: nearest door within 5 m
RegisterNetEvent('g_doorlock:quickToggle', function()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, door in ipairs(ClientDoors.nearby(pos, 5.0)) do
        local dist = #(pos - door.center)
        if not bestDist or dist < bestDist then best, bestDist = door, dist end
    end
    if not best then
        Notify(L('quick_none'), 'error')
        return
    end
    local locked = lib.callback.await('g_doorlock:admin:quickToggle', false, best.id)
    if locked == nil then return end
    Notify(L(locked and 'quick_locked' or 'quick_unlocked', best.name), 'success')
end)

-- doorbell
RegisterNetEvent('g_doorlock:knock', function(name)
    Notify(L('knock_text', name), 'info', L('knock_title'), 6000)
end)

RegisterNetEvent('g_doorlock:knockSound', function(coords)
    Nui.playSoundKey('knock', vector3(coords.x, coords.y, coords.z))
end)
