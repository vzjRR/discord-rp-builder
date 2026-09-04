---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Client framework adapter.

    Keeps the local copy of the player's employment in sync with whatever
    framework is running, and wraps notifications, targets and asset loading so
    nothing else in client/ has to care.
]]

MN = MN or {}

MN.job = { name = nil, grade = 0, onduty = false }
MN.busy = false
MN.nearShop = false

local core

-- ═══════════════════════════════════════════════════════════════
-- Notifications
-- ═══════════════════════════════════════════════════════════════

---@param message string
---@param kind? 'inform'|'success'|'error'|'warning'
function MN.notify(message, kind)
    kind = kind or 'inform'

    local mode = Config.UI.notify
    if mode == 'auto' then mode = MN.has.oxLib and 'ox' or 'framework' end

    if mode == 'framework' then
        if MN.framework == MN.FW.QBX or MN.framework == MN.FW.QB then
            TriggerEvent('QBCore:Notify', message,
                (kind == 'success' or kind == 'error') and kind or 'primary', 5000)
            return
        elseif MN.framework == MN.FW.ESX then
            TriggerEvent('esx:showNotification', message)
            return
        end
    end

    if not MN.has.oxLib then
        print(('[%s] %s'):format(MN.BRAND, message))
        return
    end

    lib.notify({
        title = T('brand'),
        description = message,
        type = kind,
        duration = 5000,
        position = 'top-right',
        icon = 'ice-cream',
        iconColor = Config.UI.theme.mango,
    })
end

RegisterNetEvent('mangonazlet:client:notify', function(key, kind, args)
    if type(key) ~= 'string' then return end
    if type(args) == 'table' and #args > 0 then
        MN.notify(T(key, table.unpack(args)), kind)
    else
        MN.notify(T(key), kind)
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- Employment state
-- ═══════════════════════════════════════════════════════════════

---@param job table|nil
local function applyJob(job)
    local before = MN.job

    if type(job) ~= 'table' or job.name ~= Permissions.job then
        MN.job = { name = nil, grade = 0, onduty = false }
    else
        local grade = 0
        if type(job.grade) == 'table' then
            grade = tonumber(job.grade.level) or 0          -- Qbox / QBCore
        else
            grade = tonumber(job.grade) or tonumber(job.grade_level) or 0  -- ESX
        end

        local onduty = job.onduty
        if onduty == nil then onduty = true end

        MN.job = { name = job.name, grade = grade, onduty = onduty == true }
    end

    if before.name ~= MN.job.name or before.grade ~= MN.job.grade or before.onduty ~= MN.job.onduty then
        TriggerEvent('mangonazlet:client:jobChanged', MN.job)
        MN.debug('job → %s grade=%s duty=%s',
            tostring(MN.job.name), MN.job.grade, tostring(MN.job.onduty))
    end
end

function MN.refreshJob()
    if MN.framework == MN.FW.QBX then
        local data = exports.qbx_core:GetPlayerData()
        applyJob(data and data.job)

    elseif MN.framework == MN.FW.QB then
        core = core or exports['qb-core']:GetCoreObject()
        local data = core.Functions.GetPlayerData()
        applyJob(data and data.job)

    elseif MN.framework == MN.FW.ESX then
        core = core or exports['es_extended']:getSharedObject()
        local data = core.GetPlayerData()
        applyJob(data and data.job)

    else
        lib.callback('mangonazlet:server:job', false, applyJob)
    end
end

---@return boolean
function MN.isStaff() return MN.job.name == Permissions.job end

---@return boolean
function MN.isWorking()
    if not MN.isStaff() then return false end
    if Config.RequireDuty and not MN.job.onduty then return false end
    return true
end

---@param permission string
---@return boolean
function MN.allowed(permission)
    return MN.isWorking() and Permissions.can(MN.job.grade, permission)
end

---Check access and tell the player what is wrong. Returns true when allowed.
---@param permission? string
---@return boolean
function MN.checkAccess(permission)
    if not MN.isStaff() then
        MN.notify(T('not_employee'), 'error')
        return false
    end
    if Config.RequireDuty and not MN.job.onduty then
        MN.notify(T('not_on_duty'), 'error')
        return false
    end
    if permission and not Permissions.can(MN.job.grade, permission) then
        MN.notify(T('no_permission'), 'error')
        return false
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- Inventory reads (display only — the server re-checks everything)
-- ═══════════════════════════════════════════════════════════════

---@param item string
---@return number
function MN.itemCount(item)
    if MN.inventory == MN.INV.OX then
        return exports.ox_inventory:Search('count', item) or 0

    elseif MN.inventory == MN.INV.QB then
        local data
        if MN.framework == MN.FW.QBX then
            data = exports.qbx_core:GetPlayerData()
        else
            core = core or exports['qb-core']:GetCoreObject()
            data = core.Functions.GetPlayerData()
        end
        local items = data and data.items
        if type(items) ~= 'table' then return 0 end
        local total = 0
        for _, slot in pairs(items) do
            if slot and slot.name == item then
                total = total + (tonumber(slot.amount) or tonumber(slot.count) or 0)
            end
        end
        return total
    end
    return 0
end

---Count including the "any scoop" wildcard.
---@param item string
---@return number
function MN.countIngredient(item)
    if item ~= Products.SCOOP_ANY then return MN.itemCount(item) end
    local total = 0
    for _, name in ipairs(Products.scoopNames) do
        total = total + MN.itemCount(name)
    end
    return total
end

-- ═══════════════════════════════════════════════════════════════
-- Assets
-- ═══════════════════════════════════════════════════════════════

---@param dict string
---@return boolean
function MN.loadAnim(dict)
    if not dict then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then
            MN.warn('animation dictionary "%s" did not load', dict)
            return false
        end
        Wait(10)
    end
    return true
end

---@param model string|number
---@return number|nil
function MN.loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) then
        MN.warn('model "%s" is not in the game files', tostring(model))
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            MN.warn('model "%s" timed out loading', tostring(model))
            return nil
        end
        Wait(10)
    end
    return hash
