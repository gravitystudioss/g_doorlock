ServerConfig = {}

-- Allow framework admin groups to use the editor alongside ACE permissions.
ServerConfig.UseFrameworkAdmin = true

-- Framework groups considered administrators (editor access + "admin" door criterion).
ServerConfig.AdminGroups = {
    esx = { 'admin', 'superadmin' },
    qb = { 'admin', 'god' },   -- checked with IsPlayerAceAllowed(src, group) like QBCore does
    qbx = { 'admin', 'god' },
}

ServerConfig.Logs = {
    -- Discord webhook: preferably set it in server.cfg:
    --   set g_doorlock_webhook "https://discord.com/api/webhooks/..."
    discordWebhook = GetConvar('g_doorlock_webhook', ''),
    -- Which actions are sent to Discord. State changes by players can be noisy.
    discordActions = {
        create = true, update = true, delete = true, import = true,
        pin_lockout = true, admin_state = true, state = false,
        lockpick = true, breach = true, group = true,
        alarm = true, repair = true, temp_pin = true,
        hack = true, bulk = true, restore = true,
    },
}

-- Check GitHub for updates once on startup.
-- Report new versions in the console.
ServerConfig.UpdateCheck = {
    enabled = true,
    repo = 'gravitystudioss/g_doorlock',
}
