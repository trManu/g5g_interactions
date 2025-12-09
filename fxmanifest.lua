fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'trManu'
description ''
version '1.0.0'

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory'
}

shared_scripts {
    '@ox_lib/init.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    'server/*.lua'
}
