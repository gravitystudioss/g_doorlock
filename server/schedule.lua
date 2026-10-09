-- opening hours. the door is changed only when the schedule switches (open -> closed or back),
-- so a manual lock/unlock stays until the next switch

Schedule = { last = {} } -- id -> last wanted state (true = open)

local function minutes(hhmm)
    local h, m = hhmm:match('^(%d+):(%d+)$')
    return tonumber(h) * 60 + tonumber(m)
end

-- now = os.date('*t')
function Schedule.isOpen(schedule, now)
    if #schedule.days > 0 then
        local today = false
        for _, d in ipairs(schedule.days) do
            if d == now.wday then today = true end
        end
        if not today then return false end
    end

    local cur = now.hour * 60 + now.min
    local open, close = minutes(schedule.open), minutes(schedule.close)
    if open < close then
        return cur >= open and cur < close
    end
    -- overnight, e.g. 22:00 - 04:00
    return cur >= open or cur < close
end

function Schedule.tick()
    local now = os.date('*t')
    for id, door in pairs(Doors.list) do
        if door.schedule then
            local open = Schedule.isOpen(door.schedule, now)
            if Schedule.last[id] ~= open then
                Schedule.last[id] = open
                if Doors.state[id].locked == open then
                    Doors.setState(id, not open, nil, 'schedule', { autoLock = 0 })
                end
            end
        else
            Schedule.last[id] = nil
        end
    end
end

CreateThread(function()
    while not Doors.ready do Wait(500) end
    while true do
        Schedule.tick()
        Wait(Config.Doors.scheduleCheck * 1000)
    end
end)
