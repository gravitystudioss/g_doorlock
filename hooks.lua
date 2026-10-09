Hooks = {}

function Hooks.canInteract(src, door, action)
    -- Example: block a vault while a robbery cooldown is active
    -- if door.group == 'pacific_vault' and GlobalState.pacificCooldown then return false, 'Vault sealed' end
    return true
end

function Hooks.onStateChanged(door, locked, src, reason)
    -- Example: alarm when a bank door is opened by a non-employee via export
    -- if door.group == 'fleeca' and not locked and reason == 'export' then
    --     TriggerEvent('my_alarm:trigger', door.id)
    -- end
end

function Hooks.onAccessDenied(src, door, reason)
end

function Hooks.onPinFailed(src, door, attempts, lockedOut)
end

-- lockpick attempt finished. success = true when the door was opened
function Hooks.onLockpick(src, door, success)
    -- Example: alert the police
    -- if success then TriggerEvent('my_dispatch:alert', 'Break-in', door.id) end
end

-- a door was breached (police / swat)
function Hooks.onBreach(src, door)
end

function Hooks.onDoorSaved(door, src, isNew)
end

function Hooks.onDoorDeleted(doorId, src)
end
