fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'g_doorlock'
author 'Gravity Studios'
description 'Gravity Doorlock - doors, double doors, gates and garage doors with server-side permissions, PIN, keycards and in-game editor'
version '1.0.0'

ui_page 'web/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/locale.lua',
    'locales/*.lua',
    'shared/utils.lua',
    'shared/validate.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config_server.lua',
    'hooks.lua',
    'bridge/framework/*.lua',
    'bridge/inventory/*.lua',
    'server/bridge.lua',
    'server/ratelimit.lua',
    'server/logs.lua',
    'server/db.lua',
    'server/access.lua',
    'server/doors.lua',
    'server/interact.lua',
    'server/alarm.lua',
    'server/breakin.lua',
    'server/schedule.lua',
    'server/migrate.lua',
    'server/extras.lua',
    'server/templates.lua',
    'server/admin.lua',
    'server/exports.lua',
    'server/main.lua',
}

client_scripts {
    'client/nui.lua',
    'client/notify.lua',
    'client/doors.lua',
    'client/interact.lua',
    'client/breakin.lua',
    'client/alarm.lua',
    'client/editor.lua',
    'client/main.lua',
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/img/logo.png',
    'web/fonts/*.woff2',
    'examples/packs/*.json',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}

