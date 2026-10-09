# g_doorlock

![g_doorlock](g_doorlock.png)

A free FiveM doorlock resource by Gravity Studios. Supports single and double doors, gates and garage doors, with an in-game editor, server-side access checks and synchronized lock states.

## Features

- In-game editor (`/dooradmin`): create, edit, group, import and export doors
- Access by job, gang, identifier, item (with metadata) or PIN
- Lockpicking, hacking and breaching with configurable minigames, alarms and door repair
- Doorbell, garage remote, opening hours, automatic gates
- Import from ox_doorlock and qb-doorlock; included door packs
- Configurable notifications and text UI
- ESX, QBCore, QBX or standalone · ox_inventory, qs-inventory, qb-inventory or ESX inventory
- 6 languages: en, it, de, fr, es, pt

## Showcase

![Door admin editor](dooradmin.png)

![Door admin interface](dooradmin2.png)

![Door admin showcase](dooradmin3.png)

![Door groups](groups.png)

![PIN access](pin.png)

## Requirements

- OneSync
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- Optional: ox_target. Keyboard controls: `E` to interact, `G` for break-in actions.

## Installation

1. Put `g_doorlock` in your resources (keep the folder name).
2. Import `sql/install.sql` (tables are also created on start).
3. Add to `server.cfg` after your framework and inventory:

```cfg
ensure g_doorlock

add_ace group.admin g_doorlock.admin allow    # editor
add_ace group.admin g_doorlock.bypass allow   # "Administrators" criterion on doors
set g_doorlock_webhook "https://discord.com/api/webhooks/..."   # optional
```

4. Add the items you use to your inventory (see below).

## Items

Add the missing entries to your inventory's item table. `keycard` is optional and can be configured as a door key in the editor.

### ox_inventory

Add to `ox_inventory/data/items.lua` ([item format](https://overextended.dev/docs/ox_inventory/Guides/creatingItems)).

```lua
['lockpick'] = {
    label = 'Lockpick', weight = 100, stack = true, close = true,
    description = 'A tool for picking door locks.',
},
['hacking_device'] = {
    label = 'Hacking Device', weight = 1000, stack = false, close = true,
    description = 'A device for bypassing electronic door locks.',
},
['garage_remote'] = {
    label = 'Garage Remote', weight = 50, stack = false, close = true, consume = 0,
    description = 'A remote control for gates and garage doors.',
    client = { export = 'g_doorlock.useRemote' },
},
['keycard'] = {
    label = 'Keycard', weight = 10, stack = false, close = true,
    description = 'An access card for a door or group of doors.',
},
```

### qs-inventory

Add to `qs-inventory/shared/items.lua` for ESX or `qb-core/shared/items.lua` for QBCore ([item locations](https://www.quasar-store.com/docs/advanced-inventory/installation#item-management)). Use matching item images in `qs-inventory/html/images/`.

```lua
['lockpick'] = {
    name = 'lockpick', label = 'Lockpick', weight = 100, type = 'item', image = 'lockpick.png',
    unique = false, useable = false, shouldClose = true,
    description = 'A tool for picking door locks.',
},
['hacking_device'] = {
    name = 'hacking_device', label = 'Hacking Device', weight = 1000, type = 'item', image = 'hacking_device.png',
    unique = true, useable = false, shouldClose = true,
    description = 'A device for bypassing electronic door locks.',
},
['garage_remote'] = {
    name = 'garage_remote', label = 'Garage Remote', weight = 50, type = 'item', image = 'garage_remote.png',
    unique = true, useable = true, shouldClose = true,
    description = 'A remote control for gates and garage doors.',
    client = { export = 'g_doorlock.useRemote' },
},
['keycard'] = {
    name = 'keycard', label = 'Keycard', weight = 10, type = 'item', image = 'keycard.png',
    unique = true, useable = false, shouldClose = true,
    description = 'An access card for a door or group of doors.',
},
```

## Exports

```lua
local dl = exports.g_doorlock

dl:lockDoor('mrpd_front')
dl:unlockDoor('vault', 60)            -- relock after 60 s
dl:setGroupState('mrpd', true)
dl:isLocked('mrpd_front')
dl:canAccess(source, 'mrpd_armory')
dl:setTempAccess('house_12', { identifiers = { 'ABC123' } }, 3600)
dl:addTempPin('motel_12', '4821', 86400)
```

Server event: `g_doorlock:stateChanged (id, locked, src, reason)`. More hooks in `hooks.lua`.

## License

[GPL-3.0](LICENSE)
