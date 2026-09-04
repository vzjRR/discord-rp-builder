---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Customer ordering menu (NUI).

    The interface is presentation only. It sends item names and quantities; the
    server prices the basket, checks stock, charges and hands over. A modified
    interface can change what it asks for, never what it pays.
]]

MN = MN or {}

local open = false

---Close the menu and release focus. Safe to call when already closed.
local function close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

---Localised copy of the menu for whichever language this player runs.
---@param products table[]
---@return table[]
local function localise(products)
    local language = Config.Locale
    local out = {}

    for i = 1, #products do
        local product = products[i]
        out[#out + 1] = {
            item = product.item,
            label = (product.label and (product.label[language] or product.label.en)) or product.item,
            desc = (product.desc and (product.desc[language] or product.desc.en)) or '',
            price = product.price,
            category = product.category,
            image = product.image,
        }
    end
    return out
end

function MN.openShop()
    if open or MN.busy then return end
    if not Config.Counter.enabled then return end

    local data = lib.callback.await('mangonazlet:server:menu', false)
    if type(data) ~= 'table' then
        MN.notify(T('shop_closed'), 'error')
        return
    end

    if #data.products == 0 then
        MN.notify(T('shop_closed'), 'error')
        return
    end

    open = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'open',
        locale = MN.localeTable(),
        direction = MN.dir(),
        theme = Config.UI.theme,
        products = localise(data.products),
        stock = data.stock,
        requireStock = data.requireStock,
        payment = { cash = data.cash, bank = data.bank },
        maxPerCheckout = data.maxPerCheckout,
    })
end

-- Live stock updates reach an open menu without reopening it.
AddEventHandler('mangonazlet:client:stockChanged', function(stock)
    if not open then return end
    SendNUIMessage({ action = 'stock', stock = stock })
end)

-- ═══════════════════════════════════════════════════════════════
-- NUI callbacks
-- ═══════════════════════════════════════════════════════════════

RegisterNUICallback('close', function(_, cb)
    close()
    cb({ ok = true })
end)

RegisterNUICallback('checkout', function(data, cb)
    -- Shape the payload defensively: the interface is the one part of this
    -- resource a player can rewrite, so nothing it sends is trusted here or
    -- on the server.
    if type(data) ~= 'table' or type(data.basket) ~= 'table' then
        cb({ ok = false })
        return
    end

    local basket = {}
    for i = 1, #data.basket do
        local line = data.basket[i]
        if type(line) == 'table' and type(line.item) == 'string' then
            local quantity = tonumber(line.quantity)
            if quantity and quantity >= 1 then
                basket[#basket + 1] = {
                    item = line.item,
                    quantity = math.floor(quantity),
                }
            end
        end
    end

    if #basket == 0 then
        cb({ ok = false })
        return
    end

    local result = lib.callback.await('mangonazlet:server:checkout', false, {
        basket = basket,
        account = data.account == 'cash' and 'cash' or 'bank',
    })

    if result then
        close()
        cb({ ok = true, total = result.total })
    else
        -- Stay open so the customer can adjust; refresh stock in case that was why.
        MN.refreshState()
        cb({ ok = false })
    end
end)

-- The interface closes itself on Escape. This is only the safety net for the
-- case where app.js failed to load and the player would otherwise be left with
-- their input locked to a blank screen. Ten checks a second is plenty for that
-- and costs nothing; a per-frame loop here would not.
CreateThread(function()
    while true do
        if open then
            if IsControlJustReleased(0, 200) or IsControlJustReleased(0, 202) then
                close()
            end
            Wait(100)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    if open then SetNuiFocus(false, false) end
end)
