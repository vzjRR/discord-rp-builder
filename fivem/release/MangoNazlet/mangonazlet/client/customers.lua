---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — The customer standing at the counter.

    A ticket is only real to a player if somebody is visibly waiting for it, so
    the oldest open ticket gets a ped at the counter that staff can hand the
    order straight to. The ped is purely local: the ticket itself lives on the
    server and delivery is confirmed there.
]]

MN = MN or {}

local ped = nil
local option = nil
local announced = false

---The ticket the waiting customer represents.
---@return table|nil
local function frontTicket()
    return MN.tickets and MN.tickets[1] or nil
end

local function despawn()
    if option and ped and DoesEntityExist(ped) and MN.target == MN.TGT.OX then
        pcall(function() exports.ox_target:removeLocalEntity(ped, option) end)
    end
    option = nil

    if ped and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
    ped = nil
    announced = false
end

local function spawn()
    if ped and DoesEntityExist(ped) then return end

    local stand = Locations.shop.customer.stand
    if not stand then return end

    local model = Locations.customerModels[math.random(#Locations.customerModels)]
    local hash = MN.loadModel(model)
    if not hash then return end

    local created = CreatePed(4, hash, stand.x, stand.y, stand.z - 1.0, stand.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(created) then return end

    SetEntityAsMissionEntity(created, true, true)
    SetBlockingOfNonTemporaryEvents(created, true)
    SetPedCanRagdollFromPlayerImpact(created, false)
    SetPedDiesWhenInjured(created, false)
    SetEntityInvincible(created, true)
    FreezeEntityPosition(created, true)
    TaskStartScenarioInPlace(created, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    ped = created

    -- Hand the order over directly, without walking to the till.
    if MN.target == MN.TGT.OX then
        option = 'mn_customer_hand'
        exports.ox_target:addLocalEntity(created, { {
            name = option,
            label = T('order_hand'),
            icon = 'hand-holding-heart',
            distance = 2.5,
            canInteract = function()
                return MN.isWorking()
                    and Permissions.can(MN.job.grade, MN.PERM.REGISTER)
                    and frontTicket() ~= nil
                    and not MN.busy
            end,
            onSelect = function()
                local ticket = frontTicket()
                if not ticket then
                    MN.notify(T('register_none'), 'inform')
                    return
                end

                local served = lib.callback.await('mangonazlet:server:serveTicket', false, ticket.id)
                if served then MN.refreshTickets() end
            end,
        } })
    end
end

-- Keep exactly one customer visible while tickets are open and staff are close.
CreateThread(function()
    while true do
        local sleep = 3000

        if MN.isWorking() and MN.nearShop and Config.Tickets.enabled then
            local waiting = MN.tickets and #MN.tickets or 0
            local distance = #(GetEntityCoords(PlayerPedId()) - Locations.shop.centre)

            if waiting > 0 and distance < 60.0 then
                sleep = 2000
                if not ped or not DoesEntityExist(ped) then
                    spawn()
                    if ped and not announced then
                        MN.notify(T('order_waiting'), 'inform')
                        announced = true
                    end
                end
            else
                despawn()
            end
        elseif ped then
            despawn()
        end

        Wait(sleep)
    end
end)

-- The queue emptied: send the customer on their way.
AddEventHandler('mangonazlet:client:ticketsChanged', function(tickets)
    if (not tickets or #tickets == 0) and ped then despawn() end
end)

-- An admin moved the shop: the ped has to move with it.
AddEventHandler('mangonazlet:client:relocated', despawn)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    despawn()
end)
