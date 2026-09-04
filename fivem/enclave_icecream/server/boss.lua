---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — منيو البوس (سيرفري)
    ---------------------------------------
    كل إجراء هنا يتطلب صلاحية isBoss + وجود اللاعب في مكتب الإدارة.
    الحد الأعلى للترقية محكوم بـ Config.Job.maxPromoteGrade حتى لا يصنع البوس بوسات.
]]

IC = IC or {}

---تحديث رتبة موظف غير متصل في جدولنا (بلا لمس جداول الفريمويرك)
---@param citizenid string
---@param grade number
local function updateStoredGrade(citizenid, grade)
    if not IC.db.enabled then return end
    MySQL.update('UPDATE icecream_employees SET grade = ? WHERE citizenid = ?',
        { math.floor(grade), citizenid })
end

---بوابة البوس: تحقق موحّد لكل إجراءات هذا الملف
---@param src number
---@param branchId any
---@return table|nil player, table|nil branch
local function bossGate(src, branchId)
    local branch = IC.server.resolveBranch(branchId)
    if not branch then
        IC.logs.exploit(src, 'invalid_branch', tostring(branchId))
        return nil
    end
    local player = IC.server.gate(src, 'isBoss', branch.boss.coords, 5.0)
    if not player then return nil end
    return player, branch
end

-- ────────────────────────────────────────────────────────────
-- بيانات المنيو
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:getBossData', function(source, branchId)
    local player, branch = bossGate(source, branchId)
    if not player then return nil end

    local employees = IC.db.getEmployees(branch.id)

    -- من هو متصل الآن؟
    local online = {}
    for _, src in ipairs(GetPlayers()) do
        local p = IC.getPlayer(tonumber(src))
        if p and p.job.name == Config.Job.name then
            online[p.citizenid] = { source = p.source, onduty = p.job.onduty, grade = p.job.grade }
        end
    end

    for i = 1, #employees do
        local emp = employees[i]
        local live = online[emp.citizenid]
        emp.online = live ~= nil
        emp.onduty = live and live.onduty or false
        emp.source = live and live.source or nil
        if live then emp.grade = live.grade end
        emp.gradeLabel = IC.gradeInfo(emp.grade).label
    end

    return {
        balance = IC.society.getBalance(branch.id),
        employees = employees,
        stats = IC.db.getStats(branch.id),
        maxPromoteGrade = Config.Job.maxPromoteGrade,
        grades = Config.Job.grades,
    }
end)

-- ────────────────────────────────────────────────────────────
-- إيداع وسحب
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:bossDeposit', function(source, branchId, amount)
    local src = source
    if not IC.rateLimit(src, 'boss_money', 1500) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end

    local player, branch = bossGate(src, branchId)
    if not player then return false end

    local value = IC.toInt(amount, 1, 10000000)
    if not value then
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    if not IC.removeMoney(src, 'bank', value, 'icecream-deposit') then
        IC.server.notify(src, 'bill_no_money', 'error')
        return false
    end

    local balance = IC.society.add(branch.id, value)
    IC.logs.money(player, branch.id, 'deposit', value, balance)
    IC.server.notify(src, 'boss_deposited', 'success', IC.money(value))
    return balance
end)

lib.callback.register('icecream:server:bossWithdraw', function(source, branchId, amount)
    local src = source
    if not IC.rateLimit(src, 'boss_money', 1500) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end

    local player, branch = bossGate(src, branchId)
    if not player then return false end

    local value = IC.toInt(amount, 1, 10000000)
    if not value then
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    if not IC.society.canAfford(branch.id, value) then
        IC.server.notify(src, 'boss_insufficient', 'error')
        return false
    end

    local ok, balance = IC.society.take(branch.id, value)
    if not ok then
        IC.server.notify(src, 'boss_insufficient', 'error')
        return false
    end

    if not IC.addMoney(src, 'bank', value, 'icecream-withdraw') then
        -- فشل الإيداع للاعب: نرجّع المبلغ للشركة
        balance = IC.society.add(branch.id, value)
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    IC.logs.money(player, branch.id, 'withdraw', value, balance)
    IC.server.notify(src, 'boss_withdrew', 'success', IC.money(value))
    return balance
end)

-- ────────────────────────────────────────────────────────────
-- التوظيف
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:bossHire', function(source, branchId, targetId)
    local src = source
    local player, branch = bossGate(src, branchId)
    if not player then return false end

    local target = IC.toInt(targetId, 1)
    if not target or not GetPlayerName(target) then
        IC.server.notify(src, 'boss_player_offline', 'error')
        return false
    end

    local targetPlayer = IC.getPlayer(target)
    if not targetPlayer then
        IC.server.notify(src, 'boss_player_offline', 'error')
        return false
    end

    -- المستهدف لازم يكون قريب (توظيف وجهًا لوجه)
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if a == 0 or b == 0 or #(GetEntityCoords(a) - GetEntityCoords(b)) > 8.0 then
        IC.server.notify(src, 'bill_target_far', 'error')
        return false
    end

    local grade = Config.Job.hireGrade or 0
    if not IC.setJob(target, grade) then
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    IC.db.upsertEmployee(targetPlayer.citizenid, branch.id, targetPlayer.name, grade)
    IC.db.saveStandaloneJob(targetPlayer.citizenid, grade)
    IC.logs.employee(player, targetPlayer, branch.id, 'hire', IC.gradeInfo(grade).label)

    IC.server.notify(src, 'boss_hired', 'success', targetPlayer.name)
    IC.server.notify(target, 'boss_hired', 'success', targetPlayer.name)
    return true
