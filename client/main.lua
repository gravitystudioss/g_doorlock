CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    Interact.init()
    local list = lib.callback.await('g_doorlock:getDoors', false)
    ClientDoors.load(list)
end)

RegisterNUICallback('ready', function(_, cb)
    cb(true)
    Nui.init()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    Editor.selecting = false
    Editor.open = false
    Interact.removeAllZones()
    ClientDoors.clearAll()
    TextUI.hide()
end)

exports('getDoorState', function(id)
    local door = ClientDoors.list[id]
    if not door then return nil end
    return door.locked
end)

exports('getNearestDoor', function()
    local door = Interact.current
    if not door then return nil end
    return { id = door.id, name = door.name, locked = door.locked }
end)
