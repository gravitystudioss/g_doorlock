Nui = { focus = nil }

function Nui.send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function Nui.setFocus(name)
    Nui.focus = name
    SetNuiFocus(name ~= nil, name ~= nil)
end

-- list for the editor dropdowns
local function soundChoices()
    local list = {}
    for key, s in pairs(Config.Sounds.library) do
        list[#list + 1] = { key = key, label = s.label or key }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function Nui.init()
    Nui.send('init', {
        locale = GetLocaleTable(),
        pinMin = Config.Access.pin.minLength,
        pinMax = Config.Access.pin.maxLength,
        indicator = Config.TextUI.system ~= false,
        sounds = soundChoices(),
        defaults = {
            locked = Config.Doors.defaults.locked,
            persist = Config.Doors.defaults.persist,
            autoLock = Config.Doors.defaults.autoLock,
            mode = Config.Doors.defaults.accessMode,
            interact = Config.Doors.distances.defaultInteract,
            auto = Config.Doors.distances.defaultAuto,
        },
    })
end

function Nui.toast(kind, text)
    Nui.send('toast', { type = kind, text = text })
end

function Nui.playSoundKey(key, coords)
    if not Config.Sounds.enabled or not key or key == 'none' then return end
    local cfg = Config.Sounds.library[key]
    if not cfg then return end

    local volume = Config.Sounds.volume
    if coords then
        local dist = #(GetEntityCoords(PlayerPedId()) - coords)
        if dist > Config.Sounds.range then return end
        volume = volume * (1.0 - (dist / Config.Sounds.range) * 0.7)
    end

    if cfg.type == 'native' then
        if coords then
            PlaySoundFromCoord(-1, cfg.name, coords.x, coords.y, coords.z, cfg.set, false, Config.Sounds.range, false)
        else
            PlaySoundFrontend(-1, cfg.name, cfg.set, true)
        end
    else
        Nui.send('sound', { type = cfg.type, preset = cfg.preset, file = cfg.file, volume = volume })
    end
end

-- kind = 'lock' | 'unlock' | 'denied'. the door can override lock/unlock
function Nui.playSound(kind, coords, door)
    local key = Config.Sounds[kind]
    if door and door.sounds and door.sounds[kind] then
        key = door.sounds[kind]
    end
    Nui.playSoundKey(key, coords)
end

RegisterNUICallback('editor:testSound', function(data, cb)
    cb(true)
    local key = data.key
    if key == 'default' then key = Config.Sounds[data.kind] end
    Nui.playSoundKey(key, nil)
end)

RegisterNUICallback('close', function(data, cb)
    if Nui.focus == 'keypad' then
        Interact.closeKeypad()
    elseif Nui.focus == 'editor' then
        Editor.close()
    end
    Nui.setFocus(nil)
    cb(true)
end)
