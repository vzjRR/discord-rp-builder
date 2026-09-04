---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Constants
    Immutable identifiers shared by client, server and the installer.
    Never localise these; they are wire/DB identifiers.
]]

MN = MN or {}

MN.BRAND = 'MangoNazlet'
MN.RESOURCE = GetCurrentResourceName()
MN.VERSION = '1.0.0'

-- Item name prefix. Every item this resource owns starts with it, which lets the
-- installer find and update exactly its own items and nothing else.
MN.PREFIX = 'mn_'

-- Marker written into foreign files we patch, so patching is idempotent.
MN.PATCH_BEGIN = '-- >>> MANGONAZLET AUTO-GENERATED ITEMS — DO NOT EDIT BY HAND <<<'
MN.PATCH_END   = '-- <<< MANGONAZLET AUTO-GENERATED ITEMS — END >>>'

-- Sale channels, persisted in the `channel` column of mn_sales.
MN.CHANNEL = {
    COUNTER = 'counter',  -- NUI walk-in customer purchase
    ORDER   = 'order',    -- NPC ticket served by an employee
    BILL    = 'bill',     -- employee-issued bill to a player
    TRUCK   = 'truck',    -- mobile truck sale
}

-- Permission keys, resolved per grade in config/permissions.lua.
MN.PERM = {
    CRAFT   = 'craft',
    REGISTER= 'register',
    STORAGE = 'storage',
    SUPPLY  = 'supply',
    MANAGE  = 'manage',
}

-- Framework / inventory / target identifiers produced by detection.
MN.FW  = { QBX = 'qbx', QB = 'qb', ESX = 'esx', STANDALONE = 'standalone' }
MN.INV = { OX = 'ox', QB = 'qb', ESX = 'esx', NONE = 'none' }
MN.TGT = { OX = 'ox', QB = 'qb' }
