---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — الكاشير والفوترة
    ------------------------------------
    فوترة لاعب قريب: الموظف يرسل الطلب، اللاعب المستهدف يوافق أو يرفض،
    والدفع يتم بالكامل على السيرفر بعد إعادة فحص المسافة والرصيد.
]]

IC = IC or {}

-- الفواتير المعلّقة: [billId] = bill
local bills = {}
local nextBillId = 1

---شكل الفاتورة:
---  { id, from, fromName, to, amount, reason, branch, expiresAt, citizenid }

local function cleanupExpired()
    local now = os.time()
    for id, bill in pairs(bills) do
        if bill.expiresAt <= now then
            bills[id] = nil
            if GetPlayerName(bill.from) then
                IC.server.notify(bill.from, 'bill_expired', 'error')
            end
            if GetPlayerName(bill.to) then
                TriggerClientEvent('icecream:client:closeBill', bill.to, id)
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(5000)
        cleanupExpired()
    end
end)

-- ────────────────────────────────────────────────────────────
-- إصدار فاتورة
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:createBill', function(source, data)
    local src = source

    if not Config.Register.enabled then return false end
    if not IC.rateLimit(src, 'bill', 3000) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end
    if type(data) ~= 'table' then
        IC.logs.exploit(src, 'malformed_payload', 'bill')
        return false
    end

    local branch = IC.server.resolveBranch(data.branch)
    if not branch then
        IC.logs.exploit(src, 'invalid_branch', tostring(data.branch))
        return false
    end

    local player = IC.server.gate(src, 'canRegister', branch.register.coords, Config.Register.maxDistance + 2.0)
    if not player then return false end

    local amount = IC.toInt(data.amount, 1, Config.Register.maxAmount)
    if not amount then
        IC.server.notify(src, 'bill_max', 'error', IC.money(Config.Register.maxAmount))
        return false
    end

    local targetSrc = IC.toInt(data.target, 1)
    if not targetSrc or not GetPlayerName(targetSrc) then
        IC.server.notify(src, 'bill_invalid', 'error')
        return false
    end
    if targetSrc == src then
        IC.server.notify(src, 'bill_self', 'error')
        return false
    end

    -- المستهدف يجب أن يكون قريبًا فعلًا من الموظف
    local employeePed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if not employeePed or not targetPed or employeePed == 0 or targetPed == 0 then
        IC.server.notify(src, 'bill_invalid', 'error')
        return false
    end
    if #(GetEntityCoords(employeePed) - GetEntityCoords(targetPed)) > Config.Register.maxDistance then
        IC.server.notify(src, 'bill_target_far', 'error')
        return false
    end

    local reason = type(data.reason) == 'string' and data.reason:sub(1, 60) or ''

    local bill = {
        id = nextBillId,
        from = src,
        fromName = player.name,
        citizenid = player.citizenid,
        to = targetSrc,
        amount = amount,
        reason = reason,
        branch = branch.id,
        expiresAt = os.time() + Config.Register.acceptTimeout,
    }
    bills[bill.id] = bill
    nextBillId = nextBillId + 1

    TriggerClientEvent('icecream:client:receiveBill', targetSrc, {
        id = bill.id,
        from = player.name,
        amount = amount,
        reason = reason,
        shop = branch.label,
        timeout = Config.Register.acceptTimeout,
    })

    IC.server.notify(src, 'bill_sent', 'success', GetPlayerName(targetSrc), IC.money(amount))
    return true
end)

-- ────────────────────────────────────────────────────────────
-- رد اللاعب على الفاتورة
-- ────────────────────────────────────────────────────────────

RegisterNetEvent('icecream:server:respondBill', function(billId, accepted)
    local src = source

    local id = IC.toInt(billId, 1)
    local bill = id and bills[id]
    if not bill then return end

    -- فقط المستهدف يقدر يرد
    if bill.to ~= src then
        IC.logs.exploit(src, 'bill_hijack', ('bill %s'):format(id))
        return
    end

    bills[id] = nil

    if bill.expiresAt <= os.time() then
        IC.server.notify(src, 'bill_expired', 'error')
        return
    end

    local employeeOnline = GetPlayerName(bill.from) ~= nil

    if accepted ~= true then
        if employeeOnline then
            IC.server.notify(bill.from, 'bill_declined', 'error', GetPlayerName(src) or '?')
        end
        return
    end

    -- إعادة فحص المسافة عند الدفع (قد يكون ابتعد أثناء التفكير)
    if employeeOnline then
        local a, b = GetPlayerPed(bill.from), GetPlayerPed(src)
        if a ~= 0 and b ~= 0 and #(GetEntityCoords(a) - GetEntityCoords(b)) > Config.Register.maxDistance + 5.0 then
            IC.server.notify(src, 'bill_target_far', 'error')
            IC.server.notify(bill.from, 'bill_target_far', 'error')
            return
        end
    end

    if not IC.removeMoney(src, Config.Economy.billAccount, bill.amount, 'icecream-bill') then
        IC.server.notify(src, 'bill_no_money', 'error')
        if employeeOnline then
            IC.server.notify(bill.from, 'bill_declined', 'error', GetPlayerName(src) or '?')
        end
        return
    end

    IC.server.notify(src, 'bill_you_paid', 'success', IC.money(bill.amount))

    -- الموظف موجود؟ يأخذ بقشيشه والشركة نصيبها. غير موجود؟ كل المبلغ للشركة.
    if employeeOnline then
        local player = IC.getPlayer(bill.from)
        if player then
            IC.society.settleSale(bill.branch, bill.from, player, bill.amount, 'bill', 1, 'bill')
            IC.server.notify(bill.from, 'bill_accepted', 'success', GetPlayerName(src) or '?', IC.money(bill.amount))
        else
            IC.society.add(bill.branch, bill.amount)
        end
    else
        IC.society.add(bill.branch, bill.amount)
        IC.db.recordSale(bill.branch, bill.citizenid, 'bill', 1, bill.amount, 'bill')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, bill in pairs(bills) do
        if bill.from == src or bill.to == src then bills[id] = nil end
    end
end)

-- ────────────────────────────────────────────────────────────
-- قائمة الأسعار (تُبنى من الوصفات — مصدر واحد للحقيقة)
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:getPriceList', function(source)
    local player = IC.getPlayer(source)
    if not player or player.job.name ~= Config.Job.name then return {} end

    local list = {}
    for item, recipe in pairs(Recipes.byResult) do
        if recipe.sellPrice and recipe.sellPrice > 0 then
            list[#list + 1] = { item = item, label = recipe.label, price = recipe.sellPrice }
        end
    end
    table.sort(list, function(a, b) return a.price > b.price end)
    return list
end)
