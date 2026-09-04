---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Client core: blip, shared state, world reporting, melt warning.
]]

MN = MN or {}

MN.stock = {}         -- live counter stock, pushed by the server
MN.tickets = {}       -- open customer tickets

local blip

-- ═══════════════════════════════════════════════════════════════
-- Blip
-- ═══════════════════════════════════════════════════════════════

local function createBlip()
    if not Config.UI.blip then return end
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end

    local shop = Locations.shop
    blip = AddBlipForCoord(shop.centre.x, shop.centre.y, shop.centre.z)
    SetBlipSprite(blip, shop.blip.sprite)
    SetBlipColour(blip, shop.blip.colour)
    SetBlipScale(blip, shop.blip.scale)
    SetBlipAsShortRange(blip, shop.blip.shortRange ~= false)
    SetBlipDisplay(blip, 4)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Locations.label(shop))
    EndTextCommandSetBlipName(blip)
end

local function removeBlip()
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blip = nil
end

-- ═══════════════════════════════════════════════════════════════
-- Live state from the server
-- ═══════════════════════════════════════════════════════════════

RegisterNetEvent('mangonazlet:client:stock', function(stock)
    if type(stock) ~= 'table' then return end
    MN.stock = stock
    TriggerEvent('mangonazlet:client:stockChanged', stock)
end)

RegisterNetEvent('mangonazlet:client:tickets', function(tickets)
    MN.tickets = type(tickets) == 'table' and tickets or {}
    TriggerEvent('mangonazlet:client:ticketsChanged', MN.tickets)
end)

---Ask the server for a fresh snapshot.
function MN.refreshState()
    lib.callback('mangonazlet:server:state', false, function(state)
        if type(state) ~= 'table' then return end
        MN.stock = state.stock or {}
        TriggerEvent('mangonazlet:client:stockChanged', MN.stock)
    end)
end

---Refresh the ticket list when it matters.
function MN.refreshTickets()
    if not MN.isStaff() then return end
    lib.callback('mangonazlet:server:tickets', false, function(tickets)
        MN.tickets = type(tickets) == 'table' and tickets or {}
        TriggerEvent('mangonazlet:client:ticketsChanged', MN.tickets)
    end)
end

-- Placements saved by an admin arrive here and are applied live.
RegisterNetEvent('mangonazlet:client:placements', function(placements)
    Locations.applyOverrides(placements)
    createBlip()
    TriggerEvent('mangonazlet:client:relocated')
end)

-- ═══════════════════════════════════════════════════════════════
-- Proximity — everything expensive only runs near the shop
-- ═══════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        local sleep = 3000
        local distance = #(GetEntityCoords(PlayerPedId()) - Locations.shop.centre)
        local near = distance < 100.0

        if near ~= MN.nearShop then
            MN.nearShop = near
            TriggerEvent('mangonazlet:client:proximity', near)
            if near then MN.refreshState() end
        end

        if near then sleep = 1000 end
        Wait(sleep)
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- World report (feeds the ticket price multiplier)
-- ═══════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(60000)
        if MN.isWorking() then
            TriggerServerEvent('mangonazlet:server:world', GetClockHours(), GetPrevWeatherTypeHashName())
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- Melting warning
-- ═══════════════════════════════════════════════════════════════

if Config.Melting.enabled then
    CreateThread(function()
        local warned = false

        while true do
            Wait(Config.Melting.checkInterval * 1000)

            if MN.isWorking() and MN.inventory == MN.INV.OX then
                local melting = false

                for i = 1, #Products.all do
                    local product = Products.all[i]
                    if product.perishable then
                        local slots = exports.ox_inventory:Search('slots', product.name)
                        if type(slots) == 'table' then
                            for _, slot in ipairs(slots) do
                                local madeAt = slot.metadata and tonumber(slot.metadata.madeAt)
                                if madeAt and (os.time() - madeAt) / 60 > Config.Melting.freshMinutes then
                                    melting = true
                                    break
                                end
                            end
                        end
                        if melting then break end
                    end
                end

                if melting and not warned then
                    MN.notify(T('melt_warning'), 'warning')
                    warned = true
                elseif not melting then
                    warned = false
                end
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- /mn:where — put a waypoint on the shop
-- Open to everyone: finding the restaurant is not an admin action.
-- ═══════════════════════════════════════════════════════════════

RegisterCommand('mn:where', function()
    local centre = Locations.shop.centre
    SetNewWaypoint(centre.x, centre.y)
    MN.notify(T('where_set'), 'success')
end, false)

TriggerEvent('chat:addSuggestion', '/mn:where', T('where_help'))

-- ═══════════════════════════════════════════════════════════════
-- Standalone economy hook
-- ═══════════════════════════════════════════════════════════════

RegisterNetEvent('mangonazlet:client:money', function(account, amount, reason)
    -- No framework economy to touch. A server running standalone can listen for
    -- this event from its own resource and move money however it likes.
    MN.debug('money event: %s %s (%s)', account, amount, reason or '')
end)

-- ═══════════════════════════════════════════════════════════════
-- Lifecycle
-- ═══════════════════════════════════════════════════════════════

AddEventHandler('mangonazlet:client:loaded', function()
    createBlip()
    MN.refreshState()
end)

AddEventHandler('mangonazlet:client:jobChanged', function(job)
    if job.name == Permissions.job and job.onduty then
        MN.refreshTickets()
    end
end)

CreateThread(function()
    Wait(1500)
    -- Apply placements that were saved before this client connected.
    local placements = GlobalState.mnPlacements
    if type(placements) == 'table' then Locations.applyOverrides(placements) end
    createBlip()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    removeBlip()
    MN.stopAnim()
    if MN.has.oxLib then lib.hideTextUI() end
end)
