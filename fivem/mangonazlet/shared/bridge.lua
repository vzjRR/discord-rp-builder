---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Environment detection (shared).

    Runs on both sides and decides, at runtime, which framework / inventory /
    target the host server is actually using. This is what removes every
    "edit the config for your framework" step: the resource adapts to the
    server rather than the server adapting to the resource.
]]

MN = MN or {}

local function detectFramework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if MN.hasResource('qbx_core') then return MN.FW.QBX end
    if MN.hasResource('qb-core') then return MN.FW.QB end
    if MN.hasResource('es_extended') then return MN.FW.ESX end
    return MN.FW.STANDALONE
end

local function detectInventory()
    if Config.Inventory ~= 'auto' then return Config.Inventory end
    if MN.hasResource('ox_inventory') then return MN.INV.OX end
    if MN.hasResource('qb-inventory') then return MN.INV.QB end
    if MN.hasResource('qs-inventory') then return MN.INV.QB end -- qs mirrors the qb API surface we use
    if MN.hasResource('es_extended') then return MN.INV.ESX end
    return MN.INV.NONE
end

local function detectTarget()
    if Config.Target ~= 'auto' then return Config.Target end
    if MN.hasResource('ox_target') then return MN.TGT.OX end
    if MN.hasResource('qb-target') then return MN.TGT.QB end
    return MN.TGT.OX
end

MN.framework = detectFramework()
MN.inventory = detectInventory()
MN.target    = detectTarget()

-- Optional integrations, each independently detected.
MN.has = {
    oxLib     = MN.hasResource('ox_lib'),
    oxMysql   = MN.hasResource('oxmysql'),
    mysqlAsync = MN.hasResource('mysql-async'),
    ghmattiMysql = MN.hasResource('ghmattimysql'),
    oxTarget  = MN.hasResource('ox_target'),
    qbTarget  = MN.hasResource('qb-target'),
    oxInv     = MN.hasResource('ox_inventory'),
    qbMenu    = MN.hasResource('qb-menu'),
    qbInput   = MN.hasResource('qb-input'),
    qbProgress = MN.hasResource('progressbar') or MN.hasResource('qb-progressbar'),
}

-- ox_lib is required for menus, dialogs, progress and callbacks. If it is not
-- installed the resource degrades loudly rather than erroring on every click.
MN.uiReady = MN.has.oxLib

---True when persistent storage is available in any supported form.
MN.dbReady = MN.has.oxMysql

MN.reloadLocale()

MN.debug('detected framework=%s inventory=%s target=%s oxlib=%s db=%s',
    MN.framework, MN.inventory, MN.target, tostring(MN.has.oxLib), tostring(MN.dbReady))
