-- kind = 'success' | 'error' | 'info'
function Notify(text, kind, title, duration)
    kind = kind or 'info'
    duration = duration or 5000
    local system = ClientBridge.provider('notify')

    local ok, err = pcall(function()
        if system == 'custom' then
            Config.Notify.custom(text, kind, title, duration)
        elseif system == 'esx' then
            TriggerEvent('esx:showNotification', text, kind, duration)
        elseif system == 'qb' then
            TriggerEvent('QBCore:Notify', text, kind == 'info' and 'primary' or kind, duration)
        elseif system == 'qbx' then
            exports.qbx_core:Notify(text, kind == 'info' and 'inform' or kind, duration)
        elseif system == 'okokNotify' then
            exports.okokNotify:Alert(title or '', text, duration, kind)
        elseif system == 'mythic_notify' then
            exports.mythic_notify:DoHudText(kind == 'info' and 'inform' or kind, text)
        elseif system == 'brutal_notify' then
            exports.brutal_notify:SendAlert(title or '', text, duration, kind)
        elseif system == 'wasabi_notify' then
            exports.wasabi_notify:notify(title or '', text, duration, kind)
        elseif system == 'ox_lib' then
            lib.notify({ title = title, description = text, type = kind == 'info' and 'inform' or kind, duration = duration, position = Config.Bridge.notifyPosition })
        else
            TriggerEvent('esx:showNotification', text, kind, duration)
        end
    end)
    if not ok then
        ClientBridge.warn('notify', tostring(err))
        TriggerEvent('esx:showNotification', text, kind, duration)
    end
end

RegisterNetEvent('g_doorlock:notify', Notify)

-- text shown near a door. returns false when the built-in indicator has to be used
TextUI = {}
local activeSystem
local textPositions = { bottom = 'bottom-center', left = 'left-center', right = 'right-center' }

function TextUI.show(text, locked)
    local system = ClientBridge.provider('textUI')
    if activeSystem and activeSystem ~= system then TextUI.hide() end
    if system == false or system == 'g_doorlock' then return false end
    local position = Config.Bridge.textUIPosition

    local ok, err = pcall(function()
        if system == 'custom' then
            Config.TextUI.show(text, locked)
        elseif system == 'ox_lib' then
            lib.showTextUI(text, { icon = locked and 'lock' or 'lock-open', position = textPositions[position] })
        elseif system == 'esx' then
            exports.esx_textui:TextUI(text, locked and 'error' or 'success')
        elseif system == 'qb' then
            exports['qb-core']:DrawText(text, position == 'right' and 'right' or 'left')
        elseif system == 'okokTextUI' then
            exports.okokTextUI:Open(text, locked and 'red' or 'green', position == 'right' and 'right' or 'left')
        elseif system == 'cd_drawtextui' then
            TriggerEvent('cd_drawtextui:ShowUI', 'show', text)
        elseif system == 'jg-textui' then
            exports['jg-textui']:DrawText(text)
        end
    end)
    if not ok then
        ClientBridge.warn('textUI', tostring(err) .. '; using g_doorlock')
        TextUI.hide()
        return false
    end
    activeSystem = system
    Nui.send('indicator', { show = false })
    return true
end

function TextUI.hide()
    local system = activeSystem
    activeSystem = nil
    Nui.send('indicator', { show = false })

    local ok, err = pcall(function()
        if system == 'custom' then
            Config.TextUI.hide()
        elseif system == 'ox_lib' then
            lib.hideTextUI()
        elseif system == 'esx' then
            exports.esx_textui:HideUI()
        elseif system == 'qb' then
            exports['qb-core']:HideText()
        elseif system == 'okokTextUI' then
            exports.okokTextUI:Close()
        elseif system == 'cd_drawtextui' then
            TriggerEvent('cd_drawtextui:HideUI')
        elseif system == 'jg-textui' then
            exports['jg-textui']:HideText()
        end
    end)
    if not ok then ClientBridge.warn('textUI', tostring(err)) end
end
