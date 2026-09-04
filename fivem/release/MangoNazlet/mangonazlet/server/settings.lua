---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Server-only settings.

    Loaded ONLY on the server (server_scripts). Players never receive this file,
    which is why the Discord webhook belongs here and not in config/config.lua.

    Better still: leave the webhook empty and set it in server.cfg, so it never
    enters the repository at all:

        set mangonazlet_webhook "https://discord.com/api/webhooks/..."
]]

Config = Config or {}

Config.Server = {
    -- Read from the `mangonazlet_webhook` convar first; this is the fallback.
    webhook = '',
    webhookName = 'MangoNazlet',

    -- Embed colours (decimal).
    colours = {
        sale     = 0xF5A623,  -- mango
        money    = 0x2E7D5B,  -- leaf
        staff    = 0x3498DB,
        warning  = 0xE74C3C,
    },

    -- What reaches Discord. Everything is written to `mn_logs` regardless.
    logSales     = false,  -- every single sale is noisy on a busy server
    logMoney     = true,   -- deposits, withdrawals, supply spend, payroll
    logStaff     = true,   -- hire / fire / rank changes
    logSecurity  = true,   -- rejected requests and tampering attempts

    -- Admin ace/permission required by /mn:setjob and /mn:place.
    adminAce = 'group.admin',
}
