---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — جسر السيرفر
    -------------------------------
    كل تعامل مع الفريمويرك والحقيبة والفلوس يمر من هنا.
    بقية ملفات server/ تستخدم IC.* فقط.
]]

IC = IC or {}

local frameworkObject

-- تخزين الوظيفة في الوضع standalone (في الذاكرة + قاعدة البيانات عبر server/db.lua)
IC.standaloneJobs = {}   -- [citizenid] = { grade = n }
IC.dutyState = {}        -- [src] = boolean   (يُستخدم في standalone و ESX)

-- ────────────────────────────────────────────────────────────
-- تهيئة كائن الفريمويرك
-- ────────────────────────────────────────────────────────────
CreateThread(function()
    if IC.framework == 'qb' then
        frameworkObject = exports['qb-core']:GetCoreObject()
    elseif IC.framework == 'esx' then
        frameworkObject = exports['es_extended']:getSharedObject()
    end
end)

-- ────────────────────────────────────────────────────────────
-- بيانات اللاعب — الشكل الموحّد
--   { source, citizenid, name, job = { name, grade, onduty } }
-- ────────────────────────────────────────────────────────────

---@param src number
---@return table|nil
function IC.getPlayer(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    if IC.framework == 'qbx' then
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
            _raw = player,
        }
    elseif IC.framework == 'qb' then
        if not frameworkObject then frameworkObject = exports['qb-core']:GetCoreObject() end
        local player = frameworkObject.Functions.GetPlayer(src)
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
            _raw = player,
        }
    elseif IC.framework == 'esx' then
        if not frameworkObject then frameworkObject = exports['es_extended']:getSharedObject() end
        local xPlayer = frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return nil end
        local job = xPlayer.getJob()
        return {
            source = src,
            citizenid = xPlayer.identifier,
            name = xPlayer.getName(),
            job = {
                name = job.name,
                grade = tonumber(job.grade) or 0,
                -- ESX ما عنده دوام: نديره بأنفسنا
                onduty = IC.dutyState[src] ~= false,
            },
            _raw = xPlayer,
        }
    end

    -- standalone
    local citizenid = IC.getIdentifier(src)
    if not citizenid then return nil end
    local stored = IC.standaloneJobs[citizenid]
    return {
        source = src,
        citizenid = citizenid,
        name = GetPlayerName(src) or ('Player %s'):format(src),
        job = {
            name = stored and Config.Job.name or nil,
            grade = stored and stored.grade or 0,
            onduty = IC.dutyState[src] == true,
        },
    }
end

---معرّف اللاعب الثابت (license) — يُستخدم في الوضع standalone
---@param src number
---@return string|nil
function IC.getIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    local fallback = GetPlayerIdentifier(src, 0)
    return fallback
end

---@param citizenid string
---@return number|nil source
function IC.getSourceByCitizenId(citizenid)
    if not citizenid then return nil end
    for _, src in ipairs(GetPlayers()) do
        local player = IC.getPlayer(tonumber(src))
        if player and player.citizenid == citizenid then
            return player.source
        end
    end
    return nil
end

-- ────────────────────────────────────────────────────────────
-- التحقق من الصلاحية — البوابة الأمنية الرئيسية
-- ────────────────────────────────────────────────────────────

---يتحقق أن اللاعب موظف، على الدوام، ويملك الصلاحية المطلوبة
---@param src number
---@param permission? string
---@return table|nil player, string|nil reason
function IC.validateWorker(src, permission)
    local player = IC.getPlayer(src)
    if not player then return nil, 'not_employee' end
    if player.job.name ~= Config.Job.name then return nil, 'not_employee' end
    if Config.RequireDuty and not player.job.onduty then return nil, 'not_on_duty' end
    if permission and not IC.can(player.job.grade, permission) then
        return nil, 'no_permission'
    end
    return player, nil
end

