---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — حساب الشركة والرواتب
    ----------------------------------------
    مصدر الحقيقة الوحيد لرصيد المحل. كل زيادة/نقصان تمر من هنا،
    والحفظ في قاعدة البيانات مؤجّل (dirty flag) لتفادي كتابة عند كل بيعة.
]]

IC = IC or {}
IC.society = {}

local balances = {}   -- [branchId] = number
local dirty = {}      -- [branchId] = true

-- ────────────────────────────────────────────────────────────
-- التهيئة والحفظ
-- ────────────────────────────────────────────────────────────

function IC.society.init()
    for i = 1, #Locations.Branches do
        local id = Locations.Branches[i].id
        local stored = IC.db.loadBalance(id)
        balances[id] = stored or Config.Economy.startingBalance
    end
    IC.debug('حمّلت أرصدة %s فرع', #Locations.Branches)
end

function IC.society.saveAll()
    for branchId, balance in pairs(balances) do
        if dirty[branchId] then
            IC.db.saveBalance(branchId, balance)
            dirty[branchId] = nil
        end
    end
end

-- حفظ دوري كل دقيقة لما يكون في تغيير
CreateThread(function()
    while true do
        Wait(60000)
        IC.society.saveAll()
    end
end)

-- ────────────────────────────────────────────────────────────
-- الرصيد
-- ────────────────────────────────────────────────────────────

---@param branchId string
---@return number
function IC.society.getBalance(branchId)
    return balances[branchId] or 0
end

---يضيف للرصيد (amount موجب فقط)
---@param branchId string
---@param amount number
---@return number newBalance
function IC.society.add(branchId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return balances[branchId] or 0 end
    balances[branchId] = (balances[branchId] or 0) + amount
    dirty[branchId] = true
    return balances[branchId]
end

---يخصم من الرصيد. يرجّع false لو الرصيد لا يكفي.
---@param branchId string
---@param amount number
---@return boolean ok, number balance
function IC.society.take(branchId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, balances[branchId] or 0 end

    local current = balances[branchId] or 0
    if current < amount and not Config.Economy.allowNegativeBalance then
        return false, current
    end

    balances[branchId] = current - amount
    dirty[branchId] = true
    return true, balances[branchId]
end

---هل يقدر الحساب يتحمّل هذا المبلغ؟
---@param branchId string
---@param amount number
---@return boolean
function IC.society.canAfford(branchId, amount)
    if Config.Economy.allowNegativeBalance then return true end
    return (balances[branchId] or 0) >= (tonumber(amount) or 0)
end

-- ────────────────────────────────────────────────────────────
-- توزيع قيمة بيعة: نصيب الشركة + بقشيش الموظف
-- ────────────────────────────────────────────────────────────

---يوزّع قيمة بيعة ويدفع البقشيش للموظف مباشرة
---@param branchId string
---@param src number
---@param player table
---@param total number
---@param item string
---@param qty number
---@param kind string
---@return number tip
function IC.society.settleSale(branchId, src, player, total, item, qty, kind)
    total = math.floor(tonumber(total) or 0)
    if total <= 0 then return 0 end

    local tip = math.floor(total * Config.Economy.employeeTip)
    if tip > Config.Economy.maxTipPerOrder then tip = Config.Economy.maxTipPerOrder end
    local societyCut = total - tip

    IC.society.add(branchId, societyCut)
    if tip > 0 then
        IC.addMoney(src, Config.Economy.playerAccount, tip, 'icecream-tip')
    end

    IC.db.recordSale(branchId, player.citizenid, item, qty, total, kind)
    IC.db.addEmployeeStats(player.citizenid, qty, tip)
    IC.logs.sale(player, branchId, item, qty, total, kind)

    return tip
end

-- ────────────────────────────────────────────────────────────
-- الرواتب الدورية
-- ────────────────────────────────────────────────────────────

if Config.Paycheck.enabled then
    CreateThread(function()
        local interval = math.max(Config.Paycheck.intervalMinutes, 1) * 60000
        while true do
            Wait(interval)

            for i = 1, #Locations.Branches do
                local branchId = Locations.Branches[i].id
                local paid, total = 0, 0

                for _, src in ipairs(IC.server.getOnDuty(branchId)) do
                    local player = IC.getPlayer(src)
                    if player and player.job.name == Config.Job.name then
                        local eligible = not Config.Paycheck.requireDuty or player.job.onduty
                        local amount = Config.Paycheck.amounts[player.job.grade] or 0

                        if eligible and amount > 0 then
                            if IC.society.getBalance(branchId) - amount < Config.Paycheck.minBalance then
                                IC.debug('راتب متخطّى: رصيد %s لا يكفي', branchId)
                                break
                            end
                            local ok = IC.society.take(branchId, amount)
                            if ok and IC.addMoney(src, 'bank', amount, 'icecream-paycheck') then
                                IC.server.notify(src, 'paycheck_received', 'success', IC.money(amount))
                                paid = paid + 1
                                total = total + amount
                            elseif ok then
                                -- فشل الدفع للاعب: نرجّع المبلغ للشركة
                                IC.society.add(branchId, amount)
                            end
                        end
                    end
                end

                if paid > 0 then
                    IC.logs.money(nil, branchId, 'paycheck', total, IC.society.getBalance(branchId))
                    IC.debug('صرفت رواتب %s موظف بمجموع %s في %s', paid, total, branchId)
                end
            end
        end
    end)
end

-- ────────────────────────────────────────────────────────────
-- Exports للموارد الأخرى
-- ────────────────────────────────────────────────────────────

exports('getBalance', function(branchId)
    return IC.society.getBalance(branchId or Locations.Branches[1].id)
end)

exports('addBalance', function(branchId, amount)
    return IC.society.add(branchId or Locations.Branches[1].id, amount)
end)

exports('takeBalance', function(branchId, amount)
    local ok = IC.society.take(branchId or Locations.Branches[1].id, amount)
    return ok
end)

exports('getOnDutyCount', function(branchId)
    return IC.server.countOnDuty(branchId or Locations.Branches[1].id)
end)
