Config = {}

Config.Locale = 'en'          -- en | it | de | fr | es | pt
Config.Debug = false

Config.Bridge = {
    framework = 'auto',        -- auto | esx | qb | qbx | standalone
    inventory = 'auto',        -- auto | ox_inventory | qs-inventory | qb-inventory | esx | none
    target = 'builtin',        -- auto | ox_target | builtin
    notify = 'g_doorlock',         -- auto | g_doorlock | ox_lib | esx | qb | qbx | okokNotify | mythic_notify | brutal_notify | wasabi_notify | custom
    textUI = 'g_doorlock',      -- auto | g_doorlock | ox_lib | esx | qb | okokTextUI | cd_drawtextui | jg-textui | custom | false
    notifyPosition = 'top-right', -- top | top-right | bottom-right (built-in and ox_lib)
    textUIPosition = 'bottom', -- bottom | left | right (built-in and ox_lib); qb / okokTextUI use left or right
    progress = 'ox_lib',       -- auto | ox_lib (circle) | ox_lib_bar | qb (progressbar) | esx (esx_progressbar)
    menu = 'ox_lib',           -- auto | ox_lib | qb (qb-menu) | esx (esx_context)
    logs = 'discord',          -- console | discord | ox_lib | none; webhook stays in config_server.lua
}

Config.NUI = {
    watermark = true,                 -- show the server logo; the name stays visible when false
    serverName = 'Gravity Studios',    -- empty string hides the server name
    logo = 'img/logo.png',             -- local path relative to web/; empty string hides the logo
    theme = {
        colors = {
            background = '#080918', backgroundSecondary = '#0a0b1c',
            surface = '#0d0e21', surfaceSecondary = '#15112b', input = '#0d0e21',
            border = '#251d3e', borderStrong = '#42305f',
            text = '#eeebf7', muted = '#a3a5b4', faint = '#999caf',
            primary = '#7629e8', accent = '#843af0', highlight = '#ce9bf5', primaryText = '#ffffff',
            info = '#67d9ed', success = '#62d2e8', warning = '#fcd34d',
            danger = '#ff6975', dangerStrong = '#ef4444',
        },
        fonts = { body = 'Barlow Condensed', headings = 'Bebas Neue' },
    },
}

-- Existing custom hooks are kept for compatibility; select them in Config.Bridge.
Config.TextUI = {
    show = function(text, locked)
        lib.showTextUI(text)
    end,
    hide = function()
        lib.hideTextUI()
    end,
}

Config.Notify = {
    custom = function(text, kind, title, duration)
        lib.notify({ title = title, description = text, type = kind == 'info' and 'inform' or kind, duration = duration })
    end,
}

-- keys can be rebound by players in GTA settings > Key Bindings > FiveM
Config.Interaction = {
    key = 'E',
    actionKey = 'G',          -- lockpick / breach without ox_target
    targetIcon = 'fa-solid fa-door-closed',
    pinIcon = 'fa-solid fa-hashtag',
    lockpickIcon = 'fa-solid fa-unlock-keyhole',
    breachIcon = 'fa-solid fa-hammer',
    repairIcon = 'fa-solid fa-screwdriver-wrench',
    hackIcon = 'fa-solid fa-laptop-code',
    bellIcon = 'fa-solid fa-bell',
}

Config.Admin = {
    command = 'dooradmin',
    quickCommand = 'doorlock',             -- lock/unlock the nearest door
    ace = 'g_doorlock.admin',
    bypassAce = 'g_doorlock.bypass', -- counts as the "admin" criterion
    undoSeconds = 300,                     -- deleted doors can be restored for this long
}

Config.Doors = {
    scheduleCheck = 30,       -- seconds, opening hours use server time
    defaults = {              -- new doors created in the editor
        locked = true,
        persist = true,
        autoLock = 0,
        accessMode = 'any',
    },
    distances = {
        defaultInteract = 2.0,
        defaultAuto = 0.0,    -- 0 = auto gate off
        maxInteract = 15.0,
        maxAuto = 40.0,
        nearbyRadius = 40.0,
        serverTolerance = 1.5,
    },
    autoGate = {
        requireVehicle = false,
        relockAfter = 10,     -- when the gate has no autoLock
        cooldown = 4000,
    },
}