---يتحقق أن اللاعب فعلًا قريب من إحداثيات (مضاد للغش عن بُعد)
---@param src number
---@param coords vector3
---@param maxDistance number
---@return boolean
function IC.isNear(src, coords, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    return #(pos - coords) <= (maxDistance or 5.0)
end

-- حد المعدّل: يمنع رشّ الأحداث السيرفرية
local rateLimits = {}   -- [src] = { [key] = lastTimestamp }

---@param src number
---@param key string
---@param cooldownMs number
---@return boolean allowed
function IC.rateLimit(src, key, cooldownMs)
    local now = GetGameTimer()
    local bucket = rateLimits[src]
    if not bucket then
        bucket = {}
        rateLimits[src] = bucket
    end
    local last = bucket[key]
    if last and (now - last) < cooldownMs then return false end
    bucket[key] = now
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    rateLimits[src] = nil
    IC.dutyState[src] = nil
end)

-- ────────────────────────────────────────────────────────────
-- الفلوس
-- ────────────────────────────────────────────────────────────

---@param src number
---@param account 'cash'|'bank'
---@param amount number
---@param reason? string
---@return boolean
function IC.addMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    reason = reason or 'icecream'

    if IC.framework == 'qbx' then
        return exports.qbx_core:AddMoney(src, account, amount, reason) == true
    elseif IC.framework == 'qb' then
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.AddMoney(account, amount, reason) == true
    elseif IC.framework == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return false end
        if account == 'cash' then xPlayer.addMoney(amount, reason)
        else xPlayer.addAccountMoney('bank', amount, reason) end
        return true
    end

    -- standalone: بلا نظام فلوس — نبلّغ العميل فقط
    TriggerClientEvent('icecream:client:moneyChanged', src, account, amount, reason)
    return true
end

---@param src number
---@param account 'cash'|'bank'
---@param amount number
---@param reason? string
---@return boolean
function IC.removeMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    reason = reason or 'icecream'

    if IC.framework == 'qbx' then
        return exports.qbx_core:RemoveMoney(src, account, amount, reason) == true
    elseif IC.framework == 'qb' then
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.RemoveMoney(account, amount, reason) == true
    elseif IC.framework == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
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

    TriggerClientEvent('icecream:client:moneyChanged', src, account, -amount, reason)
    return true
end

---@param src number
---@param account 'cash'|'bank'
---@return number
function IC.getMoney(src, account)
    if IC.framework == 'qbx' then
        return tonumber(exports.qbx_core:GetMoney(src, account)) or 0
    elseif IC.framework == 'qb' then
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return 0 end
        return tonumber(player.PlayerData.money[account]) or 0
    elseif IC.framework == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return 0 end
        if account == 'cash' then return xPlayer.getMoney() end
        local acc = xPlayer.getAccount('bank')
        return acc and acc.money or 0
    end
    return 0
end

-- ────────────────────────────────────────────────────────────
-- الحقيبة
-- ────────────────────────────────────────────────────────────

---@param src number
---@param item string
---@param count number
---@param metadata? table
---@return boolean
function IC.addItem(src, item, count, metadata)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false end

    if IC.inventory == 'ox' then
        return exports.ox_inventory:AddItem(src, item, count, metadata) == true
    elseif IC.inventory == 'qb' then
        if IC.framework == 'qbx' then
            local player = exports.qbx_core:GetPlayer(src)
            if not player then return false end
            return exports['qb-inventory']:AddItem(src, item, count, false, metadata) == true
        end
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.AddItem(item, count, false, metadata) == true
    elseif IC.inventory == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return false end
        if not xPlayer.canCarryItem(item, count) then return false end
        xPlayer.addInventoryItem(item, count)
        return true
    end
    return true  -- 'none': بلا حقيبة، نعتبرها نجحت
end

