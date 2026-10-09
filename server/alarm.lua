-- door alarm: sound at the door for everyone near, notification + blip for the jobs in Config.Alarm

Alarm = {}

local function shouldNotify(src)
    local jobs = Config.Alarm.notifyJobs
    if next(jobs) == nil then return false end
    local job = Bridge.getJob(src)
    if not job then return false end
    local minGrade = jobs[job.name]
    return minGrade ~= nil and job.grade >= minGrade
end

-- kind = 'lockpick' | 'breach' | 'export'
function Alarm.trigger(door, kind)
    if not door.alarm then return end
    local c = Doors.center(door.id)

    TriggerClientEvent('g_doorlock:alarm', -1, door.id, c, door.bucket)

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if GetPlayerRoutingBucket(src) == door.bucket and shouldNotify(src) then
            TriggerClientEvent('g_doorlock:alarmNotify', src, { name = door.name, coords = c, kind = kind })
        end
    end

    Logs.add('alarm', nil, door.id, kind)
end
