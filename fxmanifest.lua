fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Falcon'
description 'Framework-agnostic boss management (QBCore / ESX / QBox / OxCore)'
version '3.0.0'

provide 'qb-management'
provide 'qb-gangmenu'
provide 'esx_society'

dependency 'oxmysql'

ui_page 'web/dist/index.html'

shared_scripts {
    'config.lua',
    'locales/en.lua',
    'locales/es.lua',
    'locales/de.lua',
    'shared/locales.lua',
    'shared/permissions.lua',
    'shared/framework.lua'
}

client_scripts {
    'client/markers.lua',
    'client/target.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/security.lua',
    'server/audit.lua',
    'server/ranks.lua',
    'server/employees.lua',
    'server/finance.lua',
    'server/inventory.lua',
    'server/uniforms.lua',
    'server/applications.lua',
    'server/admin.lua',
    'server/gangs.lua',
    'server/territories.lua',
    'server/contracts.lua',
    'server/main.lua'
}

files {
    'web/dist/index.html',
    'web/dist/style.css',
    'web/dist/main.js'
}
