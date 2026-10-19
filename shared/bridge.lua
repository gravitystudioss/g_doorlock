-- Old configurations remain usable when a Config.Bridge field is omitted.
Config.Bridge = Config.Bridge or {}
Config.Notify = Config.Notify or {}
Config.TextUI = Config.TextUI or {}

local bridge = Config.Bridge
local defaults = {
    framework = Config.Framework or 'auto',
    inventory = Config.Inventory or 'auto',
    notify = Config.Notify.system or 'ox_lib',
    notifyPosition = 'top-right',
    textUIPosition = 'bottom',
    progress = 'ox_lib',
    menu = 'ox_lib',
    logs = 'discord',
}
defaults.textUI = Config.TextUI.system
if defaults.textUI == nil then defaults.textUI = 'g_doorlock' end
defaults.target = Config.Interaction.target
if defaults.target == nil then defaults.target = 'builtin' end

for key, value in pairs(defaults) do
    if bridge[key] == nil then bridge[key] = value end
end
if bridge.target == true or bridge.target == 'true' then bridge.target = 'ox_target' end
if bridge.target == false or bridge.target == 'false' then bridge.target = 'builtin' end

local notifyPositions = { top = true, ['top-right'] = true, ['bottom-right'] = true }
local textPositions = { bottom = true, left = true, right = true }
if not notifyPositions[bridge.notifyPosition] then bridge.notifyPosition = 'top-right' end
if not textPositions[bridge.textUIPosition] then bridge.textUIPosition = 'bottom' end

-- Preserve the legacy fields read by custom integrations and minigames.
Config.Framework = bridge.framework
Config.Inventory = bridge.inventory
Config.Notify.system = bridge.notify
Config.TextUI.system = bridge.textUI
Config.Interaction.target = bridge.target == 'ox_target' or (bridge.target == 'auto' and 'auto' or false)
