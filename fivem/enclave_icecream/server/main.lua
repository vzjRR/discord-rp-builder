---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — نواة السيرفر
    --------------------------------
    التهيئة، الدوام، الفريزرات، التحقق المشترك، والأوامر الإدارية.
]]

IC = IC or {}
IC.server = IC.server or {}

-- الموظفون على الدوام حاليًا: [branchId] = { [src] = true }
IC.onDuty = {}

-- ────────────────────────────────────────────────────────────
-- أدوات مشتركة
-- ────────────────────────────────────────────────────────────

---يرسل إشعارًا للاعب عبر مفتاح ترجمة
---@param src number
---@param key string
---@param kind? string
function IC.server.notify(src, key, kind, ...)
    TriggerClientEvent('icecream:client:notify', src, key, kind or 'inform', { ... })
end

---يتحقق أن معرّف الفرع صالح ويرجّع تعريفه
---@param branchId any
---@return table|nil
function IC.server.resolveBranch(branchId)
    if type(branchId) ~= 'string' then return nil end
    return Locations.getBranch(branchId)
end

---تحقق كامل: موظف + دوام + صلاحية + قرب من نقطة
---يسجّل محاولة غش تلقائيًا عند فشل فحص المسافة.
---@param src number
---@param permission string|nil
---@param coords vector3|nil
---@param maxDistance number|nil
---@return table|nil player
function IC.server.gate(src, permission, coords, maxDistance)
    local player, reason = IC.validateWorker(src, permission)
    if not player then
        IC.server.notify(src, reason or 'no_permission', 'error')
        return nil
    end
    if coords and not IC.isNear(src, coords, maxDistance or 5.0) then
        IC.logs.exploit(src, 'distance_check', ('المسافة أكبر من %s'):format(maxDistance or 5.0))
        IC.server.notify(src, 'too_far', 'error')
        return nil
    end
    return player
end

---عدد الموظفين على الدوام في فرع
---@param branchId string
---@return number
function IC.server.countOnDuty(branchId)
    local set = IC.onDuty[branchId]
    if not set then return 0 end
    local count = 0
    for src in pairs(set) do
        if GetPlayerName(src) then count = count + 1 else set[src] = nil end
    end
    return count
end

