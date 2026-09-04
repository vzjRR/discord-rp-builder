---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Ingredient supply.

    Two ways to restock:
      1. buy from the supplier at the shop (paid from the business account)
      2. run the van to collection points for a personal payout

    Unit prices come from config/products.lua; the client only ever sends an
    item name and a quantity, both re-validated here.
]]

MN = MN or {}

local runs = {}       -- [source] = run
local lastRun = {}    -- [citizenid] = timestamp

---@param item any
---@return table|nil
local function ingredient(item)
    if type(item) ~= 'string' then return nil end
    local product = Products.get(item)
    if not product or product.category ~= 'ingredient' then return nil end
    return product
end

lib.callback.register('mangonazlet:server:catalogue', function(source)
    if not MN.rateLimit(source, 'catalogue', 1000) then return nil end

    local player = MN.getPlayer(source)
    if not player or player.job.name ~= Permissions.job then return nil end

    local catalogue = Products.catalogue()
    local out = {}
    for i = 1, #catalogue do
        local product = catalogue[i]
        out[#out + 1] = {
            item = product.name,
            label = product.label,
            cost = product.cost,
            maxBuy = math.min(product.maxBuy or Config.Supply.maxQuantity, Config.Supply.maxQuantity),
        }
    end

    return {
        catalogue = out,
        balance = MN.business.balance(),
        payFrom = Config.Supply.payFrom,
    }
end)

lib.callback.register('mangonazlet:server:buySupply', function(source, payload)
    local src = source

    if not Config.Supply.enabled then return false end
    if not MN.rateLimit(src, 'supply', 1000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end
    if type(payload) ~= 'table' then
        MN.reject(src, 'payload', 'supply')
        return false
    end

    local player = MN.gate(src, MN.PERM.SUPPLY, Locations.shop.supply.coords, 5.0)
    if not player then return false end

    local product = ingredient(payload.item)
    if not product then
        MN.reject(src, 'supply_item', tostring(payload.item))
        return false
    end

    local cap = math.min(product.maxBuy or Config.Supply.maxQuantity, Config.Supply.maxQuantity)
    local quantity = MN.int(payload.quantity, 1, cap)
    if not quantity then return false end

    -- Total is computed here, never taken from the message.
    local total = product.cost * quantity

    if not MN.canCarry(src, product.name, quantity) then
        MN.notify(src, 'inventory_full', 'error')
        return false
    end

    local paidFromBusiness = Config.Supply.payFrom == 'business'
    if paidFromBusiness then
        if not MN.business.canAfford(total) then
            MN.notify(src, 'supply_short', 'error', MN.money(total))
            return false
        end
        if not MN.business.debit(total) then
            MN.notify(src, 'supply_short', 'error', MN.money(total))
            return false
        end
    else
        if not MN.removeMoney(src, Config.Economy.playerAccount, total, 'mangonazlet:supply') then
            MN.notify(src, 'no_money', 'error')
            return false
        end
    end

    if not MN.addItem(src, product.name, quantity) then
        -- Delivery failed after payment: refund exactly what was charged.
        if paidFromBusiness then
            MN.business.credit(total)
        else
            MN.addMoney(src, Config.Economy.playerAccount, total, 'mangonazlet:supply-refund')
        end
        MN.notify(src, 'inventory_full', 'error')
        return false
    end

    MN.logs.money(player, Locations.shop.id, 'supply', total, MN.business.balance())
    MN.notify(src, 'supply_bought', 'success', quantity, Products.label(product.name), MN.money(total))
    return true
end)

-- ═══════════════════════════════════════════════════════════════
-- Van run
-- ═══════════════════════════════════════════════════════════════

lib.callback.register('mangonazlet:server:runStart', function(source)
    local src = source

    if not (Config.Supply.enabled and Config.Supply.run.enabled) then return false end
    if not MN.rateLimit(src, 'runstart', 3000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = MN.gate(src, MN.PERM.SUPPLY, Locations.shop.supply.coords, 6.0)
    if not player then return false end

    if runs[src] then
        MN.notify(src, 'supply_run_busy', 'error')
        return false
    end

    local cooldown = Config.Supply.run.cooldownMinutes * 60
    local last = lastRun[player.citizenid]
    if last and (os.time() - last) < cooldown then
        MN.notify(src, 'supply_run_wait', 'error', math.ceil((cooldown - (os.time() - last)) / 60))
        return false
    end

    -- Pick distinct collection points.
    local order = {}
    for i = 1, #Locations.pickups do order[i] = i end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end

    local wanted = math.min(Config.Supply.run.pickups, #order)
    local points = {}
    for i = 1, wanted do
        local pickup = Locations.pickups[order[i]]
        points[i] = { index = order[i], label = pickup.label, coords = pickup.coords }
    end

    runs[src] = {
        citizenid = player.citizenid,
        points = points,
        collected = 0,
        done = {},
        started = os.time(),
    }

    MN.notify(src, 'supply_run_go', 'inform', wanted)
    return { points = points, vehicle = Config.Supply.run.vehicle, total = wanted }
end)

lib.callback.register('mangonazlet:server:runCollect', function(source, index)
    local src = source
    if not MN.rateLimit(src, 'runcollect', 1000) then return false end

    local run = runs[src]
    if not run then return false end

    local idx = MN.int(index, 1, #Locations.pickups)
    if not idx then
        MN.reject(src, 'pickup_index', tostring(index))
        return false
    end

    -- Must be one of THIS run's points, and not already collected.
    local point
    for i = 1, #run.points do
        if run.points[i].index == idx then point = run.points[i] break end
    end
    if not point or run.done[idx] then return false end

    if not MN.isNear(src, Locations.pickups[idx].coords, 25.0) then
        MN.reject(src, 'distance', 'supply pickup')
        MN.notify(src, 'too_far', 'error')
        return false
    end

    run.done[idx] = true
    run.collected = run.collected + 1

    if run.collected >= #run.points then
        MN.notify(src, 'supply_run_back', 'inform')
    else
        MN.notify(src, 'supply_run_got', 'success', run.collected, #run.points)
    end

    return { collected = run.collected, total = #run.points }
end)

lib.callback.register('mangonazlet:server:runFinish', function(source)
    local src = source
    if not MN.rateLimit(src, 'runfinish', 2000) then return false end

    local run = runs[src]
    if not run then return false end

    if run.collected < #run.points then
        MN.notify(src, 'supply_run_back', 'error')
        return false
    end

    if not MN.isNear(src, Locations.shop.supply.coords, 15.0) then
        MN.notify(src, 'too_far', 'error')
        return false
    end

    local player = MN.getPlayer(src)
    if not player then
        runs[src] = nil
        return false
    end

    runs[src] = nil
    lastRun[run.citizenid] = os.time()

    local payout = math.random(Config.Supply.run.payout.min, Config.Supply.run.payout.max)
    MN.addMoney(src, Config.Economy.playerAccount, payout, 'mangonazlet:supply-run')

    MN.db.log(Locations.shop.id, player.citizenid, 'supply_run',
        ('%s pickups'):format(#run.points), payout)
    MN.logs.money(player, Locations.shop.id, 'supply_run', payout, MN.business.balance())
    MN.notify(src, 'supply_run_done', 'success', MN.money(payout))
    return true
end)

RegisterNetEvent('mangonazlet:server:runCancel', function()
    local src = source
    if not MN.rateLimit(src, 'runcancel', 1000) then return end

    if runs[src] then
        runs[src] = nil
        MN.notify(src, 'supply_run_stop', 'inform')
    end
end)

AddEventHandler('playerDropped', function()
    runs[source] = nil
end)
