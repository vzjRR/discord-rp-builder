---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Management actions.

    Every action here requires the `manage` permission AND presence in the
    office, so a manager cannot run the business from across the map.
]]

MN = MN or {}

---@param src number
---@return table|nil
local function manager(src)
    return MN.gate(src, MN.PERM.MANAGE, Locations.shop.office.coords, 5.0)
end

lib.callback.register('mangonazlet:server:management', function(source)
    -- Reads the staff table and the statistics aggregates.
    if not MN.rateLimit(source, 'management', 1500) then return nil end

    local player = manager(source)
    if not player then return nil end

    local staff = MN.db.staff(Locations.shop.id)

    -- Merge in who is online right now.
    local online = {}
    for _, id in ipairs(GetPlayers()) do
        local other = MN.getPlayer(tonumber(id))
        if other and other.job.name == Permissions.job then
            online[other.citizenid] = other
        end
    end

    for i = 1, #staff do
        local record = staff[i]
        local live = online[record.citizenid]
        record.online = live ~= nil
        record.onduty = live and live.job.onduty or false
        if live then record.grade = live.job.grade end
        record.gradeLabel = Permissions.gradeLabel(record.grade)
        record.isOwner = Permissions.isOwner(record.grade)
    end

    local grades = {}
    for _, entry in ipairs(Permissions.ordered()) do
        if entry.level <= Permissions.maxAssignable then
            grades[#grades + 1] = { level = entry.level, label = Permissions.gradeLabel(entry.level) }
        end
    end

    return {
        balance = MN.business.balance(),
        staff = staff,
        stats = MN.db.stats(Locations.shop.id),
        grades = grades,
        maxAssignable = Permissions.maxAssignable,
    }
end)

lib.callback.register('mangonazlet:server:deposit', function(source, amount)
    local src = source
    if not MN.rateLimit(src, 'manage_money', 1500) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = manager(src)
    if not player then return false end

    local value = MN.int(amount, 1, 10000000)
    if not value then return false end

    if not MN.removeMoney(src, 'bank', value, 'mangonazlet:deposit') then
        MN.notify(src, 'no_money', 'error')
        return false
    end

    local balance = MN.business.credit(value)
    MN.logs.money(player, Locations.shop.id, 'deposit', value, balance)
    MN.notify(src, 'boss_deposited', 'success', MN.money(value))
    return balance
end)

lib.callback.register('mangonazlet:server:withdraw', function(source, amount)
    local src = source
    if not MN.rateLimit(src, 'manage_money', 1500) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = manager(src)
    if not player then return false end

    local value = MN.int(amount, 1, 10000000)
    if not value then return false end

    local ok, balance = MN.business.debit(value)
    if not ok then
        MN.notify(src, 'boss_short', 'error')
        return false
    end

    if not MN.addMoney(src, 'bank', value, 'mangonazlet:withdraw') then
        balance = MN.business.credit(value)  -- payout failed, restore it
        MN.notify(src, 'error_generic', 'error')
        return false
    end

    MN.logs.money(player, Locations.shop.id, 'withdraw', value, balance)
    MN.notify(src, 'boss_withdrew', 'success', MN.money(value))
    return balance
end)

lib.callback.register('mangonazlet:server:hire', function(source, targetId)
    local src = source
    if not MN.rateLimit(src, 'staff', 2000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = manager(src)
    if not player then return false end

    local target = MN.int(targetId, 1)
    if not target or not GetPlayerName(target) then
        MN.notify(src, 'boss_offline', 'error')
        return false
    end

    local hired = MN.getPlayer(target)
    if not hired then
        MN.notify(src, 'boss_offline', 'error')
        return false
    end

    -- Hiring happens face to face.
    if MN.playerDistance(src, target) > 8.0 then
        MN.notify(src, 'bill_far', 'error')
        return false
    end

    local grade = Permissions.hireGrade
    if not MN.setJob(target, grade) then
        MN.notify(src, 'error_generic', 'error')
        return false
    end

    MN.db.upsertStaff(hired.citizenid, Locations.shop.id, hired.name, grade)
    MN.logs.staff(player, hired, Locations.shop.id, 'hire', Permissions.gradeLabel(grade))

    MN.notify(src, 'boss_hired', 'success', hired.name)
    MN.notify(target, 'boss_hired', 'success', hired.name)
    return true
end)

lib.callback.register('mangonazlet:server:fire', function(source, citizenid)
    local src = source
    if not MN.rateLimit(src, 'staff', 2000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = manager(src)
    if not player then return false end

    if type(citizenid) ~= 'string' or #citizenid == 0 or #citizenid > 64 then
        MN.reject(src, 'payload', 'fire')
        return false
    end
    if citizenid == player.citizenid then
        MN.notify(src, 'boss_not_self', 'error')
        return false
    end

    local staff = MN.db.staff(Locations.shop.id)
    local record
    for i = 1, #staff do
        if staff[i].citizenid == citizenid then record = staff[i] break end
    end

    local targetSrc = MN.sourceOf(citizenid)
    local target = targetSrc and MN.getPlayer(targetSrc) or nil

    if not record and not target then
        MN.notify(src, 'boss_offline', 'error')
        return false
    end

    local grade = target and target.job.grade or (record and record.grade) or 0
    if Permissions.isOwner(grade) then
        MN.notify(src, 'boss_not_owner', 'error')
        return false
    end

    if targetSrc then
        MN.clearJob(targetSrc)
        MN.clockOut(targetSrc)
    end

    MN.db.removeStaff(citizenid)
    MN.setStandaloneGrade(citizenid, nil)

    local name = (target and target.name) or (record and record.name) or citizenid
    MN.logs.staff(player, { name = name, citizenid = citizenid }, Locations.shop.id, 'fire', 'dismissed')
    MN.notify(src, 'boss_fired', 'success', name)
    return true
end)

lib.callback.register('mangonazlet:server:setGrade', function(source, citizenid, grade)
    local src = source
    if not MN.rateLimit(src, 'staff', 2000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = manager(src)
    if not player then return false end

    if type(citizenid) ~= 'string' or #citizenid == 0 or #citizenid > 64 then
        MN.reject(src, 'payload', 'grade')
        return false
    end

    local cap = math.min(Permissions.maxAssignable, Permissions.maxGrade())
    local newGrade = MN.int(grade, 0, cap)
    if not newGrade then
        MN.notify(src, 'boss_rank_cap', 'error', Permissions.gradeLabel(cap))
        return false
    end

    if citizenid == player.citizenid then
        MN.notify(src, 'boss_not_self', 'error')
        return false
    end

    local targetSrc = MN.sourceOf(citizenid)

    if not targetSrc then
        -- Offline: update our own records so it applies when they return.
        MN.db.setStaffGrade(citizenid, newGrade)
        MN.setStandaloneGrade(citizenid, newGrade)
        MN.logs.staff(player, { name = citizenid, citizenid = citizenid },
            Locations.shop.id, 'rank', Permissions.gradeLabel(newGrade))
        MN.notify(src, 'boss_ranked', 'success', citizenid, Permissions.gradeLabel(newGrade))
        return true
    end

    local target = MN.getPlayer(targetSrc)
    if not target then
        MN.notify(src, 'boss_offline', 'error')
        return false
    end
    if Permissions.isOwner(target.job.grade) then
        MN.notify(src, 'boss_not_owner', 'error')
        return false
    end

    if not MN.setJob(targetSrc, newGrade) then
        MN.notify(src, 'error_generic', 'error')
        return false
    end

    MN.db.upsertStaff(citizenid, Locations.shop.id, target.name, newGrade)
    MN.logs.staff(player, target, Locations.shop.id, 'rank', Permissions.gradeLabel(newGrade))

    MN.notify(src, 'boss_ranked', 'success', target.name, Permissions.gradeLabel(newGrade))
    MN.notify(targetSrc, 'boss_ranked', 'inform', target.name, Permissions.gradeLabel(newGrade))
    return true
end)
