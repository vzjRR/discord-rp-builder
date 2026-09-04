---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — التوريد
    ---------------------------
    1) شراء مواد خام من المورّد (يُدفع من حساب الشركة أو من جيب اللاعب).
    2) جولة توريد بالشاحنة: نقاط تحميل عشوائية ثم تسليم بالمحل مقابل أجر.
]]

IC = IC or {}
IC.supply = {}

-- الجولات النشطة: [src] = run
local runs = {}
-- آخر جولة لكل لاعب: [citizenid] = timestamp
local lastRun = {}

-- ────────────────────────────────────────────────────────────
-- كتالوج المواد الخام
-- ────────────────────────────────────────────────────────────

---يبحث عن مادة في الكتالوج (مصدر السعر الوحيد الموثوق)
---@param item any
---@return table|nil
local function findCatalogEntry(item)
    if type(item) ~= 'string' then return nil end
    for i = 1, #Config.Supply.catalog do
        if Config.Supply.catalog[i].item == item then
            return Config.Supply.catalog[i]
        end
    end
    return nil
end

lib.callback.register('icecream:server:getCatalog', function(source, branchId)
    local player = IC.getPlayer(source)
    if not player or player.job.name ~= Config.Job.name then return nil end
    if not IC.server.resolveBranch(branchId) then return nil end

    return {
        catalog = Config.Supply.catalog,
        balance = IC.society.getBalance(branchId),
        payFrom = Config.Supply.payFrom,
    }
end)

-- ────────────────────────────────────────────────────────────
-- شراء مادة خام
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:buySupply', function(source, data)
    local src = source

    if not Config.Supply.enabled then return false end
    if not IC.rateLimit(src, 'supply', 1000) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end
    if type(data) ~= 'table' then
        IC.logs.exploit(src, 'malformed_payload', 'supply')
        return false
    end

    local branch = IC.server.resolveBranch(data.branch)
    if not branch then
        IC.logs.exploit(src, 'invalid_branch', tostring(data.branch))
        return false
    end

    local player = IC.server.gate(src, 'canSupply', branch.supply.coords, 5.0)
    if not player then return false end

    local entry = findCatalogEntry(data.item)
    if not entry then
        IC.logs.exploit(src, 'invalid_supply_item', tostring(data.item))
        return false
    end

    local maxQty = math.min(entry.max or Config.Supply.maxQuantity, Config.Supply.maxQuantity)
    local qty = IC.toInt(data.quantity, 1, maxQty)
    if not qty then
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    -- السعر يُحسب على السيرفر من الكونفق، لا من رسالة العميل
    local total = entry.price * qty

    if not IC.canCarry(src, entry.item, qty) then
        IC.server.notify(src, 'supply_full', 'error')
        return false
    end

    -- الدفع
    if Config.Supply.payFrom == 'society' then
        if not IC.society.canAfford(branch.id, total) then
            IC.server.notify(src, 'supply_no_funds', 'error', IC.money(total))
            return false
        end
        local ok = IC.society.take(branch.id, total)
        if not ok then
            IC.server.notify(src, 'supply_no_funds', 'error', IC.money(total))
            return false
        end
    else
        if not IC.removeMoney(src, Config.Economy.playerAccount, total, 'icecream-supply') then
            IC.server.notify(src, 'bill_no_money', 'error')
            return false
        end
    end

    -- التسليم — لو فشل، نرجّع الفلوس
    if not IC.addItem(src, entry.item, qty) then
        if Config.Supply.payFrom == 'society' then
            IC.society.add(branch.id, total)
        else
            IC.addMoney(src, Config.Economy.playerAccount, total, 'icecream-supply-refund')
        end
        IC.server.notify(src, 'supply_full', 'error')
        return false
    end

    IC.logs.money(player, branch.id, 'supply', total, IC.society.getBalance(branch.id))
    IC.server.notify(src, 'supply_bought', 'success', qty, entry.label, IC.money(total))
    return true
end)