---@param src number
---@param item string
---@param count number
---@param metadata? table
---@return boolean
function IC.removeItem(src, item, count, metadata)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false end

    if IC.inventory == 'ox' then
        return exports.ox_inventory:RemoveItem(src, item, count, metadata) == true
    elseif IC.inventory == 'qb' then
        if IC.framework == 'qbx' then
            return exports['qb-inventory']:RemoveItem(src, item, count, nil, 'icecream') == true
        end
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.RemoveItem(item, count) == true
    elseif IC.inventory == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return false end
        if xPlayer.getInventoryItem(item).count < count then return false end
        xPlayer.removeInventoryItem(item, count)
        return true
    end
    return true
end

---@param src number
---@param item string
---@return number
function IC.getItemCount(src, item)
    if IC.inventory == 'ox' then
        return tonumber(exports.ox_inventory:GetItemCount(src, item)) or 0
    elseif IC.inventory == 'qb' then
        local items
        if IC.framework == 'qbx' then
            local player = exports.qbx_core:GetPlayer(src)
            items = player and player.PlayerData.items
        else
            local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
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
    elseif IC.inventory == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
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
function IC.canCarry(src, item, count)
    if IC.inventory == 'ox' then
        return exports.ox_inventory:CanCarryItem(src, item, count) == true
    elseif IC.inventory == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        return xPlayer and xPlayer.canCarryItem(item, count) or false
    elseif IC.inventory == 'qb' then
        if IC.framework == 'qbx' then
            local ok = exports['qb-inventory']:CanAddItem(src, item, count)
            return ok ~= false
        end
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        -- qb-inventory القديم ما عنده فحص موثوق؛ نسمح ونترك AddItem يفشل لو ما ينفع
        return true
    end
    return true
end

-- ────────────────────────────────────────────────────────────
-- المكوّنات مع دعم الوايلدكارد (ic_scoop_any)
-- ────────────────────────────────────────────────────────────