Config.Access = {
    requireOnDuty = false,    -- qb / qbx only
    pin = {
        minLength = 4,
        maxLength = 8,
        maxAttempts = 3,
        window = 60,
        lockout = 120,
    },
    keys = {
        metadataField = 'doorkey', -- item.metadata[field] must match the door
        expiresField = 'expires',  -- unix time, optional
    },
}

-- relockAfter: seconds, 0 = stays open
-- minTime: ms, faster results are refused by the server
-- minigame: runs on the client, return true on success
Config.Lockpick = {
    item = 'lockpick',
    removeChance = 35,        -- % to lose the item on fail
    relockAfter = 30,
    minTime = 1500,
    difficulty = {
        easy = { 'easy', 'easy' },
        medium = { 'easy', 'medium', 'medium' },
        hard = { 'medium', 'hard', 'hard' },
    },
    minigame = function(checks, difficulty)
        return lib.skillCheck(checks)
    end,
}

Config.Hack = {
    item = 'hacking_device',
    removeChance = 20,
    relockAfter = 30,
    minTime = 2500,
    checks = { 'medium', 'medium', 'hard', 'hard' },
    keys = { 'w', 'a', 's', 'd' },
    minigame = function(checks, keys)
        return lib.skillCheck(checks, keys)
    end,
}

-- jobs: { job = min grade }, {} = anyone
Config.Breach = {
    jobs = { police = 0, sheriff = 0 },
    item = nil,               -- e.g. 'breaching_ram'
    removeItem = false,
    duration = 6000,          -- ms, the minigame must last at least this
    relockAfter = 120,
    minigame = function(duration)
        return ClientBridge.progress({
            duration = duration,
            label = L('breach_progress'),
            position = 'bottom',
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { scenario = 'WORLD_HUMAN_HAMMERING' },
        })
    end,
    damage = {                -- breached doors stay open until repaired
        enabled = true,
        repairJobs = { police = 0, mechanic = 0 },
        repairItem = nil,     -- e.g. 'toolkit'
        removeRepairItem = false,
        repairTime = 8000,
    },
}

Config.Alarm = {
    duration = 30,
    range = 40.0,
    blipTime = 90,
    onLockpickFail = true,
    notifyJobs = { police = 0, sheriff = 0 },
}

Config.Extras = {
    bell = {
        range = 60.0,
        cooldown = 15,
    },
    remote = {
        item = 'garage_remote', -- nil = no item
        range = 30.0,
        key = nil,              -- nil = use the item from the inventory instead
    },
}

-- per player: max requests inside window (ms)
Config.RateLimit = {
    toggle = { max = 6, window = 4000 },
    auto = { max = 4, window = 4000 },
    admin = { max = 30, window = 10000 },
    breakin = { max = 4, window = 5000 },
    bell = { max = 2, window = 5000 },
    remote = { max = 4, window = 4000 },
}

-- type: synth (no files) | file (web/sounds/ + fxmanifest files) | native (GTA name + set)
Config.Sounds = {
    enabled = true,
    range = 10.0,
    volume = 0.35,
    lock = 'bolt',
    unlock = 'unlock',
    denied = 'denied',
    library = {
        bolt = { label = 'Bolt', type = 'synth', preset = 'bolt' },
        unlock = { label = 'Unlock click', type = 'synth', preset = 'unlock' },
        beep = { label = 'Beep', type = 'synth', preset = 'beep' },
        chime = { label = 'Chime', type = 'synth', preset = 'chime' },
        keycard = { label = 'Keycard reader', type = 'synth', preset = 'keycard' },
        heavy = { label = 'Heavy door', type = 'synth', preset = 'heavy' },
        gate = { label = 'Gate motor', type = 'synth', preset = 'gate' },
        denied = { label = 'Denied buzz', type = 'synth', preset = 'denied' },
        knock = { label = 'Knock', type = 'synth', preset = 'knock' },
        -- garage = { label = 'Garage (file)', type = 'file', file = 'garage.ogg' },
        -- select = { label = 'GTA select', type = 'native', name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    },
}
