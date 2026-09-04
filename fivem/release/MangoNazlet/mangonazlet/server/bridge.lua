---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Server framework adapter.

    Everything framework-specific lives here. The rest of server/ speaks only in
    MN.* calls and never learns which framework is running, which is what lets
    one codebase serve Qbox, QBCore, ESX and standalone without edits.
]]

MN = MN or {}

local core           -- QBCore / ESX shared object, resolved lazily
local standaloneJobs = {}   -- [identifier] = grade   (standalone mode)
local dutyState      = {}   -- [source] = boolean     (ESX / standalone)

CreateThread(function()
    if MN.framework == MN.FW.QB then
        core = exports['qb-core']:GetCoreObject()
    elseif MN.framework == MN.FW.ESX then
        core = exports['es_extended']:getSharedObject()
    end
end)

---@return table|nil
local function qbCore()
    if not core and MN.framework == MN.FW.QB then core = exports['qb-core']:GetCoreObject() end
    return core
end

---@return table|nil
local function esxCore()
    if not core and MN.framework == MN.FW.ESX then core = exports['es_extended']:getSharedObject() end
    return core
end

-- ═══════════════════════════════════════════════════════════════
-- Identity
-- ═══════════════════════════════════════════════════════════════

---Stable identifier, used for standalone employment and security logging.
---@param src number
---@return string|nil
function MN.identifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return GetPlayerIdentifier(src, 0)
end

