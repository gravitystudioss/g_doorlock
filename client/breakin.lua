Breakin = { busy = false }

local errors = {
    no_lockpick = 'no_lockpick',
    no_item = 'breach_no_item',
    no_access = 'breach_no_job',
    already_open = 'already_open',
    distance = 'too_far',
    rate = 'slow_down',
    lockpick_failed = 'lockpick_failed',
    repair_no_job = 'repair_no_job',
    repair_no_item = 'repair_no_item',
    not_broken = 'not_broken',
    no_hack_item = 'no_hack_item',
    hack_failed = 'hack_failed',
}

local function showError(reason)
    Notify(L(errors[reason] or 'access_denied'), 'error')
    Nui.playSound('denied', nil)
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

function Breakin.lockpick(door)
    if Breakin.busy or not door then return end
    Breakin.busy = true

    local res = lib.callback.await('g_doorlock:breakin:start', false, door.id, 'lockpick')
    if not res or not res.ok then
        Breakin.busy = false
        showError(res and res.reason)
        return
    end

    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, door.center.x, door.center.y, door.center.z, 800)
    Wait(800)
    if loadDict('mp_arresting') then
        TaskPlayAnim(ped, 'mp_arresting', 'a_uncuff', 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end

    local success = Config.Lockpick.minigame(res.checks, door.lockpick and door.lockpick.difficulty)
    ClearPedTasks(ped)
    RemoveAnimDict('mp_arresting')

    local fin = lib.callback.await('g_doorlock:lockpick:finish', false, res.token, success == true)
    Breakin.busy = false

    if fin and fin.ok then
        Notify(L('lockpick_success'), 'success')
    else
        showError(fin and fin.reason or 'lockpick_failed')
    end
end

function Breakin.hack(door)
    if Breakin.busy or not door then return end
    Breakin.busy = true

    local res = lib.callback.await('g_doorlock:breakin:start', false, door.id, 'hack')
    if not res or not res.ok then
        Breakin.busy = false
        showError(res and res.reason)
        return
    end

    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, door.center.x, door.center.y, door.center.z, 800)
    Wait(800)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)

    local success = Config.Hack.minigame(res.checks, res.keys)
    ClearPedTasks(ped)

    local fin = lib.callback.await('g_doorlock:hack:finish', false, res.token, success == true)
    Breakin.busy = false
    if fin and fin.ok then
        Notify(L('hack_success'), 'success')
    else
        showError(fin and fin.reason or 'hack_failed')
    end
end

function Breakin.knock(door)
    if not door then return end
    local res = lib.callback.await('g_doorlock:bell', false, door.id)
    if res and res.ok then
        local ped = PlayerPedId()
        TaskTurnPedToFaceCoord(ped, door.center.x, door.center.y, door.center.z, 600)
        Wait(600)
        if loadDict('timetable@jimmy@doorknock@') then
            TaskPlayAnim(ped, 'timetable@jimmy@doorknock@', 'knockdoor_idle', 8.0, -8.0, 3000, 48, 0.0, false, false, false)
            RemoveAnimDict('timetable@jimmy@doorknock@')
        end
        Notify(L('knock_sent'), 'info')
    elseif res and res.reason == 'rate' then
        Notify(L('slow_down'), 'error')
    end
end

function Breakin.breach(door)
    if Breakin.busy or not door then return end
    Breakin.busy = true

    local res = lib.callback.await('g_doorlock:breakin:start', false, door.id, 'breach')
    if not res or not res.ok then
        Breakin.busy = false
        showError(res and res.reason)
        return
    end

    local done = Config.Breach.minigame(res.duration)
    ClearPedTasks(PlayerPedId())

    if not done then
        Breakin.busy = false
        return
    end

    local fin = lib.callback.await('g_doorlock:breach:finish', false, res.token)
    Breakin.busy = false
    if fin and fin.ok then
        Notify(L('breach_success'), 'success')
    else
        showError(fin and fin.reason or 'access_denied')
    end
end

function Breakin.repair(door)
    if Breakin.busy or not door then return end
    Breakin.busy = true

    local res = lib.callback.await('g_doorlock:breakin:start', false, door.id, 'repair')
    if not res or not res.ok then
        Breakin.busy = false
        showError(res and res.reason)
        return
    end

    local done = lib.progressCircle({
        duration = res.duration,
        label = L('repair_progress'),
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { scenario = 'WORLD_HUMAN_WELDING' },
    })
    ClearPedTasks(PlayerPedId())

    if not done then
        Breakin.busy = false
        return
    end

    local fin = lib.callback.await('g_doorlock:repair:finish', false, res.token)
    Breakin.busy = false
    if fin and fin.ok then
        Notify(L('repair_success'), 'success')
    else
        showError(fin and fin.reason or 'access_denied')
    end
end

-- action key (no ox_target): one option runs directly, more open a small menu
function Breakin.options(door)
    local options = {}
    if not door then return options end
    if door.broken then
        options[#options + 1] = { title = L('target_repair'), icon = Config.Interaction.repairIcon, onSelect = function() Breakin.repair(door) end }
    end
    -- players with access just open the door
    local hasAccess = Interact.access[door.id]
    if door.locked and door.canLockpick and not hasAccess then
        options[#options + 1] = { title = L('target_lockpick'), icon = Config.Interaction.lockpickIcon, onSelect = function() Breakin.lockpick(door) end }
    end
    if door.locked and door.canHack and not hasAccess then
        options[#options + 1] = { title = L('target_hack'), icon = Config.Interaction.hackIcon, onSelect = function() Breakin.hack(door) end }
    end
    if door.locked and door.bell and not hasAccess then
        options[#options + 1] = { title = L('target_knock'), icon = Config.Interaction.bellIcon, onSelect = function() Breakin.knock(door) end }
    end
    if door.locked and door.canBreach and not hasAccess then
        options[#options + 1] = { title = L('target_breach'), icon = Config.Interaction.breachIcon, onSelect = function() Breakin.breach(door) end }
    end
    return options
end

-- what the action key does on this door, nil when nothing
function Breakin.actionLabel(door)
    local options = Breakin.options(door)
    if #options == 0 then return nil end
    return #options == 1 and options[1].title or L('ed_breakin')
end

function Breakin.openMenu(door)
    local options = Breakin.options(door)
    if #options == 0 then return end
    if #options == 1 then
        options[1].onSelect()
        return
    end

    lib.registerContext({ id = 'g_doorlock_breakin', title = L('ed_breakin'), options = options })
    lib.showContext('g_doorlock_breakin')
end
