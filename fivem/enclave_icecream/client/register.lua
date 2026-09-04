---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — الكاشير
    ---------------------------
    قائمة الكاشير: الطلبات، الفوترة اليدوية، قائمة الأسعار، الإحصائيات.
    استقبال الفواتير عند اللاعب الزبون كذلك.
]]

IC = IC or {}
IC.client = IC.client or {}

-- ────────────────────────────────────────────────────────────
-- الفوترة اليدوية (جانب الموظف)
-- ────────────────────────────────────────────────────────────

---يرجّع أقرب لاعب مع المسافة
---@return number|nil serverId, number distance
local function getClosestPlayer()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist

    for _, playerId in ipairs(GetActivePlayers()) do
        local target = GetPlayerPed(playerId)
        if target ~= ped and DoesEntityExist(target) then
            local dist = #(coords - GetEntityCoords(target))
            if dist <= Config.Register.maxDistance and (not closestDist or dist < closestDist) then
                closest, closestDist = GetPlayerServerId(playerId), dist
            end
        end
    end

    return closest, closestDist or math.huge
end

---@param branch table
local function openBillDialog(branch)
    local closest = getClosestPlayer()

    local input = lib.inputDialog(L('bill_player_title'), {
        {
            type = 'number',
            label = L('bill_player_input'),
            default = closest,
            required = true,
            min = 1,
            icon = 'user',
        },
        {
            type = 'number',
            label = L('bill_amount_input'),
            required = true,
            min = 1,
            max = Config.Register.maxAmount,
            icon = 'dollar-sign',
        },
        {
            type = 'input',
            label = L('bill_reason_input'),
            max = 60,
            icon = 'receipt',
        },
    })

    if not input then return end

    lib.callback.await('icecream:server:createBill', false, {
        branch = branch.id,
        target = math.floor(input[1] or 0),
        amount = math.floor(input[2] or 0),
        reason = input[3] or '',
    })
end

-- ────────────────────────────────────────────────────────────
-- الفوترة (جانب الزبون)
-- ────────────────────────────────────────────────────────────

RegisterNetEvent('icecream:client:receiveBill', function(bill)
    if type(bill) ~= 'table' then return end

    local content = L('bill_received', bill.from or '?', IC.money(bill.amount or 0))
    if bill.reason and bill.reason ~= '' then
        content = ('%s\n\n_%s_'):format(content, bill.reason)
    end

    local accepted = lib.alertDialog({
        header = bill.shop or L('job_label'),
        content = content,
        centered = true,
        cancel = true,
        labels = { confirm = 'دفع', cancel = 'رفض' },
    })

    TriggerServerEvent('icecream:server:respondBill', bill.id, accepted == 'confirm')
end)

RegisterNetEvent('icecream:client:closeBill', function()
    -- ox_lib أضاف closeAlertDialog في إصدارات لاحقة — نستدعيه فقط لو موجود
    if type(lib.closeAlertDialog) == 'function' then
        lib.closeAlertDialog()
    end
end)

-- ────────────────────────────────────────────────────────────
-- قائمة الأسعار
-- ────────────────────────────────────────────────────────────

local function openPriceList(branch)
    local list = lib.callback.await('icecream:server:getPriceList', false)
    if type(list) ~= 'table' or #list == 0 then
        IC.notify(L('stats_none'), 'inform')
        return
    end

    local options = {}
    for i = 1, #list do
        options[i] = {
            title = list[i].label,
            description = ('$%s'):format(IC.money(list[i].price)),
            icon = 'tag',
            readOnly = true,
        }
    end

    lib.registerContext({
        id = 'icecream_prices',
        title = L('price_list_title'),
        menu = 'icecream_register',
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_prices')
end

-- ────────────────────────────────────────────────────────────
-- الإحصائيات
-- ────────────────────────────────────────────────────────────

---@param branch table
---@param parentMenu? string
function IC.client.openStats(branch, parentMenu)
    local stats = lib.callback.await('icecream:server:getStats', false, branch.id)
    if not stats then
        IC.notify(L('stats_none'), 'inform')
        return
    end

    local options = {
        { title = L('stats_today'), description = ('$%s'):format(IC.money(stats.today)), icon = 'calendar-day', readOnly = true },
        { title = L('stats_week'),  description = ('$%s'):format(IC.money(stats.week)),  icon = 'calendar-week', readOnly = true },
        { title = L('stats_orders'), description = tostring(stats.orders or 0), icon = 'receipt', readOnly = true },
        { title = L('stats_your_sales'), description = ('$%s'):format(IC.money(stats.yours or 0)), icon = 'user', readOnly = true },
    }

    if stats.topItem then
        local recipe = Recipes.byResult[stats.topItem]
        options[#options + 1] = {
            title = L('stats_top_item'),
            description = ('%s (%s)'):format(recipe and recipe.label or stats.topItem, stats.topItemQty or 0),
            icon = 'trophy', readOnly = true,
        }
    end
    if stats.topEmployee then
        options[#options + 1] = {
            title = L('stats_top_employee'),
            description = ('%s — $%s'):format(stats.topEmployee, IC.money(stats.topEmployeeTotal or 0)),
            icon = 'medal', readOnly = true,
        }
    end

    lib.registerContext({
        id = 'icecream_stats',
        title = L('stats_title'),
        menu = parentMenu,
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_stats')
end

-- ────────────────────────────────────────────────────────────
-- القائمة الرئيسية للكاشير
-- ────────────────────────────────────────────────────────────

---@param branch table
function IC.client.openRegisterMenu(branch)
    if not IC.checkAccess('canRegister') then return end

    local pending = IC.client.getOrders(branch.id)

    local options = {}

    if Config.Orders.enabled then
        options[#options + 1] = {
            title = L('register_orders'),
            description = L('register_orders_desc', #pending),
            icon = 'bell-concierge',
            iconColor = #pending > 0 and '#facc15' or nil,
            arrow = true,
            onSelect = function() IC.client.openOrdersMenu(branch) end,
        }
    end

    if Config.Register.enabled then
        options[#options + 1] = {
            title = L('register_bill'),
            description = L('register_bill_desc'),
            icon = 'file-invoice-dollar',
            onSelect = function() openBillDialog(branch) end,
        }
    end

    options[#options + 1] = {
        title = L('register_prices'),
        icon = 'tags',
        arrow = true,
        onSelect = function() openPriceList(branch) end,
    }

    options[#options + 1] = {
        title = L('register_stats'),
        icon = 'chart-simple',
        arrow = true,
        onSelect = function() IC.client.openStats(branch, 'icecream_register') end,
    }

    lib.registerContext({
        id = 'icecream_register',
        title = L('register_menu_title'),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_register')
end