---Unified player record:
---  { source, citizenid, name, job = { name, grade, onduty } }
---@param src any
---@return table|nil
function MN.getPlayer(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return nil end

    if MN.framework == MN.FW.QBX then
        local player = exports.qbx_core:GetPlayer(src)
        if not player then return nil end
        local data = player.PlayerData
        return {
            source = src,
            citizenid = data.citizenid,
            name = ('%s %s'):format(data.charinfo.firstname or '', data.charinfo.lastname or ''),
            job = {
                name = data.job.name,
                grade = tonumber(data.job.grade and data.job.grade.level) or 0,
                onduty = data.job.onduty == true,
            },
        }

    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        if not player then return nil end
        local data = player.PlayerData
        return {
            source = src,
            citizenid = data.citizenid,
            name = ('%s %s'):format(data.charinfo.firstname or '', data.charinfo.lastname or ''),
            job = {
                name = data.job.name,
                grade = tonumber(data.job.grade and data.job.grade.level) or 0,
                onduty = data.job.onduty == true,
            },
        }

    elseif MN.framework == MN.FW.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return nil end
        local job = xPlayer.getJob()
        return {
            source = src,
            citizenid = xPlayer.identifier,
            name = xPlayer.getName(),
            job = {
                name = job.name,
                grade = tonumber(job.grade) or 0,
                -- ESX has no duty concept; MangoNazlet keeps it itself.
                onduty = dutyState[src] == true,
            },
        }
    end

    -- standalone
    local identifier = MN.identifier(src)
    if not identifier then return nil end
    local grade = standaloneJobs[identifier]
    return {
        source = src,
        citizenid = identifier,
        name = GetPlayerName(src) or ('Player %s'):format(src),
        job = {
            name = grade ~= nil and Permissions.job or nil,
            grade = grade or 0,
            onduty = dutyState[src] == true,
        },
    }
end

---Find an online player by citizen id.
---@param citizenid string
---@return number|nil source
function MN.sourceOf(citizenid)
    if type(citizenid) ~= 'string' then return nil end
    for _, id in ipairs(GetPlayers()) do
        local player = MN.getPlayer(tonumber(id))
        if player and player.citizenid == citizenid then return player.source end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- Money
-- ═══════════════════════════════════════════════════════════════

---@param src number
---@param account 'cash'|'bank'
---@param amount number
---@param reason? string
---@return boolean
function MN.addMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    reason = reason or 'mangonazlet'

    if MN.framework == MN.FW.QBX then
        return exports.qbx_core:AddMoney(src, account, amount, reason) == true

    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.AddMoney(account, amount, reason) == true

    elseif MN.framework == MN.FW.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return false end
        if account == 'cash' then xPlayer.addMoney(amount, reason)
        else xPlayer.addAccountMoney('bank', amount, reason) end
        return true
    end

    -- standalone: no economy to touch; tell the client so a custom one can hook in
    TriggerClientEvent('mangonazlet:client:money', src, account, amount, reason)
    return true
end

---@param src number
---@param account 'cash'|'bank'
---@param amount number
---@param reason? string
---@return boolean
function MN.removeMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    reason = reason or 'mangonazlet'

    if MN.framework == MN.FW.QBX then
        return exports.qbx_core:RemoveMoney(src, account, amount, reason) == true

    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.RemoveMoney(account, amount, reason) == true

    elseif MN.framework == MN.FW.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return false end
        if account == 'cash' then
            if xPlayer.getMoney() < amount then return false end
            xPlayer.removeMoney(amount, reason)
        else
            local acc = xPlayer.getAccount('bank')
            if not acc or acc.money < amount then return false end
            xPlayer.removeAccountMoney('bank', amount, reason)
        end
        return true
    end

    TriggerClientEvent('mangonazlet:client:money', src, account, -amount, reason)
    return true
end

---@param src number
---@param account 'cash'|'bank'
---@return number
function MN.getMoney(src, account)
    if MN.framework == MN.FW.QBX then
        return tonumber(exports.qbx_core:GetMoney(src, account)) or 0

    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        return player and (tonumber(player.PlayerData.money[account]) or 0) or 0

    elseif MN.framework == MN.FW.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return 0 end
        if account == 'cash' then return xPlayer.getMoney() end
        local acc = xPlayer.getAccount('bank')
        return acc and acc.money or 0
    end
    return 0
end

-- ═══════════════════════════════════════════════════════════════
-- Inventory
-- ═══════════════════════════════════════════════════════════════

---@param src number
---@param item string
---@param count number
---@param metadata? table
---@return boolean
function MN.addItem(src, item, count, metadata)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false end

    if MN.inventory == MN.INV.OX then
        return exports.ox_inventory:AddItem(src, item, count, metadata) == true

    elseif MN.inventory == MN.INV.QB then
        if MN.framework == MN.FW.QB then
            local qb = qbCore()
            local player = qb and qb.Functions.GetPlayer(src)
            if not player then return false end
            return player.Functions.AddItem(item, count, false, metadata) ~= false
        end
        return exports['qb-inventory']:AddItem(src, item, count, false, metadata, 'mangonazlet') ~= false

    elseif MN.inventory == MN.INV.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return false end
        if not xPlayer.canCarryItem(item, count) then return false end
        xPlayer.addInventoryItem(item, count)
        return true
    end

    return true -- no inventory installed: nothing to hold, treat as success
end

---@param src number
---@param item string
---@param count number
---@param metadata? table
---@return boolean
function MN.removeItem(src, item, count, metadata)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false end

    if MN.inventory == MN.INV.OX then
        return exports.ox_inventory:RemoveItem(src, item, count, metadata) == true

    elseif MN.inventory == MN.INV.QB then
        if MN.framework == MN.FW.QB then
            local qb = qbCore()
            local player = qb and qb.Functions.GetPlayer(src)
            if not player then return false end
            return player.Functions.RemoveItem(item, count) ~= false
        end
        return exports['qb-inventory']:RemoveItem(src, item, count, nil, 'mangonazlet') ~= false

    elseif MN.inventory == MN.INV.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return false end
        local slot = xPlayer.getInventoryItem(item)
        if not slot or slot.count < count then return false end
        xPlayer.removeInventoryItem(item, count)
        return true
    end

    return true
end

---@param src number
---@param item string
---@return number
function MN.itemCount(src, item)
    if MN.inventory == MN.INV.OX then
        return tonumber(exports.ox_inventory:GetItemCount(src, item)) or 0

    elseif MN.inventory == MN.INV.QB then
        local items
        if MN.framework == MN.FW.QBX then
            local player = exports.qbx_core:GetPlayer(src)
            items = player and player.PlayerData.items
        else
            local qb = qbCore()
            local player = qb and qb.Functions.GetPlayer(src)
            items = player and player.PlayerData.items
        end
        if type(items) ~= 'table' then return 0 end
        local total = 0
        for _, slot in pairs(items) do
            if slot and slot.name == item then
                total = total + (tonumber(slot.amount) or tonumber(slot.count) or 0)
            end
        end
        return total

    elseif MN.inventory == MN.INV.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return 0 end
        local slot = xPlayer.getInventoryItem(item)
        return slot and slot.count or 0
    end
    return 0
end

---@param src number
---@param item string
---@param count number
---@return boolean
function MN.canCarry(src, item, count)
    if MN.inventory == MN.INV.OX then
        return exports.ox_inventory:CanCarryItem(src, item, count) == true

    elseif MN.inventory == MN.INV.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        return xPlayer ~= nil and xPlayer.canCarryItem(item, count) == true

    elseif MN.inventory == MN.INV.QB then
        if MN.framework == MN.FW.QBX or MN.hasResource('qb-inventory') then
            local ok = exports['qb-inventory']:CanAddItem(src, item, count)
            return ok ~= false
        end
        return true
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- Employment
-- ═══════════════════════════════════════════════════════════════

---@param src number
---@param onduty boolean
---@return boolean
function MN.setDuty(src, onduty)
    onduty = onduty == true

    if MN.framework == MN.FW.QBX then
        exports.qbx_core:SetJobDuty(src, onduty)
    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        if not player then return false end
        player.Functions.SetJobDuty(onduty)
        TriggerClientEvent('QBCore:Client:SetDuty', src, onduty)
    else
        dutyState[src] = onduty
    end

    TriggerClientEvent('mangonazlet:client:duty', src, onduty)
    return true
end

---@param src number
---@param grade number
---@return boolean
function MN.setJob(src, grade)
    grade = math.floor(tonumber(grade) or 0)

    if MN.framework == MN.FW.QBX then
        return exports.qbx_core:SetJob(src, Permissions.job, grade) ~= false

    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.SetJob(Permissions.job, grade) ~= false

    elseif MN.framework == MN.FW.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.setJob(Permissions.job, grade)
        return true
    end

    local identifier = MN.identifier(src)
    if not identifier then return false end
    standaloneJobs[identifier] = grade
    MN.db.saveStandaloneJob(identifier, grade)
    TriggerClientEvent('mangonazlet:client:job', src, {
        name = Permissions.job, grade = grade, onduty = dutyState[src] == true,
    })
    return true
end

---@param src number
---@return boolean
function MN.clearJob(src)
    if MN.framework == MN.FW.QBX then
        return exports.qbx_core:SetJob(src, 'unemployed', 0) ~= false

    elseif MN.framework == MN.FW.QB then
        local qb = qbCore()
        local player = qb and qb.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.SetJob('unemployed', 0) ~= false

    elseif MN.framework == MN.FW.ESX then
        local esx = esxCore()
        local xPlayer = esx and esx.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.setJob('unemployed', 0)
        return true
    end

    local identifier = MN.identifier(src)
    if identifier then
        standaloneJobs[identifier] = nil
        MN.db.saveStandaloneJob(identifier, nil)
    end
    dutyState[src] = nil
    TriggerClientEvent('mangonazlet:client:job', src, nil)
    return true
end

---Offline grade change for standalone mode.
---@param identifier string
---@param grade number|nil
function MN.setStandaloneGrade(identifier, grade)
    if not identifier then return end
    standaloneJobs[identifier] = grade
    MN.db.saveStandaloneJob(identifier, grade)
end

---Load standalone employment on boot.
function MN.loadStandaloneJobs()
    if MN.framework ~= MN.FW.STANDALONE then return end
    standaloneJobs = MN.db.loadStandaloneJobs()
    MN.debug('loaded %s standalone employment records', MN.count(standaloneJobs))
end

-- ═══════════════════════════════════════════════════════════════
-- Notifications — the client translates the key, so one message works
-- in whatever language that particular player is running.
-- ═══════════════════════════════════════════════════════════════

---@param src number
---@param key string
---@param kind? 'inform'|'success'|'error'|'warning'
function MN.notify(src, key, kind, ...)
    TriggerClientEvent('mangonazlet:client:notify', src, key, kind or 'inform', { ... })
end

AddEventHandler('playerDropped', function()
    dutyState[source] = nil
end)