-- ────────────────────────────────────────────────────────────
-- جولة التوريد بالشاحنة
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:startSupplyRun', function(source, branchId)
    local src = source

    if not (Config.Supply.enabled and Config.Supply.run.enabled) then return false end

    local branch = IC.server.resolveBranch(branchId)
    if not branch then return false end

    local player = IC.server.gate(src, 'canSupply', branch.supply.coords, 6.0)
    if not player then return false end

    if runs[src] then
        IC.server.notify(src, 'supply_run_active', 'error')
        return false
    end

    local last = lastRun[player.citizenid]
    local cooldown = Config.Supply.run.cooldownMinutes * 60
    if last and (os.time() - last) < cooldown then
        local left = math.ceil((cooldown - (os.time() - last)) / 60)
        IC.server.notify(src, 'supply_run_cooldown', 'error', left)
        return false
    end

    -- اختيار نقاط عشوائية بلا تكرار
    local available = {}
    for i = 1, #Locations.SupplyPickups do available[i] = i end
    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    local wanted = math.min(Config.Supply.run.pickups, #available)
    local points = {}
    for i = 1, wanted do
        local pickup = Locations.SupplyPickups[available[i]]
        points[i] = { index = available[i], label = pickup.label, coords = pickup.coords }
    end

    runs[src] = {
        branch = branch.id,
        citizenid = player.citizenid,
        points = points,
        collected = 0,
        startedAt = os.time(),
    }

    IC.server.notify(src, 'supply_run_started', 'inform', wanted)
    return { points = points, vehicle = Config.Supply.run.vehicle, total = wanted }
end)

lib.callback.register('icecream:server:collectSupply', function(source, index)
    local src = source
    local run = runs[src]
    if not run then return false end

    local idx = IC.toInt(index, 1, #Locations.SupplyPickups)
    if not idx then
        IC.logs.exploit(src, 'invalid_pickup', tostring(index))
        return false
    end

    -- النقطة يجب أن تكون ضمن نقاط هذه الجولة وغير مستلمة
    local point
    for i = 1, #run.points do
        if run.points[i].index == idx then point = run.points[i] break end
    end
    if not point or point.done then return false end

    if not IC.isNear(src, Locations.SupplyPickups[idx].coords, 25.0) then
        IC.logs.exploit(src, 'distance_check', 'supply pickup')
        IC.server.notify(src, 'too_far', 'error')
        return false
    end

    point.done = true
    run.collected = run.collected + 1

    if run.collected >= #run.points then
        IC.server.notify(src, 'supply_run_deliver', 'inform')
    else
        IC.server.notify(src, 'supply_run_pickup', 'success', run.collected, #run.points)
    end

    return { collected = run.collected, total = #run.points }
end)

lib.callback.register('icecream:server:finishSupplyRun', function(source)
    local src = source
    local run = runs[src]
    if not run then return false end

    local branch = Locations.getBranch(run.branch)
    if not branch then
        runs[src] = nil
        return false
    end

    if run.collected < #run.points then
        IC.server.notify(src, 'supply_run_deliver', 'error')
        return false
    end

    if not IC.isNear(src, branch.supply.coords, 15.0) then
        IC.server.notify(src, 'too_far', 'error')
        return false
    end

    local player = IC.getPlayer(src)
    if not player then
        runs[src] = nil
        return false
    end

    runs[src] = nil
    lastRun[run.citizenid] = os.time()

    local payout = math.random(Config.Supply.run.payout.min, Config.Supply.run.payout.max)
    IC.addMoney(src, Config.Economy.playerAccount, payout, 'icecream-supply-run')

    IC.db.log(branch.id, player.citizenid, 'supply_run',
        ('%s نقاط'):format(#run.points), payout)
    IC.logs.money(player, branch.id, 'supply_run', payout, IC.society.getBalance(branch.id))
    IC.server.notify(src, 'supply_run_done', 'success', IC.money(payout))

    return true
end)

RegisterNetEvent('icecream:server:cancelSupplyRun', function()
    local src = source
    if runs[src] then
        runs[src] = nil
        IC.server.notify(src, 'supply_run_cancelled', 'inform')
    end
end)

AddEventHandler('playerDropped', function()
    runs[source] = nil
end)