end)

-- ────────────────────────────────────────────────────────────
-- الفصل
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:bossFire', function(source, branchId, citizenid)
    local src = source
    local player, branch = bossGate(src, branchId)
    if not player then return false end

    if type(citizenid) ~= 'string' or #citizenid == 0 or #citizenid > 64 then
        IC.logs.exploit(src, 'malformed_payload', 'fire')
        return false
    end

    if citizenid == player.citizenid then
        IC.server.notify(src, 'boss_cant_fire_self', 'error')
        return false
    end

    -- الموظف يجب أن يكون فعلًا في سجل هذا الفرع
    local employees = IC.db.getEmployees(branch.id)
    local record
    for i = 1, #employees do
        if employees[i].citizenid == citizenid then record = employees[i] break end
    end

    local targetSrc = IC.getSourceByCitizenId(citizenid)
    local targetPlayer = targetSrc and IC.getPlayer(targetSrc) or nil

    if not record and not targetPlayer then
        IC.server.notify(src, 'boss_player_offline', 'error')
        return false
    end

    local targetGrade = targetPlayer and targetPlayer.job.grade or (record and record.grade) or 0
    if IC.can(targetGrade, 'isBoss') then
        IC.server.notify(src, 'boss_cant_fire_boss', 'error')
        return false
    end

    if targetSrc then
        IC.removeJob(targetSrc)
        for _, set in pairs(IC.onDuty) do set[targetSrc] = nil end
    end

    IC.db.removeEmployee(citizenid)
    IC.db.saveStandaloneJob(citizenid, nil)
    IC.standaloneJobs[citizenid] = nil

    local name = (targetPlayer and targetPlayer.name) or (record and record.name) or citizenid
    IC.logs.employee(player, { name = name, citizenid = citizenid }, branch.id, 'fire', 'مفصول')
    IC.server.notify(src, 'boss_fired', 'success', name)
    return true
end)

-- ────────────────────────────────────────────────────────────
-- تغيير الرتبة
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:bossPromote', function(source, branchId, citizenid, grade)
    local src = source
    local player, branch = bossGate(src, branchId)
    if not player then return false end

    if type(citizenid) ~= 'string' or #citizenid == 0 or #citizenid > 64 then
        IC.logs.exploit(src, 'malformed_payload', 'promote')
        return false
    end

    local maxGrade = math.min(Config.Job.maxPromoteGrade, IC.maxGrade())
    local newGrade = IC.toInt(grade, 0, maxGrade)
    if not newGrade then
        IC.server.notify(src, 'boss_grade_too_high', 'error', IC.gradeInfo(maxGrade).label)
        return false
    end

    if citizenid == player.citizenid then
        IC.server.notify(src, 'no_permission', 'error')
        return false
    end

    local targetSrc = IC.getSourceByCitizenId(citizenid)
    if not targetSrc then
        -- غير متصل: نحدّث السجل فقط، وتُطبَّق عند دخوله (في الوضع standalone)
        IC.standaloneJobs[citizenid] = { grade = newGrade }
        IC.db.saveStandaloneJob(citizenid, newGrade)
        updateStoredGrade(citizenid, newGrade)
        IC.logs.employee(player, { name = citizenid, citizenid = citizenid }, branch.id,
            'promote', IC.gradeInfo(newGrade).label)
        IC.server.notify(src, 'boss_promoted', 'success', citizenid, IC.gradeInfo(newGrade).label)
        return true
    end

    local targetPlayer = IC.getPlayer(targetSrc)
    if not targetPlayer then
        IC.server.notify(src, 'boss_player_offline', 'error')
        return false
    end

    if IC.can(targetPlayer.job.grade, 'isBoss') then
        IC.server.notify(src, 'no_permission', 'error')
        return false
    end

    if not IC.setJob(targetSrc, newGrade) then
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    IC.db.upsertEmployee(citizenid, branch.id, targetPlayer.name, newGrade)
    IC.db.saveStandaloneJob(citizenid, newGrade)
    IC.logs.employee(player, targetPlayer, branch.id, 'promote', IC.gradeInfo(newGrade).label)

    IC.server.notify(src, 'boss_promoted', 'success', targetPlayer.name, IC.gradeInfo(newGrade).label)
    IC.server.notify(targetSrc, 'boss_promoted', 'inform', targetPlayer.name, IC.gradeInfo(newGrade).label)
    return true
end)
