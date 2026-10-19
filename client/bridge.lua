ClientBridge = {}

local resources = {
    target = { builtin = '', ox_target = 'ox_target' },
    notify = {
        g_doorlock = '', ox_lib = 'ox_lib', custom = '', esx = 'es_extended',
        qb = { 'qb-core', 'qbx_core' }, qbx = 'qbx_core', okokNotify = 'okokNotify',
        mythic_notify = 'mythic_notify', brutal_notify = 'brutal_notify', wasabi_notify = 'wasabi_notify',
    },
    textUI = {
        g_doorlock = '', ox_lib = 'ox_lib', custom = '', esx = 'esx_textui', qb = 'qb-core',
        okokTextUI = 'okokTextUI', cd_drawtextui = 'cd_drawtextui', ['jg-textui'] = 'jg-textui',
    },
    progress = { ox_lib = 'ox_lib', ox_lib_bar = 'ox_lib', qb = 'progressbar', esx = 'esx_progressbar' },
    menu = { ox_lib = 'ox_lib', qb = 'qb-menu', esx = 'esx_context' },
}
local fallbacks = { target = 'builtin', notify = 'g_doorlock', textUI = 'g_doorlock', progress = 'ox_lib', menu = 'ox_lib' }
local warnings = {}

function ClientBridge.warn(service, message)
    local key = service .. ':' .. message
    if warnings[key] then return end
    warnings[key] = true
    print(('^3[g_doorlock] %s: %s^0'):format(service, message))
end

function ClientBridge.provider(service)
    local wanted = Config.Bridge[service]
    if service == 'textUI' and wanted == false then return false end
    if wanted == 'auto' then
        if service == 'target' then
            return GetResourceState('ox_target') == 'started' and 'ox_target' or 'builtin'
        end
        wanted = 'ox_lib'
    end
    local resource = resources[service][wanted]
    if resource == '' then return wanted end
    if type(resource) == 'string' and GetResourceState(resource) == 'started' then return wanted end
    if type(resource) == 'table' then
        for _, name in ipairs(resource) do
            if GetResourceState(name) == 'started' then return wanted end
        end
    end
    ClientBridge.warn(service, ('provider "%s" unavailable; using %s'):format(tostring(wanted), fallbacks[service]))
    return fallbacks[service]
end

local activeProgress
local activeMenu

function ClientBridge.cancelProgress()
    local active = activeProgress
    if not active then return end
    if active.provider == 'qb' then
        TriggerEvent('progressbar:client:cancel')
    elseif active.provider == 'esx' then
        pcall(function() exports.esx_progressbar:CancelProgressbar() end)
        FreezeEntityPosition(PlayerPedId(), false)
    elseif lib.progressActive() then
        lib.cancelProgress()
    end
    if active.finish then active.finish(false) end
    if active.provider == 'esx' or active.provider == 'qb' then ClearPedTasks(PlayerPedId()) end
end

function ClientBridge.progress(options)
    if activeProgress then return false end
    local provider = ClientBridge.provider('progress')
    local active = { provider = provider }
    activeProgress = active
    local ok, result = pcall(function()
        if provider == 'ox_lib' then return lib.progressCircle(options) end
        if provider == 'ox_lib_bar' then return lib.progressBar(options) end

        local pending = promise.new()
        local settled = false
        active.finish = function(done)
            if settled then return end
            settled = true
            pending:resolve(done == true)
        end
        local animation = options.anim or {}
        if provider == 'qb' then
            exports.progressbar:Progress({
                name = 'g_doorlock', duration = options.duration, label = options.label,
                useWhileDead = false, canCancel = options.canCancel ~= false,
                controlDisables = { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
                animation = animation.scenario and { task = animation.scenario }
                    or (animation.dict and { animDict = animation.dict, anim = animation.clip, flags = animation.flag or 1 }) or nil,
            }, function(cancelled) active.finish(not cancelled) end)
        else
            local started = exports.esx_progressbar:Progressbar(options.label, options.duration, {
                FreezePlayer = true,
                animation = animation.scenario and { type = 'Scenario', Scenario = animation.scenario }
                    or (animation.dict and { type = 'anim', dict = animation.dict, lib = animation.clip }) or nil,
                onFinish = function() active.finish(true) end,
                onCancel = function() active.finish(false) end,
            })
            if started == false then active.finish(false) end
        end
        -- Providers that stop or fail to call back must not leave break-in actions busy forever.
        SetTimeout(options.duration + 3000, function()
            if activeProgress == active and not settled then ClientBridge.cancelProgress() end
        end)
        return Citizen.Await(pending)
    end)
    if not ok then
        ClientBridge.cancelProgress()
        activeProgress = nil
        ClientBridge.warn('progress', tostring(result))
        return false
    end
    activeProgress = nil
    return result == true
end

local function closeMenu()
    local provider = activeMenu
    activeMenu = nil
    if provider == 'qb' then
        pcall(function() exports['qb-menu']:closeMenu() end)
    elseif provider == 'esx' then
        pcall(function() exports.esx_context:Close() end)
    elseif provider == 'ox_lib' then
        lib.hideContext()
    end
end

function ClientBridge.menu(id, title, options)
    closeMenu()
    local provider = ClientBridge.provider('menu')
    local ok, err = pcall(function()
        if provider == 'qb' then
            local items = { { header = title, isMenuHeader = true } }
            for _, option in ipairs(options) do
                items[#items + 1] = {
                    header = option.title, txt = option.description, icon = option.icon, disabled = option.disabled,
                    params = option.onSelect and { isAction = true, event = option.onSelect } or nil,
                }
            end
            exports['qb-menu']:openMenu(items)
        elseif provider == 'esx' then
            local elements = { { title = title, unselectable = true } }
            for index, option in ipairs(options) do
                elements[#elements + 1] = {
                    title = option.title, description = option.description, icon = option.icon,
                    unselectable = option.disabled, value = index,
                }
            end
            exports.esx_context:Open('right', elements, function(_, element)
                closeMenu()
                local option = options[element.value]
                if option and not option.disabled and option.onSelect then option.onSelect() end
            end)
        else
            lib.registerContext({ id = id, title = title, options = options })
            lib.showContext(id)
        end
    end)
    if ok then
        activeMenu = provider
    else
        ClientBridge.warn('menu', tostring(err) .. '; using ox_lib')
        lib.registerContext({ id = id, title = title, options = options })
        lib.showContext(id)
        activeMenu = 'ox_lib'
    end
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        ClientBridge.cancelProgress()
        closeMenu()
    elseif activeProgress and resources.progress[activeProgress.provider] == resource then
        if activeProgress.provider == 'esx' then FreezeEntityPosition(PlayerPedId(), false) end
        if activeProgress.finish then activeProgress.finish(false) end
    end
    if activeMenu and resources.menu[activeMenu] == resource then activeMenu = nil end
end)
