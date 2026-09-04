---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Money coming in.

    Three ways a customer pays:
      1. the counter menu (NUI)  — self-service, draws from shop stock
      2. an employee-issued bill — needs the customer to accept
      3. staff stocking the case — moves finished goods into sellable stock

    Prices are NEVER read from the client. The NUI sends item names and
    quantities; every figure is recomputed here from config/products.lua.
]]

MN = MN or {}

-- ═══════════════════════════════════════════════════════════════
-- Stocking the display case
-- ═══════════════════════════════════════════════════════════════

lib.callback.register('mangonazlet:server:stockDisplay', function(source, item, quantity)
    local src = source

    if not MN.rateLimit(src, 'stock', 500) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = MN.gate(src, MN.PERM.REGISTER, Locations.shop.display.coords, 4.0)
    if not player then return false end

    -- Only a real, sellable product may go into the case.
    local product = type(item) == 'string' and Products.get(item) or nil
    if not product or not product.price or product.price <= 0 then
        MN.reject(src, 'stock_item', tostring(item))
        return false
    end

    local count = MN.int(quantity, 1, 50)
    if not count then return false end

    local ok = MN.crafting.takeProduct(src, item, count)
    if not ok then
        MN.notify(src, 'craft_missing', 'error', Products.label(item))
        return false
    end

    local total = MN.business.addStock(item, count)
    MN.db.log(Locations.shop.id, player.citizenid, 'stock',
        ('%s x%s'):format(item, count), 0)

    return { item = item, added = count, total = total }
end)

-- Staff may pull stock back out of the case (e.g. to move it to the freezer).
lib.callback.register('mangonazlet:server:unstockDisplay', function(source, item, quantity)
    local src = source

    if not MN.rateLimit(src, 'stock', 500) then return false end

    local player = MN.gate(src, MN.PERM.REGISTER, Locations.shop.display.coords, 4.0)
    if not player then return false end

    if type(item) ~= 'string' or not Products.get(item) then
        MN.reject(src, 'stock_item', tostring(item))
        return false
    end

    local count = MN.int(quantity, 1, 50)
    if not count then return false end

    if not MN.canCarry(src, item, count) then
        MN.notify(src, 'inventory_full', 'error')
        return false
    end

    if not MN.business.takeStock(item, count) then
        MN.notify(src, 'shop_empty', 'error')
        return false
    end

    if not MN.addItem(src, item, count, Config.Melting.enabled and Products.perishable(item)
        and { madeAt = os.time(), quality = 100 } or nil) then
        MN.business.addStock(item, count) -- hand-back failed: put it back on the shelf
        MN.notify(src, 'inventory_full', 'error')
        return false
    end

    MN.business.broadcastStock()
    return true
end)

-- ═══════════════════════════════════════════════════════════════
-- Counter checkout (NUI)
-- ═══════════════════════════════════════════════════════════════

