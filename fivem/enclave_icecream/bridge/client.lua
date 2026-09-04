---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — جسر العميل
    ------------------------------
    يوحّد الفروقات بين qbx_core / qb-core / es_extended / standalone.
    بقية ملفات client/ ما تعرف أي فريمويرك شغال — تستخدم IC.* فقط.
]]

IC = IC or {}

-- الحالة المحلية للاعب فيما يخص وظيفة المحل
IC.job = { name = nil, grade = 0, onduty = false, label = nil }
IC.loaded = false

local frameworkObject   -- QBCore أو ESX object عند الحاجة

-- ────────────────────────────────────────────────────────────
-- الإشعارات
-- ────────────────────────────────────────────────────────────

---@param message string
---@param kind? 'inform'|'success'|'error'|'warning'
---@param duration? number
function IC.notify(message, kind, duration)
    kind = kind or 'inform'
    if Config.UI.notify == 'framework' then
        if IC.framework == 'qbx' or IC.framework == 'qb' then
            local qbKind = (kind == 'success' and 'success')
                or (kind == 'error' and 'error') or 'primary'
            TriggerEvent('QBCore:Notify', message, qbKind, duration or 5000)
            return
        elseif IC.framework == 'esx' then
            TriggerEvent('esx:showNotification', message)
            return
        end
    end
    lib.notify({
        title = L('job_label'),
        description = message,
        type = kind,
        duration = duration or 5000,
        position = 'top-right',
        icon = 'ice-cream',
    })
end

-- ────────────────────────────────────────────────────────────
-- قراءة بيانات الوظيفة من الفريمويرك
-- ────────────────────────────────────────────────────────────

---يحوّل جدول job الخاص بالفريمويرك إلى شكلنا الموحّد
---@param job table|nil
local function applyJob(job)
    local previousName = IC.job.name
    local previousDuty = IC.job.onduty
    local previousGrade = IC.job.grade

    if type(job) ~= 'table' or job.name ~= Config.Job.name then
        IC.job = { name = nil, grade = 0, onduty = false, label = nil }
    else
        local grade = 0
        if type(job.grade) == 'table' then
            grade = tonumber(job.grade.level) or 0            -- QB / Qbox
        else
            grade = tonumber(job.grade) or tonumber(job.grade_level) or 0  -- ESX
        end

        local onduty = job.onduty
        if onduty == nil then onduty = true end               -- ESX ما عنده دوام

        IC.job = {
            name = job.name,
            grade = grade,
            onduty = onduty == true,
            label = job.label or Config.Job.label,
        }
    end

    if previousName ~= IC.job.name
        or previousDuty ~= IC.job.onduty
        or previousGrade ~= IC.job.grade then
        IC.debug('job changed → name=%s grade=%s duty=%s',
            tostring(IC.job.name), tostring(IC.job.grade), tostring(IC.job.onduty))
        TriggerEvent('icecream:client:jobChanged', IC.job)
    end
end

---يحمّل بيانات الوظيفة الحالية من الفريمويرك
function IC.refreshJob()
    if IC.framework == 'qbx' then
        local data = exports.qbx_core:GetPlayerData()
        applyJob(data and data.job)
    elseif IC.framework == 'qb' then
        if not frameworkObject then
            frameworkObject = exports['qb-core']:GetCoreObject()
        end
        local data = frameworkObject.Functions.GetPlayerData()
        applyJob(data and data.job)
    elseif IC.framework == 'esx' then
        if not frameworkObject then
            frameworkObject = exports['es_extended']:getSharedObject()
        end
        local data = frameworkObject.GetPlayerData()
        applyJob(data and data.job)
    else
        -- standalone: السيرفر هو مصدر الحقيقة، يرسل لنا الحالة
        lib.callback('icecream:server:getJob', false, function(job)
            applyJob(job)
        end)
    end
end

---هل اللاعب موظف في المحل؟
---@return boolean
function IC.isEmployee()
    return IC.job.name == Config.Job.name
end

---هل يقدر يشتغل الآن؟ (موظف + على الدوام لو الدوام مطلوب)
---@return boolean
function IC.isWorking()
    if not IC.isEmployee() then return false end
    if Config.RequireDuty and not IC.job.onduty then return false end
    return true
end

---هل عنده صلاحية معينة الآن؟
---@param permission string
---@return boolean
function IC.hasPermission(permission)
    if not IC.isWorking() then return false end
    return IC.can(IC.job.grade, permission)
end

---يتحقق ويعرض الإشعار المناسب. يرجّع true لو مسموح.
---@param permission? string
---@return boolean
function IC.checkAccess(permission)
    if not IC.isEmployee() then
        IC.notify(L('not_employee'), 'error')
        return false
    end
    if Config.RequireDuty and not IC.job.onduty then
        IC.notify(L('not_on_duty'), 'error')
        return false
    end
    if permission and not IC.can(IC.job.grade, permission) then
        IC.notify(L('no_permission'), 'error')
        return false
    end
    return true
end

-- ────────────────────────────────────────────────────────────
-- الحقيبة — عدّ العناصر على العميل (للعرض فقط، السيرفر يعيد التحقق)
-- ────────────────────────────────────────────────────────────