---يتحقق أن اللاعب يملك كل مكونات الوصفة (مضروبة في batch)
---@param src number
---@param ingredients table
---@param batch number
---@return boolean ok, table missing   -- missing = { {item=..., need=n, have=n} }
function IC.hasIngredients(src, ingredients, batch)
    batch = batch or 1
    local missing = {}

    -- نجمع العدّ لكل عنصر فعلي مرة واحدة لتفادي استعلامات مكررة
    local counts = {}
    local function countOf(name)
        if counts[name] == nil then counts[name] = IC.getItemCount(src, name) end
        return counts[name]
    end

    -- المكونات الصريحة أولًا، ثم الوايلدكارد — حتى لا يستهلك الوايلدكارد
    -- كرات مطلوبة صراحةً في نفس الوصفة.
    local reserved = {}
    local wildcardNeeds = {}

    for i = 1, #ingredients do
        local ing = ingredients[i]
        local need = ing.count * batch
        if ing.item == Recipes.ScoopWildcard then
            wildcardNeeds[#wildcardNeeds + 1] = { item = ing.item, need = need }
        else
            local have = countOf(ing.item) - (reserved[ing.item] or 0)
            if have < need then
                missing[#missing + 1] = { item = ing.item, need = need, have = math.max(have, 0) }
            else
                reserved[ing.item] = (reserved[ing.item] or 0) + need
            end
        end
    end

    for i = 1, #wildcardNeeds do
        local entry = wildcardNeeds[i]
        local available = 0
        for _, name in ipairs(Recipes.ScoopItems) do
            available = available + math.max(countOf(name) - (reserved[name] or 0), 0)
        end
        if available < entry.need then
            missing[#missing + 1] = { item = entry.item, need = entry.need, have = available }
        else
            -- نحجز من الأنواع بالترتيب
            local remaining = entry.need
            for _, name in ipairs(Recipes.ScoopItems) do
                if remaining <= 0 then break end
                local free = math.max(countOf(name) - (reserved[name] or 0), 0)
                local take = math.min(free, remaining)
                if take > 0 then
                    reserved[name] = (reserved[name] or 0) + take
                    remaining = remaining - take
                end
            end
        end
    end

    return #missing == 0, missing
end

---يخصم مكونات الوصفة. يُفترض أن IC.hasIngredients نجح قبلها مباشرة.
---@param src number
---@param ingredients table
---@param batch number
---@return boolean
function IC.consumeIngredients(src, ingredients, batch)
    batch = batch or 1
    -- نبني خطة الخصم أولًا، ثم ننفّذها — حتى لا نخصم نصف الوصفة عند الفشل
    local plan = {}

    for i = 1, #ingredients do
        local ing = ingredients[i]
        local need = ing.count * batch
        if ing.item == Recipes.ScoopWildcard then
            local remaining = need
            for _, name in ipairs(Recipes.ScoopItems) do
                if remaining <= 0 then break end
                local have = IC.getItemCount(src, name) - (plan[name] or 0)
                local take = math.min(math.max(have, 0), remaining)
                if take > 0 then
                    plan[name] = (plan[name] or 0) + take
                    remaining = remaining - take
                end
            end
            if remaining > 0 then return false end
        else
            plan[ing.item] = (plan[ing.item] or 0) + need
            if IC.getItemCount(src, ing.item) < plan[ing.item] then return false end
        end
    end

    for item, count in pairs(plan) do
        if not IC.removeItem(src, item, count) then
            IC.warn('فشل خصم %sx %s من اللاعب %s — قد تبقى مكونات مخصومة جزئيًا', count, item, src)
            return false
        end
    end
    return true
end

-- ────────────────────────────────────────────────────────────
-- الوظيفة والدوام
-- ────────────────────────────────────────────────────────────

---@param src number
---@param onduty boolean
---@return boolean
function IC.setDuty(src, onduty)
    onduty = onduty == true
    if IC.framework == 'qbx' then
        exports.qbx_core:SetJobDuty(src, onduty)
    elseif IC.framework == 'qb' then
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        player.Functions.SetJobDuty(onduty)
        TriggerClientEvent('QBCore:Client:SetDuty', src, onduty)
    else
        -- ESX و standalone: ندير الدوام بأنفسنا
        IC.dutyState[src] = onduty
    end
    TriggerClientEvent('icecream:client:setDuty', src, onduty)
    return true
end

---@param src number
---@param grade number
---@return boolean
function IC.setJob(src, grade)
    grade = math.floor(tonumber(grade) or 0)
    if IC.framework == 'qbx' then
        return exports.qbx_core:SetJob(src, Config.Job.name, grade) ~= false
    elseif IC.framework == 'qb' then
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.SetJob(Config.Job.name, grade) ~= false
    elseif IC.framework == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.setJob(Config.Job.name, grade)
        return true
    end

    local citizenid = IC.getIdentifier(src)
    if not citizenid then return false end
    IC.standaloneJobs[citizenid] = { grade = grade }
    TriggerClientEvent('icecream:client:setJob', src, {
        name = Config.Job.name, grade = grade, onduty = IC.dutyState[src] == true,
        label = Config.Job.label,
    })
    return true
end

---يفصل اللاعب من الوظيفة (يرجّعه لـ unemployed)
---@param src number
---@return boolean
function IC.removeJob(src)
    if IC.framework == 'qbx' then
        return exports.qbx_core:SetJob(src, 'unemployed', 0) ~= false
    elseif IC.framework == 'qb' then
        local player = frameworkObject and frameworkObject.Functions.GetPlayer(src)
        if not player then return false end
        return player.Functions.SetJob('unemployed', 0) ~= false
    elseif IC.framework == 'esx' then
        local xPlayer = frameworkObject and frameworkObject.GetPlayerFromId(src)
        if not xPlayer then return false end
        xPlayer.setJob('unemployed', 0)
        return true
    end

    local citizenid = IC.getIdentifier(src)
    if citizenid then IC.standaloneJobs[citizenid] = nil end
    IC.dutyState[src] = nil
    TriggerClientEvent('icecream:client:setJob', src, nil)
    return true
end

-- callback للوضع standalone: العميل يسأل عن وظيفته
lib.callback.register('icecream:server:getJob', function(source)
    local player = IC.getPlayer(source)
    return player and player.job or nil
end)
