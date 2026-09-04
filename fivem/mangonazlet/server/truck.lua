---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — The mobile truck.

    Selling away from the shop pays better because it costs time and a rental
    fee. Every sale is checked against a real hotspot, a real product and a real
    cooldown before any money moves.
]]

MN = MN or {}

local active = {}    -- [source] = { takenAt, netId }
local lastSale = {}  -- [source] = timestamp

lib.callback.register('mangonazlet:server:truckTake', function(source)
    local src = source

    if not Config.Truck.enabled then return false end
    if not MN.rateLimit(src, 'truck', 3000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local spawn = Locations.shop.truck.spawn
    local player = MN.gate(src, nil, vec3(spawn.x, spawn.y, spawn.z), 14.0)
    if not player then return false end

    if player.job.grade < Config.Truck.requireGrade then
        MN.notify(src, 'no_permission', 'error')
        return false
    end

    if active[src] then
        MN.notify(src, 'truck_taken', 'inform')
        return false
    end

    local fee = Config.Truck.fee
    if fee > 0 then
        if not MN.business.canAfford(fee) then
            MN.notify(src, 'truck_short', 'error')
            return false
        end
        MN.business.debit(fee)
        MN.logs.money(player, Locations.shop.id, 'truck_fee', fee, MN.business.balance())
    end

    active[src] = { takenAt = os.time() }
    MN.notify(src, 'truck_taken', 'success')
    return { model = Config.Truck.model, spawn = spawn }
end)

---Bind the spawned vehicle to its owner. Without the checks below a player
---could pass any network id and stamp state onto someone else's vehicle.
RegisterNetEvent('mangonazlet:server:truckRegister', function(netId)
    local src = source
    if not MN.rateLimit(src, 'truckregister', 1000) then return end

    local truck = active[src]
    if not truck then return end

    local id = MN.int(netId, 1)
    if not id then return end

    local entity = NetworkGetEntityFromNetworkId(id)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    if GetEntityType(entity) ~= 2 then
        MN.reject(src, 'truck_entity', 'not a vehicle')
        return
    end
    if GetEntityModel(entity) ~= joaat(Config.Truck.model) then
        MN.reject(src, 'truck_entity', 'model mismatch')
        return
    end

    local spawn = Locations.shop.truck.spawn
    if #(GetEntityCoords(entity) - vec3(spawn.x, spawn.y, spawn.z)) > 25.0 then
        MN.reject(src, 'truck_entity', 'not at the depot')
        return
    end

    truck.netId = id
    Entity(entity).state:set('mangonazlet', { owner = src }, true)
    MN.debug('truck %s bound to %s', id, src)
end)

lib.callback.register('mangonazlet:server:truckStore', function(source)
    local src = source
    if not MN.rateLimit(src, 'truckstore', 2000) then return false end

    local truck = active[src]
    if not truck then
        MN.notify(src, 'truck_not_yours', 'error')
        return false
    end

    local park = Locations.shop.truck.spawn
    if not MN.isNear(src, vec3(park.x, park.y, park.z), 18.0) then
        MN.notify(src, 'too_far', 'error')
        return false
    end

    active[src] = nil
    MN.notify(src, 'truck_stored', 'success')
    return { netId = truck.netId }
end)

lib.callback.register('mangonazlet:server:truckSell', function(source, payload)
    local src = source

    if not Config.Truck.enabled then return false end
    if type(payload) ~= 'table' then
        MN.reject(src, 'payload', 'truck sale')
        return false
    end

    if not MN.rateLimit(src, 'trucksell', 1000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    if not active[src] then
        MN.notify(src, 'truck_not_yours', 'error')
        return false
    end

    local player = MN.getPlayer(src)
    if not player or player.job.name ~= Permissions.job then
        MN.notify(src, 'not_employee', 'error')
        return false
    end
    if Config.RequireDuty and not player.job.onduty then
        MN.notify(src, 'not_on_duty', 'error')
        return false
    end

    local last = lastSale[src]
    if last and (os.time() - last) < Config.Truck.saleCooldown then
        MN.notify(src, 'truck_wait', 'error')
        return false
    end

    local spotIndex = MN.int(payload.spot, 1, #Locations.truckSpots)
    if not spotIndex then
        MN.reject(src, 'truck_spot', tostring(payload.spot))
        return false
    end
    local spot = Locations.truckSpots[spotIndex]
    if not MN.isNear(src, spot.coords, spot.radius + Config.Truck.maxDistance) then
        MN.reject(src, 'distance', 'truck spot')
        MN.notify(src, 'too_far', 'error')
        return false
    end

    local product = type(payload.item) == 'string' and Products.get(payload.item) or nil
    if not product or not product.price or product.price <= 0 then
        MN.reject(src, 'truck_item', tostring(payload.item))
        return false
    end

    local quantity = MN.int(payload.quantity, 1, 10)
    if not quantity then return false end

    local ok, ratio = MN.crafting.takeProduct(src, product.name, quantity)
    if not ok then
        MN.notify(src, 'truck_nostock', 'error')
        return false
    end

    lastSale[src] = os.time()

    local total = math.floor(product.price * quantity * Config.Truck.priceMultiplier * ratio)
    MN.business.settle(src, player, total, product.name, quantity, MN.CHANNEL.TRUCK)

    MN.notify(src, 'truck_sold', 'success', quantity, Products.label(product.name), MN.money(total))
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    active[src] = nil
    lastSale[src] = nil
end)
