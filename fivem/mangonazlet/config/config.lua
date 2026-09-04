---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — General configuration.

    You do not need to edit this file to install the resource. Everything here
    already holds a working production value, and everything environment
    specific (framework, inventory, target, database) is detected at runtime.

    NOTE: this file is a shared_script — it is downloaded by every player.
    Never put a secret here. Server-only settings live in server/settings.lua.
]]

Config = {}

-- ── Language ───────────────────────────────────────────────────
-- 'ar' or 'en'. Drives Lua strings and the NUI (including RTL layout).
Config.Locale = 'ar'

-- ── Integration ────────────────────────────────────────────────
-- 'auto' inspects the running server and picks the right bridge. Override only
-- if detection is wrong; the resolved values are printed on start.
Config.Framework = 'auto'  -- 'auto' | 'qbx' | 'qb' | 'esx' | 'standalone'
Config.Inventory = 'auto'  -- 'auto' | 'ox' | 'qb' | 'esx' | 'none'
Config.Target    = 'auto'  -- 'auto' | 'ox' | 'qb'

-- ── Automatic installation ─────────────────────────────────────
-- The installer registers the job and the items with whatever framework is
-- running, so the owner never edits another resource by hand.
Config.AutoInstall = {
    -- Register the MangoNazlet job at runtime (qbx_core / qb-core) or write it
    -- to the database (ESX). Safe and idempotent; runs on every start.
    job = true,

    -- Register items. qb-core takes them at runtime. ox_inventory has no
    -- runtime item API, so its data/items.lua is patched instead — always
    -- inside a clearly marked block, always after writing a backup, and only
    -- when our block is absent or out of date.
    items = true,

    -- After patching ox_inventory, restart it automatically so the items go
    -- live without the owner typing anything. Only ever done while the server
    -- is empty; with players online it is deferred to the next empty restart
    -- to avoid disturbing open inventories.
    restartInventory = true,

    -- Keep a .bak of any foreign file before patching it.
    backup = true,
}

-- ── Shift ──────────────────────────────────────────────────────
Config.RequireDuty = true          -- must clock in before working
Config.BlockOffDutyWithStock = false -- forbid clocking out holding shop stock

-- ── Economy ────────────────────────────────────────────────────
Config.Economy = {
    playerAccount = 'bank',   -- where an employee receives tips and payroll
    billAccount   = 'bank',   -- where an employee-issued bill is charged
    counterCash   = true,     -- customers may pay cash at the counter
    counterBank   = true,     -- customers may pay by card at the counter

    -- Split of every sale. Must total 1.0; checked on start.
    businessShare = 0.75,
    employeeTip   = 0.25,
    maxTipPerSale = 250,      -- cap so one huge ticket cannot mint money

    openingBalance = 25000,   -- business account on very first start only
    allowNegative  = false,
}

Config.Payroll = {
    enabled = true,
    intervalMinutes = 30,
    requireDuty = true,
    minBalance = 0,           -- never pay the balance below this
}

-- ── Crafting ───────────────────────────────────────────────────
Config.Crafting = {
    timeMultiplier = 1.0,     -- 0.5 = twice as fast
    maxDistance = 3.0,        -- cancel if the player walks off
    maxBatch = 10,
    cooldownMs = 750,         -- server-side rate limit per player
    skillCheck = { enabled = true, minDifficulty = 2 },
}

-- ── Customer tickets (NPC) ─────────────────────────────────────
Config.Tickets = {
    enabled = true,
    maxPending = 5,
    spawnDelay = { min = 45, max = 120 },  -- seconds
    expiry = 300,                          -- seconds before the customer leaves
    minStaffOnDuty = 1,
    multipliers = { day = 1.25, hot = 1.35, night = 0.85 },
    expirePenalty = 0,
}

-- ── Counter (walk-in customers, NUI) ───────────────────────────
Config.Counter = {
    enabled = true,
    -- Customers may only buy what staff actually made: purchases draw from the
    -- shop's stock, so an empty shop sells nothing. This is what makes the
    -- business loop real rather than an infinite vendor.
    requireStock = true,
    -- Sold without staff present? false means the shop must have someone on duty.
    requireStaffOnDuty = false,
    maxPerCheckout = 10,      -- items per basket
    cooldownMs = 1500,
}

-- ── Employee billing ───────────────────────────────────────────
Config.Billing = {
    enabled = true,
    maxAmount = 5000,
    maxDistance = 5.0,
    timeout = 30,             -- seconds to accept
}

-- ── Supply ─────────────────────────────────────────────────────
Config.Supply = {
    enabled = true,
    payFrom = 'business',     -- 'business' | 'player'
    maxQuantity = 200,
    run = {
        enabled = true,
        vehicle = 'boxville2',
        payout = { min = 900, max = 1600 },
        pickups = 3,
        cooldownMinutes = 10,
    },
}

-- ── Mobile truck ───────────────────────────────────────────────
Config.Truck = {
    enabled = true,
    model = 'taco',           -- ships with GTA V; no add-on needed
    fee = 500,
    requireGrade = 1,
    priceMultiplier = 1.4,
    saleCooldown = 20,
    maxDistance = 8.0,
}

-- ── Melting ────────────────────────────────────────────────────
-- Requires ox_inventory (per-slot metadata). Ignored on other inventories.
Config.Melting = {
    enabled = true,
    checkInterval = 60,       -- seconds between "it's melting" warnings
    freshMinutes = 15,        -- full value up to here
    minValueRatio = 0.35,     -- floor for a melted but sellable item
    ruinMinutes = 45,         -- unsellable and inedible past here (0 = never)
}

-- ── Storage ────────────────────────────────────────────────────
Config.Storage = {
    freezerSlots = 60,   freezerWeight = 180000,
    pantrySlots = 45,    pantryWeight = 250000,
}

-- ── Interface ──────────────────────────────────────────────────
Config.UI = {
    notify = 'auto',          -- 'auto' (ox_lib if present, else framework) | 'ox' | 'framework'
    contextPosition = 'top-right',
    blip = true,
    textUI = true,
    -- Offer every interaction on [E] as well as through the target resource.
    -- Leave this on unless your server deliberately routes everything through
    -- targeting: a prompt that names a key which does nothing is worse than
    -- no prompt.
    keyInteract = true,
    -- Draw the shop's name over the counter. No GTA prop can carry it, so this
    -- is what puts the name on the building.
    sign = true,
    signDistance = 22.0,
    -- Brand colours, handed to the NUI. Change once, the whole UI follows.
    theme = {
        mango  = '#F5A623',
        deep   = '#D4780B',
        leaf   = '#2E7D5B',
        cream  = '#FFF6E6',
        ink    = '#241a10',
    },
}

-- ── Diagnostics ────────────────────────────────────────────────
Config.Debug = false      -- verbose console output
Config.DebugZones = false -- draw interaction boxes in-game