---Validate and price a basket entirely server-side.
---@param basket any
---@return table|nil lines, number total
local function priceBasket(basket)
    if type(basket) ~= 'table' then return nil, 0 end

    local lines, total, units = {}, 0, 0
    local seen = {}

    for i = 1, #basket do
        local entry = basket[i]
        if type(entry) ~= 'table' then return nil, 0 end

        local product = type(entry.item) == 'string' and Products.get(entry.item) or nil
        if not product or not product.price or product.price <= 0 then return nil, 0 end
        if seen[entry.item] then return nil, 0 end   -- one line per item
        seen[entry.item] = true

        local quantity = MN.int(entry.quantity, 1, Config.Counter.maxPerCheckout)
        if not quantity then return nil, 0 end

        units = units + quantity
        if units > Config.Counter.maxPerCheckout then return nil, 0 end

        -- The price comes from config, never from the message.
        local lineTotal = product.price * quantity
        lines[#lines + 1] = { item = entry.item, quantity = quantity, unit = product.price, total = lineTotal }
        total = total + lineTotal
    end

    if #lines == 0 then return nil, 0 end
    return lines, total
end

lib.callback.register('mangonazlet:server:checkout', function(source, payload)
    local src = source

    if not Config.Counter.enabled then return false end
    if not MN.rateLimit(src, 'checkout', Config.Counter.cooldownMs) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end
    if type(payload) ~= 'table' then
        MN.reject(src, 'payload', 'checkout')
        return false
    end

    if not MN.customerGate(src, Locations.shop.counter.coords, 4.0) then return false end

    if Config.Counter.requireStaffOnDuty and #MN.onDutyList() == 0 then
        MN.notify(src, 'shop_closed', 'error')
        return false
    end

    local lines, total = priceBasket(payload.basket)
    if not lines then
        MN.reject(src, 'basket', 'malformed or unsellable')
        MN.notify(src, 'error_generic', 'error')
        return false
    end

    local account = payload.account == 'cash' and 'cash' or 'bank'
    if account == 'cash' and not Config.Economy.counterCash then account = 'bank' end
    if account == 'bank' and not Config.Economy.counterBank then account = 'cash' end

    -- Stock check for the whole basket before anything is taken.
    if Config.Counter.requireStock then
        for i = 1, #lines do
            if MN.business.stockOf(lines[i].item) < lines[i].quantity then
                MN.notify(src, 'shop_empty', 'error')
                MN.business.broadcastStock()
                return false
            end
        end
    end

    -- Carry check before charging.
    for i = 1, #lines do
        if not MN.canCarry(src, lines[i].item, lines[i].quantity) then
            MN.notify(src, 'inventory_full', 'error')
            return false
        end
    end

    if not MN.removeMoney(src, account, total, 'mangonazlet:counter') then
        MN.notify(src, 'no_money', 'error')
        return false
    end

    -- Take stock and hand over. Anything that fails here is refunded in full.
    local taken, delivered = {}, {}
    local function rollback()
        for i = 1, #delivered do
            MN.removeItem(src, delivered[i].item, delivered[i].quantity)
        end
        for i = 1, #taken do
            MN.business.addStock(taken[i].item, taken[i].quantity)
        end
        MN.addMoney(src, account, total, 'mangonazlet:counter-refund')
    end

    for i = 1, #lines do
        local line = lines[i]

        if Config.Counter.requireStock then
            if not MN.business.takeStock(line.item, line.quantity) then
                rollback()
                MN.notify(src, 'shop_empty', 'error')
                return false
            end
            taken[#taken + 1] = line
        end

        local metadata
        if Config.Melting.enabled and Products.perishable(line.item) then
            metadata = { madeAt = os.time(), quality = 100 }
        end

        if not MN.addItem(src, line.item, line.quantity, metadata) then
            rollback()
            MN.notify(src, 'inventory_full', 'error')
            return false
        end
        delivered[#delivered + 1] = line
    end

    -- The shop keeps the whole counter sale: there is no individual server
    -- attached to a self-service purchase.
    for i = 1, #lines do
        MN.business.settle(nil, nil, lines[i].total, lines[i].item, lines[i].quantity, MN.CHANNEL.COUNTER)
    end

    MN.business.broadcastStock()

    local first = lines[1]
    MN.notify(src, 'shop_bought', 'success', first.quantity, Products.label(first.item), MN.money(total))

    return { total = total, lines = #lines }
end)

-- Menu + live stock for the NUI. Read-only.
lib.callback.register('mangonazlet:server:menu', function(source)
    local src = source
    -- Open to any customer, so it is throttled to stop menu-spam.
    if not MN.rateLimit(src, 'menu', 1000) then return nil end
    if not MN.isNear(src, Locations.shop.counter.coords, 6.0) then return nil end

    local menu = Products.menu()
    local out = {}
    for i = 1, #menu do
        local product = menu[i]
        out[#out + 1] = {
            item = product.name,
            label = product.label,
            desc = product.desc,
            price = product.price,
            category = product.category,
            image = product.image,
        }
    end

    return {
        products = out,
        stock = MN.business.stockSnapshot(),
        requireStock = Config.Counter.requireStock,
        cash = Config.Economy.counterCash,
        bank = Config.Economy.counterBank,
        maxPerCheckout = Config.Counter.maxPerCheckout,
    }
end)

-- ═══════════════════════════════════════════════════════════════
-- Employee-issued bills
-- ═══════════════════════════════════════════════════════════════

local bills = {}   -- [id] = bill
local nextBill = 1

local function expireBills()
    local now = os.time()
    for id, bill in pairs(bills) do
        if bill.expires <= now then
            bills[id] = nil
            if GetPlayerName(bill.from) then MN.notify(bill.from, 'bill_expired', 'error') end
            if GetPlayerName(bill.to) then
                TriggerClientEvent('mangonazlet:client:billClosed', bill.to, id)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(5000)
        expireBills()
    end
end)

lib.callback.register('mangonazlet:server:createBill', function(source, payload)
    local src = source

    if not Config.Billing.enabled then return false end
    if not MN.rateLimit(src, 'bill', 3000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end
    if type(payload) ~= 'table' then
        MN.reject(src, 'payload', 'bill')
        return false
    end

    local player = MN.gate(src, MN.PERM.REGISTER, Locations.shop.register.coords, Config.Billing.maxDistance + 2.0)
    if not player then return false end

    local amount = MN.int(payload.amount, 1, Config.Billing.maxAmount)
    if not amount then
        MN.notify(src, 'bill_max', 'error', MN.money(Config.Billing.maxAmount))
        return false
    end

    local target = MN.int(payload.target, 1)
    if not target or not GetPlayerName(target) then
        MN.notify(src, 'bill_invalid', 'error')
        return false
    end
    if target == src then
        MN.notify(src, 'bill_self', 'error')
        return false
    end
    if MN.playerDistance(src, target) > Config.Billing.maxDistance then
        MN.notify(src, 'bill_far', 'error')
        return false
    end

    local bill = {
        id = nextBill,
        from = src,
        citizenid = player.citizenid,
        to = target,
        amount = amount,
        reason = MN.text(payload.reason, 60),
        expires = os.time() + Config.Billing.timeout,
    }
    bills[bill.id] = bill
    nextBill = nextBill + 1

    TriggerClientEvent('mangonazlet:client:bill', target, {
        id = bill.id,
        from = player.name,
        amount = amount,
        reason = bill.reason,
        timeout = Config.Billing.timeout,
    })

    MN.notify(src, 'bill_sent', 'success', GetPlayerName(target), MN.money(amount))
    return true
end)

RegisterNetEvent('mangonazlet:server:answerBill', function(billId, accepted)
    local src = source
    if not MN.rateLimit(src, 'answerbill', 500) then return end

    local id = MN.int(billId, 1)
    local bill = id and bills[id]
    if not bill then return end

    -- Only the person being charged may answer.
    if bill.to ~= src then
        MN.reject(src, 'bill_hijack', ('bill %s'):format(id))
        return
    end

    bills[id] = nil

    if bill.expires <= os.time() then
        MN.notify(src, 'bill_expired', 'error')
        return
    end

    local staffOnline = GetPlayerName(bill.from) ~= nil

    if accepted ~= true then
        if staffOnline then
            MN.notify(bill.from, 'bill_refused', 'error', GetPlayerName(src) or '?')
        end
        return
    end

    -- Re-check distance at the moment of payment, not when the bill was sent.
    if staffOnline and MN.playerDistance(bill.from, src) > Config.Billing.maxDistance + 5.0 then
        MN.notify(src, 'bill_far', 'error')
        MN.notify(bill.from, 'bill_far', 'error')
        return
    end

    if not MN.removeMoney(src, Config.Economy.billAccount, bill.amount, 'mangonazlet:bill') then
        MN.notify(src, 'no_money', 'error')
        if staffOnline then
            MN.notify(bill.from, 'bill_refused', 'error', GetPlayerName(src) or '?')
        end
        return
    end

    MN.notify(src, 'bill_you_paid', 'success', MN.money(bill.amount))

    local staff = staffOnline and MN.getPlayer(bill.from) or nil
    if staff then
        MN.business.settle(bill.from, staff, bill.amount, 'bill', 1, MN.CHANNEL.BILL)
        MN.notify(bill.from, 'bill_paid_by', 'success', GetPlayerName(src) or '?', MN.money(bill.amount))
    else
        MN.business.credit(bill.amount)
        MN.db.recordSale(Locations.shop.id, bill.citizenid, 'bill', 1, bill.amount, MN.CHANNEL.BILL)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, bill in pairs(bills) do
        if bill.from == src or bill.to == src then bills[id] = nil end
    end
end)

-- Price list, built from the same product table the menu uses.
lib.callback.register('mangonazlet:server:priceList', function(source)
    if not MN.rateLimit(source, 'pricelist', 1000) then return {} end

    local player = MN.getPlayer(source)
    if not player or player.job.name ~= Permissions.job then return {} end

    local menu = Products.menu()
    local out = {}
    for i = 1, #menu do
        out[#out + 1] = { item = menu[i].name, label = menu[i].label, price = menu[i].price }
    end
    return out
end)
