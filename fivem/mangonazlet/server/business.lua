---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — The business itself: balance, shop stock, sale settlement,
    payroll and the management actions.

    The balance and the stock are the only authoritative copies. Clients get
    read-only snapshots; they can never write either.
]]

MN = MN or {}
MN.business = {}

local SHOP = 'vespucci'

local balance = 0
local balanceDirty = false

---@type table<string, number> item -> quantity available at the counter
local stock = {}
local stockDirty = {}

-- ═══════════════════════════════════════════════════════════════
-- Boot / persistence
-- ═══════════════════════════════════════════════════════════════

function MN.business.load()
    SHOP = Locations.shop.id
    balance = MN.db.loadBalance(SHOP) or Config.Economy.openingBalance
    stock = MN.db.loadStock(SHOP)
    MN.debug('business loaded: balance=%s stock lines=%s', balance, MN.count(stock))
end

function MN.business.flush()
    if balanceDirty then
        MN.db.saveBalance(SHOP, balance)
        balanceDirty = false
    end
    for item in pairs(stockDirty) do
        MN.db.saveStock(SHOP, item, stock[item] or 0)
    end
    stockDirty = {}
end

-- Periodic flush keeps writes off the hot path of every sale.
CreateThread(function()
    while true do
        Wait(60000)
        MN.business.flush()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- Balance
-- ═══════════════════════════════════════════════════════════════

---@return number
function MN.business.balance() return balance end

---@param amount number
---@return number newBalance
function MN.business.credit(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return balance end
    balance = balance + amount
    balanceDirty = true
    return balance
end

---@param amount number
---@return boolean ok, number balance
function MN.business.debit(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, balance end
    if balance < amount and not Config.Economy.allowNegative then return false, balance end
    balance = balance - amount
    balanceDirty = true
    return true, balance
end

---@param amount number
---@return boolean
function MN.business.canAfford(amount)
    if Config.Economy.allowNegative then return true end
    return balance >= (tonumber(amount) or 0)
end

-- ═══════════════════════════════════════════════════════════════
-- Counter stock
-- ═══════════════════════════════════════════════════════════════

---@param item string
---@return number
function MN.business.stockOf(item) return stock[item] or 0 end

---Snapshot handed to the customer menu. Only sellable products appear.
---@return table<string, number>
function MN.business.stockSnapshot()
    local out = {}
    local menu = Products.menu()
    for i = 1, #menu do
        local name = menu[i].name
        out[name] = stock[name] or 0
    end
    return out
end

---@param item string
---@param quantity number
---@return number newQuantity
function MN.business.addStock(item, quantity)
    quantity = math.floor(tonumber(quantity) or 0)
    if quantity <= 0 then return stock[item] or 0 end
    stock[item] = (stock[item] or 0) + quantity
    stockDirty[item] = true
    MN.business.broadcastStock()
    return stock[item]
end

---Take stock for a sale. Returns false without changing anything when short,
---so a checkout can never oversell.
---@param item string
---@param quantity number
---@return boolean
function MN.business.takeStock(item, quantity)
    quantity = math.floor(tonumber(quantity) or 0)
    if quantity <= 0 then return false end
    local have = stock[item] or 0
    if have < quantity then return false end
    stock[item] = have - quantity
    stockDirty[item] = true
    return true
end

---Push the current stock to anyone with the shop menu open.
function MN.business.broadcastStock()
    TriggerClientEvent('mangonazlet:client:stock', -1, MN.business.stockSnapshot())
end

-- ═══════════════════════════════════════════════════════════════
-- Sale settlement — the one place money is created from a sale
-- ═══════════════════════════════════════════════════════════════

---Split a completed sale between the business and the employee who made it.
---@param src number|nil        employee source, nil for an unattended counter sale
---@param player table|nil      employee record
---@param total number          gross value, already computed server-side
---@param item string
---@param quantity number
---@param channel string        MN.CHANNEL.*
---@return number tip
function MN.business.settle(src, player, total, item, quantity, channel)
    total = math.floor(tonumber(total) or 0)
    if total <= 0 then return 0 end

    local tip = 0
    if src and player then
        tip = math.floor(total * Config.Economy.employeeTip)
        if tip > Config.Economy.maxTipPerSale then tip = Config.Economy.maxTipPerSale end
        if tip > 0 then
            MN.addMoney(src, Config.Economy.playerAccount, tip, 'mangonazlet:tip')
        end
    end

    MN.business.credit(total - tip)

    MN.db.recordSale(SHOP, player and player.citizenid or '', item, quantity, total, channel)
    if player then MN.db.addStaffStats(player.citizenid, quantity, tip) end
    MN.logs.sale(player, SHOP, item, quantity, total, channel)

    return tip
end

-- ═══════════════════════════════════════════════════════════════
-- Payroll
-- ═══════════════════════════════════════════════════════════════

if Config.Payroll.enabled then
    CreateThread(function()
        local interval = math.max(Config.Payroll.intervalMinutes, 1) * 60000
        while true do
            Wait(interval)

            local paid, total = 0, 0
            for _, src in ipairs(MN.onDutyList()) do
                local player = MN.getPlayer(src)
                if player and player.job.name == Permissions.job then
                    local eligible = not Config.Payroll.requireDuty or player.job.onduty
                    local amount = Permissions.pay(player.job.grade)

                    if eligible and amount > 0 then
                        if balance - amount < Config.Payroll.minBalance then
                            MN.debug('payroll skipped: balance too low')
                            break
                        end
                        local ok = MN.business.debit(amount)
                        if ok then
                            if MN.addMoney(src, 'bank', amount, 'mangonazlet:payroll') then
                                MN.notify(src, 'paycheck', 'success', MN.money(amount))
                                paid, total = paid + 1, total + amount
                            else
                                MN.business.credit(amount) -- payment failed, put it back
                            end
                        end
                    end
                end
            end

            if paid > 0 then
                MN.logs.money(nil, SHOP, 'payroll', total, balance)
                MN.debug('payroll: %s staff, $%s total', paid, total)
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Exports for other resources
-- ═══════════════════════════════════════════════════════════════

exports('getBalance', function() return balance end)
exports('addBalance', function(amount) return MN.business.credit(amount) end)
exports('takeBalance', function(amount) local ok = MN.business.debit(amount) return ok end)
exports('getStock', function(item)
    if item then return stock[item] or 0 end
    return MN.business.stockSnapshot()
end)
exports('getStaffOnDuty', function() return #MN.onDutyList() end)