---عدد نسخ عنصر في حقيبة اللاعب (تقديري — للعرض فقط)
---@param item string
---@return number
function IC.getItemCount(item)
    if IC.inventory == 'ox' then
        return exports.ox_inventory:Search('count', item) or 0
    elseif IC.inventory == 'qb' then
        if not frameworkObject and IC.framework == 'qb' then
            frameworkObject = exports['qb-core']:GetCoreObject()
        end
        local data = IC.framework == 'qbx' and exports.qbx_core:GetPlayerData()
            or (frameworkObject and frameworkObject.Functions.GetPlayerData())
        local items = data and data.items
        if type(items) ~= 'table' then return 0 end
        local total = 0
        for _, slot in pairs(items) do
            if slot and slot.name == item then total = total + (slot.amount or slot.count or 0) end
        end
        return total
    end
    return 0
end

---عدد العناصر مع دعم الوايلدكارد (ic_scoop_any)
---@param item string
---@return number
function IC.countWithWildcard(item)
    local total = 0
    for _, name in ipairs(IC.expandItem(item)) do
        total = total + IC.getItemCount(name)
    end
    return total
end

-- ────────────────────────────────────────────────────────────
-- الأنيميشن
-- ────────────────────────────────────────────────────────────

---@param dict string
---@return boolean
function IC.loadAnimDict(dict)
    if not dict or HasAnimDictLoaded(dict) then return dict ~= nil end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then
            IC.warn('تعذّر تحميل الأنيميشن: %s', dict)
            return false
        end
        Wait(10)
    end
    return true
end

---@param model string|number
---@return number|nil hash
function IC.loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) then
        IC.warn('موديل غير موجود: %s', tostring(model))
        return nil
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            IC.warn('انتهت مهلة تحميل الموديل: %s', tostring(model))
            return nil
        end
        Wait(10)
    end
    return hash
end

-- ────────────────────────────────────────────────────────────
-- التارجت — غلاف موحّد لـ ox_target و qb-target
-- ────────────────────────────────────────────────────────────

---يضيف منطقة صندوقية للتفاعل
---@param data { coords: vector3, size: vector3, rotation: number, name: string, options: table }
---@return any id
function IC.addBoxZone(data)
    if IC.targetSystem == 'ox' then
        return exports.ox_target:addBoxZone({
            coords = data.coords,
            size = data.size,
            rotation = data.rotation or 0.0,
            name = data.name,
            debug = Config.DebugZones,
            drawSprite = data.drawSprite ~= false,
            options = data.options,
        })
    end

    -- qb-target: يحتاج شكل مختلف للخيارات
    local qbOptions = {}
    for i = 1, #data.options do
        local opt = data.options[i]
        qbOptions[i] = {
            label = opt.label,
            icon = opt.icon and ('fas fa-' .. opt.icon) or 'fas fa-ice-cream',
            action = opt.onSelect,
            canInteract = opt.canInteract,
        }
    end
    exports['qb-target']:AddBoxZone(data.name, data.coords, data.size.x, data.size.y, {
        name = data.name,
        heading = data.rotation or 0.0,
        debugPoly = Config.DebugZones,
        minZ = data.coords.z - (data.size.z / 2),
        maxZ = data.coords.z + (data.size.z / 2),
    }, {
        options = qbOptions,
        distance = data.options[1] and data.options[1].distance or 2.0,
    })
    return data.name
end

---يحذف منطقة تفاعل
---@param id any
function IC.removeZone(id)
    if not id then return end
    if IC.targetSystem == 'ox' then
        exports.ox_target:removeZone(id)
    else
        exports['qb-target']:RemoveZone(id)
    end
end

-- ────────────────────────────────────────────────────────────
-- الاشتراك في أحداث الفريمويرك
-- ────────────────────────────────────────────────────────────

local function onPlayerLoaded()
    IC.loaded = true
    IC.refreshJob()
    TriggerEvent('icecream:client:playerLoaded')
end

local function onPlayerUnloaded()
    IC.loaded = false
    applyJob(nil)
    TriggerEvent('icecream:client:playerUnloaded')
end

if IC.framework == 'qbx' or IC.framework == 'qb' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', onPlayerLoaded)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', onPlayerUnloaded)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) applyJob(job) end)
    RegisterNetEvent('QBCore:Client:SetDuty', function() IC.refreshJob() end)
    RegisterNetEvent('qbx_core:client:onJobUpdate', function(job) applyJob(job) end)
    RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
        applyJob(data and data.job)
    end)
elseif IC.framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function(xPlayer)
        frameworkObject = frameworkObject or exports['es_extended']:getSharedObject()
        IC.loaded = true
        applyJob(xPlayer and xPlayer.job)
        TriggerEvent('icecream:client:playerLoaded')
    end)
    RegisterNetEvent('esx:onPlayerLogout', onPlayerUnloaded)
    RegisterNetEvent('esx:setJob', function(job) applyJob(job) end)
else
    RegisterNetEvent('icecream:client:setJob', function(job) applyJob(job) end)
end

-- الدوام يُدار عندنا في الوضع standalone وكذلك كإشعار مؤكَّد من السيرفر
RegisterNetEvent('icecream:client:setDuty', function(onduty)
    if IC.framework == 'standalone' then
        IC.job.onduty = onduty == true
        TriggerEvent('icecream:client:jobChanged', IC.job)
    else
        IC.refreshJob()
    end
end)

CreateThread(function()
    Wait(500)
    -- عند إعادة تشغيل المورد واللاعب أصلًا داخل السيرفر
    if IC.framework == 'standalone' or LocalPlayer.state.isLoggedIn ~= false then
        onPlayerLoaded()
    end
end)