---قائمة مصادر الموظفين على الدوام
---@param branchId string
---@return number[]
function IC.server.getOnDuty(branchId)
    local out = {}
    local set = IC.onDuty[branchId]
    if not set then return out end
    for src in pairs(set) do
        if GetPlayerName(src) then out[#out + 1] = src else set[src] = nil end
    end
    return out
end

---يبثّ حدثًا لكل من على الدوام في فرع
---@param branchId string
---@param event string
function IC.server.broadcast(branchId, event, ...)
    for _, src in ipairs(IC.server.getOnDuty(branchId)) do
        TriggerClientEvent(event, src, ...)
    end
end

-- ────────────────────────────────────────────────────────────
-- الدوام
-- ────────────────────────────────────────────────────────────

local function trackDuty(src, branchId, onduty)
    for id, set in pairs(IC.onDuty) do
        if id ~= branchId then set[src] = nil end
    end
    IC.onDuty[branchId] = IC.onDuty[branchId] or {}
    IC.onDuty[branchId][src] = onduty and true or nil
end

RegisterNetEvent('icecream:server:toggleDuty', function(branchId)
    local src = source
    if not IC.rateLimit(src, 'duty', 1500) then return end

    local branch = IC.server.resolveBranch(branchId)
    if not branch then
        IC.logs.exploit(src, 'invalid_branch', tostring(branchId))
        return
    end

    local player = IC.getPlayer(src)
    if not player or player.job.name ~= Config.Job.name then
        IC.server.notify(src, 'not_employee', 'error')
        return
    end

    if not IC.isNear(src, branch.duty.coords, 5.0) then
        IC.logs.exploit(src, 'distance_check', 'duty point')
        IC.server.notify(src, 'too_far', 'error')
        return
    end

    local newDuty = not player.job.onduty

    -- منع الخروج من الدوام وهو حامل منتجات المحل
    if not newDuty and Config.BlockOffDutyWithStock then
        for item in pairs(Recipes.byResult) do
            if IC.getItemCount(src, item) > 0 then
                IC.server.notify(src, 'duty_blocked_stock', 'error')
                return
            end
        end
    end

    IC.setDuty(src, newDuty)
    trackDuty(src, branchId, newDuty)

    -- سجّل الموظف في قاعدة البيانات عند أول دخول دوام
    if newDuty then
        IC.db.upsertEmployee(player.citizenid, branchId, player.name, player.job.grade)
    end

    IC.server.notify(src, newDuty and 'duty_on' or 'duty_off', 'success')
    IC.debug('%s (%s) duty=%s @ %s', player.name, src, tostring(newDuty), branchId)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, set in pairs(IC.onDuty) do set[src] = nil end
end)

-- ────────────────────────────────────────────────────────────
-- الفريزرات (ستاشات ox_inventory)
-- ────────────────────────────────────────────────────────────

local function registerFreezers()
    if IC.inventory ~= 'ox' then return end
    for i = 1, #Locations.Branches do
        local branch = Locations.Branches[i]
        if branch.freezer then
            exports.ox_inventory:RegisterStash(
                ('icecream_freezer_%s'):format(branch.id),
                L('freezer_label', branch.label),
                branch.freezer.slots or 50,
                branch.freezer.maxWeight or 150000,
                false,                       -- owner: مشترك بين كل الموظفين
                { [Config.Job.name] = 0 },   -- groups: الوظيفة فقط
                branch.freezer.coords
            )
        end
    end
    IC.debug('سجّلت %s فريزر', #Locations.Branches)
end

-- ────────────────────────────────────────────────────────────
-- الذوبان: حساب نضارة المنتج وسحبه من الحقيبة
-- ────────────────────────────────────────────────────────────

---نسبة القيمة المتبقية لمنتج حسب وقت صنعه (1.0 = طازج تمامًا)
---@param metadata table|nil
---@return number ratio, boolean ruined
function IC.server.freshness(metadata)
    if not Config.Melting.enabled then return 1.0, false end
    local madeAt = metadata and tonumber(metadata.madeAt)
    if not madeAt then return 1.0, false end

    local ageMinutes = (os.time() - madeAt) / 60
    if ageMinutes <= Config.Melting.freshMinutes then return 1.0, false end

    if Config.Melting.ruinMinutes > 0 and ageMinutes >= Config.Melting.ruinMinutes then
        return 0.0, true
    end

    local span = math.max((Config.Melting.ruinMinutes > 0 and Config.Melting.ruinMinutes
        or (Config.Melting.freshMinutes * 3)) - Config.Melting.freshMinutes, 1)
    local decayed = (ageMinutes - Config.Melting.freshMinutes) / span
    local ratio = 1.0 - decayed * (1.0 - Config.Melting.minValueRatio)
    return math.max(ratio, Config.Melting.minValueRatio), false
end

---يسحب منتجًا من حقيبة اللاعب مفضّلًا الأطزج، ويرجّع متوسط النضارة
---@param src number
---@param item string
---@param count number
---@return boolean ok, number ratio
function IC.server.takeProduct(src, item, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false, 0 end

    if IC.inventory ~= 'ox' or not Config.Melting.enabled or not Recipes.isPerishable(item) then
        if IC.getItemCount(src, item) < count then return false, 0 end
        return IC.removeItem(src, item, count), 1.0
    end

    local slots = exports.ox_inventory:Search(src, 'slots', item)
    if type(slots) ~= 'table' then return false, 0 end

    -- الأطزج أولًا (madeAt أكبر = أحدث)؛ ما بلا ميتاداتا يُعتبر طازجًا
    table.sort(slots, function(a, b)
        local am = (a.metadata and tonumber(a.metadata.madeAt)) or math.huge
        local bm = (b.metadata and tonumber(b.metadata.madeAt)) or math.huge
        return am > bm
    end)

    local plan, remaining, weighted = {}, count, 0.0
    for i = 1, #slots do
        if remaining <= 0 then break end
        local slot = slots[i]
        local available = math.floor(tonumber(slot.count) or 0)
        if available > 0 then
            local ratio, ruined = IC.server.freshness(slot.metadata)
            if not ruined then
                local take = math.min(available, remaining)
                plan[#plan + 1] = { slot = slot.slot, count = take, metadata = slot.metadata }
                weighted = weighted + ratio * take
                remaining = remaining - take
            end
        end
    end

    if remaining > 0 then return false, 0 end

    for i = 1, #plan do
        local entry = plan[i]
        if not exports.ox_inventory:RemoveItem(src, item, entry.count, nil, entry.slot) then
            IC.warn('فشل سحب %sx %s من الخانة %s للاعب %s', entry.count, item, entry.slot, src)
            return false, 0
        end
    end

    return true, weighted / count
end

-- ────────────────────────────────────────────────────────────
-- Callbacks عامة
-- ────────────────────────────────────────────────────────────

-- يرجّع الحالة الحالية للفرع (تُستخدم في القوائم على العميل)
lib.callback.register('icecream:server:getBranchState', function(source, branchId)
    local branch = IC.server.resolveBranch(branchId)
    if not branch then return nil end
    local player = IC.getPlayer(source)
    if not player or player.job.name ~= Config.Job.name then return nil end

    return {
        balance = IC.society.getBalance(branchId),
        onDuty = IC.server.countOnDuty(branchId),
        pendingOrders = IC.orders and IC.orders.countPending(branchId) or 0,
        grade = player.job.grade,
        isBoss = IC.can(player.job.grade, 'isBoss'),
    }
end)

-- إحصائيات الفرع
lib.callback.register('icecream:server:getStats', function(source, branchId)
    local player = IC.server.gate(source, nil, nil, nil)
    if not player then return nil end
    local branch = IC.server.resolveBranch(branchId)
    if not branch then return nil end

    local stats = IC.db.getStats(branchId)
    stats.yours = IC.db.getEmployeeToday(branchId, player.citizenid)
    stats.balance = IC.society.getBalance(branchId)
    return stats
end)

-- ────────────────────────────────────────────────────────────
-- الأوامر الإدارية
-- ────────────────────────────────────────────────────────────

-- أداة المطوّر: نسخ الإحداثيات بصيغة جاهزة للصق في config/locations.lua
lib.addCommand('ic_coords', {
    help = 'يطبع إحداثياتك بصيغة جاهزة لـ config/locations.lua',
    restricted = 'group.admin',
}, function(source)
    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local line = ('vec3(%.2f, %.2f, %.2f)  |  vec4(%.2f, %.2f, %.2f, %.1f)  |  rotation = %.1f')
        :format(coords.x, coords.y, coords.z, coords.x, coords.y, coords.z, heading, heading)
    print(('[%s] %s'):format(IC.resource, line))
    TriggerClientEvent('chat:addMessage', source, {
        color = { 120, 220, 255 },
        multiline = true,
        args = { 'icecream', line },
    })
end)

-- أداة الأدمن: تعيين وظيفة المحل للاعب (مفيدة في الوضع standalone)
lib.addCommand('ic_setjob', {
    help = 'يعيّن وظيفة محل المثلجات للاعب',
    params = {
        { name = 'id', type = 'playerId', help = 'رقم اللاعب' },
        { name = 'grade', type = 'number', help = 'الرتبة (0-' .. IC.maxGrade() .. ')' },
    },
    restricted = 'group.admin',
}, function(source, args)
    local grade = IC.toInt(args.grade, 0, IC.maxGrade())
    if not grade then
        IC.server.notify(source, 'error_generic', 'error')
        return
    end
    if IC.setJob(args.id, grade) then
        local target = IC.getPlayer(args.id)
        if target then
            IC.db.upsertEmployee(target.citizenid, Locations.Branches[1].id, target.name, grade)
            IC.db.saveStandaloneJob(target.citizenid, grade)
        end
        IC.server.notify(source, 'boss_promoted', 'success',
            target and target.name or args.id, IC.gradeInfo(grade).label)
    else
        IC.server.notify(source, 'error_generic', 'error')
    end
end)

-- ────────────────────────────────────────────────────────────
-- التحقق من صحة الإعدادات عند التشغيل
-- ────────────────────────────────────────────────────────────

local function validateConfig()
    local problems = {}

    local shares = Config.Economy.societyShare + Config.Economy.employeeTip
    if math.abs(shares - 1.0) > 0.001 then
        problems[#problems + 1] = ('societyShare + employeeTip = %.2f (يفترض 1.0)'):format(shares)
    end

    if #Locations.Branches == 0 then
        problems[#problems + 1] = 'ما في أي فرع معرّف في config/locations.lua'
    end

    -- كل محطة في المواقع لها وصفات، وكل وصفة لها محطة موجودة
    for i = 1, #Locations.Branches do
        local branch = Locations.Branches[i]
        for _, station in ipairs(branch.stations or {}) do
            if #Recipes.forStation(station.id) == 0 then
                problems[#problems + 1] = ('المحطة "%s" في الفرع "%s" ما لها وصفات'):format(station.id, branch.id)
            end
        end
    end

    -- كل مكوّن في الوصفات إمّا مادة خام في الكتالوج، أو منتج من وصفة أخرى، أو الوايلدكارد
    local known = {}
    for _, entry in ipairs(Config.Supply.catalog) do known[entry.item] = true end
    for item in pairs(Recipes.byResult) do known[item] = true end
    known[Recipes.ScoopWildcard] = true

    for id, recipe in pairs(Recipes.byId) do
        for _, ing in ipairs(recipe.ingredients) do
            if not known[ing.item] then
                problems[#problems + 1] = ('الوصفة "%s" تحتاج "%s" وهو غير موجود في الكتالوج ولا ينتج من أي وصفة'):format(id, ing.item)
            end
        end
    end

    -- كل منتج في قائمة الطلبات قابل للصنع
    for _, entry in ipairs(Recipes.OrderPool) do
        if not Recipes.byResult[entry.item] then
            problems[#problems + 1] = ('منتج الطلبات "%s" ما ينتج من أي وصفة'):format(entry.item)
        end
    end

    if #problems > 0 then
        IC.warn('وُجدت %s مشكلة في الإعدادات:', #problems)
        for i = 1, #problems do IC.print('  %s) %s', i, problems[i]) end
    else
        IC.debug('الإعدادات سليمة.')
    end
    return #problems == 0
end

-- ────────────────────────────────────────────────────────────
-- الإقلاع
-- ────────────────────────────────────────────────────────────

CreateThread(function()
    Wait(1000)  -- ننتظر oxmysql والفريمويرك

    IC.db.migrate()
    IC.db.loadStandaloneJobs()
    IC.society.init()
    registerFreezers()
    validateConfig()

    IC.print('^2جاهز^7 — framework=%s inventory=%s target=%s db=%s branches=%s',
        IC.framework, IC.inventory, IC.targetSystem,
        tostring(IC.db.enabled), #Locations.Branches)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= IC.resource then return end
    IC.society.saveAll()
end)

-- ────────────────────────────────────────────────────────────
-- تكامل ox_inventory: يُستدعى عند استخدام (أكل) أحد منتجات المحل
-- مرتبط بـ  server = { export = 'enclave_icecream.consume' }  في items.lua
-- ────────────────────────────────────────────────────────────
exports('consume', function(event, item, inventory, slot, data)
    if event ~= 'usingItem' then return end

    -- المنتج الذائب تمامًا لا يُؤكل
    local _, ruined = IC.server.freshness(slot and slot.metadata)
    if ruined then
        IC.server.notify(inventory.id or inventory, 'melt_ruined', 'error')
        return false
    end
end)
