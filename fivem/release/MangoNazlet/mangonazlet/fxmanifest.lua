fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mangonazlet'
author 'MangoNazlet'
description 'MangoNazlet — an ice cream and dessert restaurant job with crafting, a customer ordering menu, NPC tickets, supply runs, a mobile truck and full business management. Detects and adapts to Qbox, QBCore, ESX or standalone at runtime.'
version '1.0.0'

-- ox_lib is the only hard requirement. Everything else (framework, inventory,
-- target, database) is detected at runtime and adapted to automatically.
dependencies {
    '/server:7290',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/constants.lua',
    'locales/en.lua',
    'locales/ar.lua',
    'config/config.lua',
    'config/permissions.lua',
    'config/products.lua',
    'config/recipes.lua',
    'config/locations.lua',
    'shared/locale.lua',
    'shared/utils.lua',
    'shared/bridge.lua',
}

client_scripts {
    'client/bridge.lua',
    'client/main.lua',
    'client/zones.lua',
    'client/cooking.lua',
    'client/interactions.lua',
    'client/customers.lua',
    'client/shop.lua',
    'client/supply.lua',
    'client/truck.lua',
    'client/management.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/settings.lua',
    'server/database.lua',
    'server/bridge.lua',
    'server/logs.lua',
    'server/security.lua',
    'server/business.lua',
    'server/inventory.lua',
    'server/billing.lua',
    'server/orders.lua',
    'server/supply.lua',
    'server/truck.lua',
    'server/management.lua',
    'server/installer.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
