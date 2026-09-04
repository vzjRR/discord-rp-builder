fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'enclave_icecream'
author 'Enclave RP'
description 'Ice cream parlour job for FiveM — crafting, NPC orders, register, supply runs, ice cream truck and a full business account. Works on Qbox / QBCore / ESX / standalone.'
version '1.0.0'
repository 'https://github.com/vzjRR/discord-rp-builder'

-- ox_lib is the only hard dependency; every other integration is detected at runtime.
dependencies {
    '/server:7290',
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/locations.lua',
    'config/recipes.lua',
    'bridge/shared.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/targets.lua',
    'client/craft.lua',
    'client/register.lua',
    'client/orders.lua',
    'client/supply.lua',
    'client/truck.lua',
    'client/boss.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- إعدادات سيرفرية بحتة (الويبهوك) — لا تنزل لجهاز اللاعب
    'server/config.server.lua',
    'bridge/server.lua',
    'server/db.lua',
    'server/logs.lua',
    'server/main.lua',
    'server/society.lua',
    'server/craft.lua',
    'server/register.lua',
    'server/orders.lua',
    'server/supply.lua',
    'server/truck.lua',
    'server/boss.lua',
}

files {
    'locales/*.json',
}

-- config/items.lua is documentation for ox_inventory and is NOT loaded by this resource.
