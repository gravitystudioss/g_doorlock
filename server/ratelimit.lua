RateLimit = { buckets = {} }

function RateLimit.check(src, action)
    local cfg = Config.RateLimit[action]
    if not cfg then return true end
    local now = GetGameTimer()
    local perPlayer = RateLimit.buckets[src]
    if not perPlayer then
        perPlayer = {}
        RateLimit.buckets[src] = perPlayer
    end
    local list = perPlayer[action]
    if not list then
        list = {}
        perPlayer[action] = list
    end
    local cutoff = now - cfg.window
    local kept = {}
    for i = 1, #list do
        if list[i] > cutoff then kept[#kept + 1] = list[i] end
    end
    if #kept >= cfg.max then
        perPlayer[action] = kept
        return false
    end
    kept[#kept + 1] = now
    perPlayer[action] = kept
    return true
end

function RateLimit.clear(src)
    RateLimit.buckets[src] = nil
end
