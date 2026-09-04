---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Register, display case, tickets, bills, statistics.
]]

MN = MN or {}

-- ═══════════════════════════════════════════════════════════════
-- Display case: staff move finished goods in and out of sale
-- ═══════════════════════════════════════════════════════════════

function MN.openDisplayCase()
    if not MN.checkAccess(MN.PERM.REGISTER) then return end

    local menu = Products.menu()
    local options = {}

    for i = 1, #menu do
        local product = menu[i]
        local carried = MN.itemCount(product.name)
        local onShelf = MN.stock[product.name] or 0

        options[#options + 1] = {
            title = Products.label(product.name),
            description = ('%s • %s%s'):format(
                T('shop_stock', onShelf), T('currency'), MN.money(product.price)),
            icon = 'store',
            iconColor = onShelf > 0 and Config.UI.theme.leaf or '#8a8a8a',
            metadata = {
                { label = T('shop_cart'), value = tostring(carried) },
                { label = T('shop_stock', ''):gsub('%s*:%s*$', ''), value = tostring(onShelf) },
            },
            onSelect = function() MN.stockDialog(product, carried, onShelf) end,
        }
    end

    lib.registerContext({
        id = 'mn_display',
        title = T('register_menu'),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_display')
end

---@param product table
---@param carried number
---@param onShelf number
function MN.stockDialog(product, carried, onShelf)
    local options = {}

    if carried > 0 then
        options[#options + 1] = {
            title = T('shop_add'),
            icon = 'arrow-up-from-bracket',
            iconColor = Config.UI.theme.leaf,
            onSelect = function()
                local input = lib.inputDialog(Products.label(product.name), { {
                    type = 'slider', label = T('shop_qty'),
                    default = math.min(carried, 5), min = 1, max = math.min(carried, 50),
                } })
                if not input or not input[1] then return end

                local result = lib.callback.await('mangonazlet:server:stockDisplay', false,
                    product.name, math.floor(input[1]))
                if result then
                    MN.refreshState()
                    SetTimeout(150, MN.openDisplayCase)
                end
            end,
        }
    end

    if onShelf > 0 then
        options[#options + 1] = {
            title = T('shop_remove'),
            icon = 'arrow-down-to-bracket',
            onSelect = function()
                local input = lib.inputDialog(Products.label(product.name), { {
                    type = 'slider', label = T('shop_qty'),
                    default = 1, min = 1, max = math.min(onShelf, 50),
                } })
                if not input or not input[1] then return end

                local ok = lib.callback.await('mangonazlet:server:unstockDisplay', false,
                    product.name, math.floor(input[1]))
                if ok then
                    MN.refreshState()
                    SetTimeout(150, MN.openDisplayCase)
                end
            end,
        }
    end

    if #options == 0 then
        MN.notify(T('shop_empty_cart'), 'inform')
        return
    end

    lib.registerContext({
        id = 'mn_stock_item',
        title = Products.label(product.name),
        menu = 'mn_display',
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_stock_item')
end

-- ═══════════════════════════════════════════════════════════════
-- Customer tickets
-- ═══════════════════════════════════════════════════════════════

function MN.openTickets()
    if not MN.checkAccess(MN.PERM.REGISTER) then return end

    MN.refreshTickets()
    Wait(120)   -- let the callback land before drawing the list

    local tickets = MN.tickets
    if #tickets == 0 then
        MN.notify(T('register_none'), 'inform')
        return
    end

    local now = os.time()
    local options = {}

    for i = 1, #tickets do
        local ticket = tickets[i]
        local have = MN.itemCount(ticket.item)
        local ready = have >= ticket.count
        local left = math.max((ticket.expires or now) - now, 0)

        options[#options + 1] = {
            title = T('order_line', ticket.count, Products.label(ticket.item)),
            description = ('%s • %s'):format(
                T('order_value', MN.money(ticket.price)), T('order_time', left)),
            icon = ready and 'circle-check' or 'circle-exclamation',
            iconColor = ready and Config.UI.theme.leaf or '#c0392b',
            progress = math.floor((left / math.max(Config.Tickets.expiry, 1)) * 100),
            colorScheme = ready and 'green' or 'red',
            metadata = { { label = T('craft_yield'), value = ('%s / %s'):format(have, ticket.count) } },
            onSelect = function()
                local served = lib.callback.await('mangonazlet:server:serveTicket', false, ticket.id)
                if served then MN.refreshTickets() end
            end,
        }
    end

    lib.registerContext({
        id = 'mn_tickets',
        title = T('order_list'),
        menu = 'mn_register',
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_tickets')
end

-- ═══════════════════════════════════════════════════════════════
-- Billing a nearby player
-- ═══════════════════════════════════════════════════════════════

---@return number|nil serverId
local function nearestPlayer()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDistance

    for _, playerId in ipairs(GetActivePlayers()) do
        local other = GetPlayerPed(playerId)
        if other ~= ped and DoesEntityExist(other) then
            local distance = #(coords - GetEntityCoords(other))
            if distance <= Config.Billing.maxDistance and (not closestDistance or distance < closestDistance) then
                closest, closestDistance = GetPlayerServerId(playerId), distance
            end
        end
    end
    return closest
end

local function billDialog()
    local input = lib.inputDialog(T('bill_title'), {
        { type = 'number', label = T('bill_player'), default = nearestPlayer(),
          required = true, min = 1, icon = 'user' },
        { type = 'number', label = T('bill_amount'), required = true,
          min = 1, max = Config.Billing.maxAmount, icon = 'dollar-sign' },
        { type = 'input', label = T('bill_reason'), max = 60, icon = 'receipt' },
    })
    if not input then return end

    lib.callback.await('mangonazlet:server:createBill', false, {
        target = math.floor(input[1] or 0),
        amount = math.floor(input[2] or 0),
        reason = input[3] or '',
    })
end

RegisterNetEvent('mangonazlet:client:bill', function(bill)
    if type(bill) ~= 'table' then return end

    local content = T('bill_incoming', bill.from or '?', MN.money(bill.amount or 0))
    if bill.reason and bill.reason ~= '' then
        content = ('%s\n\n_%s_'):format(content, bill.reason)
    end

    local answer = lib.alertDialog({
        header = T('brand'),
        content = content,
        centered = true,
        cancel = true,
        labels = { confirm = T('bill_pay'), cancel = T('bill_decline') },
    })

    TriggerServerEvent('mangonazlet:server:answerBill', bill.id, answer == 'confirm')
end)

RegisterNetEvent('mangonazlet:client:billClosed', function()
    if type(lib.closeAlertDialog) == 'function' then lib.closeAlertDialog() end
end)

-- ═══════════════════════════════════════════════════════════════
-- Price list and statistics
-- ═══════════════════════════════════════════════════════════════

local function openPriceList()
    local list = lib.callback.await('mangonazlet:server:priceList', false)
    if type(list) ~= 'table' or #list == 0 then
        MN.notify(T('stats_none'), 'inform')
        return
    end

    local options = {}
    for i = 1, #list do
        options[i] = {
            title = Products.label(list[i].item),
            description = ('%s%s'):format(T('currency'), MN.money(list[i].price)),
            icon = 'tag',
            readOnly = true,
        }
    end

    lib.registerContext({
        id = 'mn_prices', title = T('price_list'), menu = 'mn_register',
        position = Config.UI.contextPosition, options = options,
    })
    lib.showContext('mn_prices')
end

---@param parent? string
function MN.openStats(parent)
    local stats = lib.callback.await('mangonazlet:server:stats', false)
    if not stats then
        MN.notify(T('stats_none'), 'inform')
        return
    end

    local currency = T('currency')
    local options = {
        { title = T('stats_today'),  description = currency .. MN.money(stats.today),  icon = 'calendar-day',  readOnly = true },
        { title = T('stats_week'),   description = currency .. MN.money(stats.week),   icon = 'calendar-week', readOnly = true },
        { title = T('stats_orders'), description = tostring(stats.orders or 0),        icon = 'receipt',       readOnly = true },
        { title = T('stats_you'),    description = currency .. MN.money(stats.yours or 0), icon = 'user',      readOnly = true },
    }

    if stats.topItem then
        options[#options + 1] = {
            title = T('stats_top_item'),
            description = ('%s (%s)'):format(Products.label(stats.topItem), stats.topItemQty or 0),
            icon = 'trophy', readOnly = true,
        }
    end
    if stats.topStaff then
        options[#options + 1] = {
            title = T('stats_top_staff'),
            description = ('%s — %s%s'):format(stats.topStaff, currency, MN.money(stats.topStaffTotal or 0)),
            icon = 'medal', readOnly = true,
        }
    end

    lib.registerContext({
        id = 'mn_stats', title = T('stats_title'), menu = parent,
        position = Config.UI.contextPosition, options = options,
    })
    lib.showContext('mn_stats')
end

-- ═══════════════════════════════════════════════════════════════
-- Register menu
-- ═══════════════════════════════════════════════════════════════

function MN.openRegister()
    if not MN.checkAccess(MN.PERM.REGISTER) then return end

    local options = {}

    if Config.Tickets.enabled then
        options[#options + 1] = {
            title = T('register_orders'),
            description = T('register_orders_d', #MN.tickets),
            icon = 'bell-concierge',
            iconColor = #MN.tickets > 0 and Config.UI.theme.mango or nil,
            arrow = true,
            onSelect = MN.openTickets,
        }
    end

    if Config.Billing.enabled then
        options[#options + 1] = {
            title = T('register_bill'),
            description = T('register_bill_d'),
            icon = 'file-invoice-dollar',
            onSelect = billDialog,
        }
    end

    options[#options + 1] = {
        title = T('price_list'), icon = 'tags', arrow = true, onSelect = openPriceList,
    }
    options[#options + 1] = {
        title = T('register_stats'), icon = 'chart-simple', arrow = true,
        onSelect = function() MN.openStats('mn_register') end,
    }

    lib.registerContext({
        id = 'mn_register',
        title = T('register_title'),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_register')
end