end

---@param anim table|nil
function MN.playAnim(anim)
    if not anim or not anim.dict then return end
    if not MN.loadAnim(anim.dict) then return end
    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 3.0, -1.0, -1, 49, 0, false, false, false)
end

function MN.stopAnim()
    ClearPedTasks(PlayerPedId())
end

---@param state boolean
function MN.setBusy(state) MN.busy = state == true end

-- ═══════════════════════════════════════════════════════════════
-- Target wrapper (ox_target / qb-target)
-- ═══════════════════════════════════════════════════════════════

---@param data { name: string, coords: vector3, size: vector3, heading?: number, options: table }
---@return any id
function MN.addZone(data)
    if MN.target == MN.TGT.OX then
        return exports.ox_target:addBoxZone({
            coords = data.coords,
            size = data.size,
            rotation = data.heading or 0.0,
            name = data.name,
            debug = Config.DebugZones,
            options = data.options,
        })
    end

    local options = {}
    for i = 1, #data.options do
        local option = data.options[i]
        options[i] = {
            label = option.label,
            icon = option.icon and ('fas fa-' .. option.icon) or 'fas fa-ice-cream',
            action = option.onSelect,
            canInteract = option.canInteract,
        }
    end

    exports['qb-target']:AddBoxZone(data.name, data.coords, data.size.x, data.size.y, {
        name = data.name,
        heading = data.heading or 0.0,
        debugPoly = Config.DebugZones,
        minZ = data.coords.z - (data.size.z / 2),
        maxZ = data.coords.z + (data.size.z / 2),
    }, {
        options = options,
        distance = data.options[1] and data.options[1].distance or 2.0,
    })
    return data.name
end

---@param id any
function MN.removeZone(id)
    if not id then return end
    if MN.target == MN.TGT.OX then
        exports.ox_target:removeZone(id)
    else
        exports['qb-target']:RemoveZone(id)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Framework events
-- ═══════════════════════════════════════════════════════════════

if MN.framework == MN.FW.QBX or MN.framework == MN.FW.QB then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        MN.refreshJob()
        TriggerEvent('mangonazlet:client:loaded')
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() applyJob(nil) end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', applyJob)
    RegisterNetEvent('qbx_core:client:onJobUpdate', applyJob)
    RegisterNetEvent('QBCore:Client:SetDuty', function() MN.refreshJob() end)
    RegisterNetEvent('QBCore:Player:SetPlayerData', function(data) applyJob(data and data.job) end)

elseif MN.framework == MN.FW.ESX then
    RegisterNetEvent('esx:playerLoaded', function(xPlayer)
        applyJob(xPlayer and xPlayer.job)
        TriggerEvent('mangonazlet:client:loaded')
    end)
    RegisterNetEvent('esx:onPlayerLogout', function() applyJob(nil) end)
    RegisterNetEvent('esx:setJob', applyJob)

else
    RegisterNetEvent('mangonazlet:client:job', applyJob)
end

-- Duty is confirmed by the server in every mode.
RegisterNetEvent('mangonazlet:client:duty', function(onduty)
    if MN.framework == MN.FW.ESX or MN.framework == MN.FW.STANDALONE then
        MN.job.onduty = onduty == true
        TriggerEvent('mangonazlet:client:jobChanged', MN.job)
    else
        MN.refreshJob()
    end
end)

CreateThread(function()
    Wait(500)
    MN.refreshJob()
    TriggerEvent('mangonazlet:client:loaded')
end)
