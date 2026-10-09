# g_doorlock

Free doorlock for FiveM by Gravity Studios. Single doors, double doors, gates and garages with an in-game editor, server-side permissions and synced state.

## Features

- In-game editor (`/dooradmin`): create, edit, group, import and export doors
- Access by job, gang, identifier, item (with metadata) or PIN
- Lockpick, hack and breach with configurable minigames, alarm, broken doors and repair
- Doorbell, garage remote, opening hours, automatic gates
- Import from ox_doorlock and qb-doorlock, ready-made door packs
- Configurable notifications and text UI
- ESX, QBCore, QBX or standalone · ox_inventory, qs-inventory, qb-inventory or ESX inventory
- 6 languages: en, it, de, fr, es, pt

## Requirements

- OneSync
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- Optional: ox_target (without it keys are used: `E` to use, `G` for break-in)

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

## Configuration

Everything is in `config.lua` (shared) and `config_server.lua` (server only: admin groups, Discord logs).

```lua
Config.Notify = { system = 'ox_lib' }     -- ox_lib | esx | qb | qbx | okokNotify | mythic_notify | brutal_notify | wasabi_notify | custom
Config.TextUI = { system = 'g_doorlock' } -- g_doorlock | ox_lib | esx | qb | okokTextUI | cd_drawtextui | jg-textui | custom | false
```

Minigames are client functions that return `true` on success, replace them with any minigame you like:

```lua
Config.Lockpick.minigame = function(checks, difficulty)
    return lib.skillCheck(checks)
end
```

## Items

| Item | Used for |
|---|---|
| `lockpick` | lockpick |
| `hacking_device` | hack |
| `garage_remote` | garage remote |

Any other item can be set as a key in the editor. With ox_inventory the remote needs the client export:

```lua
['garage_remote'] = { label = 'Garage Remote', weight = 50, client = { export = 'g_doorlock.useRemote' } },
```

Items opening only some doors use the `doorkey` metadata (door id or group):

```lua
exports.ox_inventory:AddItem(source, 'keycard', 1, { doorkey = 'mrpd_armory' })
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

## Notes

- Don't run another doorlock on the same doors, they will fight each other.
- MLO doors work only if they are real door objects.
- If an imported door doesn't lock, open it in the editor and use **Reselect leaves**.

## License

[GPL-3.0](LICENSE)
