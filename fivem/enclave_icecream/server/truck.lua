---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — عربة المثلجات المتنقلة
    ------------------------------------------
    البيع في نقاط ساخنة على الخريطة بسعر أعلى مقابل الوقت والمخاطرة.
    السيرفر يتحقق من: النقطة، المسافة، وجود المنتج، والمهلة بين البيعات.
]]

IC = IC or {}

-- العربات الخارجة حاليًا: [src] = { netId, branch, plate }
local activeTrucks = {}
-- آخر بيعة لكل لاعب: [src] = timestamp
local lastSale = {}

---يتحقق من صحة رقم نقطة البيع
---@param index any
---@return table|nil
local function resolveSpot(index)
    local idx = IC.toInt(index, 1, #Locations.TruckSpots)
    return idx and Locations.TruckSpots[idx] or nil
end

-- ────────────────────────────────────────────────────────────
-- إخراج / تخزين العربة
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:takeTruck', function(source, branchId)
    local src = source

    if not Config.Truck.enabled then return false end
    if not IC.rateLimit(src, 'truck', 3000) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end

    local branch = IC.server.resolveBranch(branchId)
    if not branch or not branch.truck then return false end

    local player = IC.server.gate(src, nil, vec3(branch.truck.spawn.x, branch.truck.spawn.y, branch.truck.spawn.z), 12.0)
    if not player then return false end

    if player.job.grade < Config.Truck.requireGrade then
        IC.server.notify(src, 'no_permission', 'error')
        return false
    end

    if activeTrucks[src] then
        IC.server.notify(src, 'truck_taken', 'inform')
        return false
    end

    local fee = Config.Truck.rentalFee
    if fee > 0 then
        if not IC.society.canAfford(branch.id, fee) then
            IC.server.notify(src, 'truck_no_funds', 'error')
            return false
        end
        IC.society.take(branch.id, fee)
        IC.logs.money(player, branch.id, 'truck_fee', fee, IC.society.getBalance(branch.id))
    end

    activeTrucks[src] = { branch = branch.id, takenAt = os.time() }
    IC.server.notify(src, 'truck_taken', 'success')
    return { model = Config.Truck.model, spawn = branch.truck.spawn }
end)

-- العميل يبلّغ عن netId العربة بعد إنشائها (لربطها باللاعب)
RegisterNetEvent('icecream:server:registerTruck', function(netId)
    local src = source
    local truck = activeTrucks[src]
    if not truck then return end

    local id = IC.toInt(netId, 1)
    if not id then return end

    local entity = NetworkGetEntityFromNetworkId(id)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    -- بلا هذه الفحوصات يقدر اللاعب يمرّر netId أي مركبة (حتى مركبة لاعب ثانٍ)
    -- ويكتب عليها حالة مشتركة. نتأكد أنها فعلًا العربة التي أخرجناها له للتو:
    if GetEntityType(entity) ~= 2 then                        -- 2 = مركبة
        IC.logs.exploit(src, 'invalid_truck_entity', 'ليست مركبة')
        return
    end
    if GetEntityModel(entity) ~= joaat(Config.Truck.model) then
        IC.logs.exploit(src, 'invalid_truck_entity', 'موديل مختلف')
        return
    end

    local branch = Locations.getBranch(truck.branch)
    if not branch or #(GetEntityCoords(entity) - vec3(branch.truck.spawn.x, branch.truck.spawn.y, branch.truck.spawn.z)) > 20.0 then
        IC.logs.exploit(src, 'invalid_truck_entity', 'بعيدة عن نقطة الإخراج')
        return
    end

    truck.netId = id
    truck.entity = entity
    Entity(entity).state:set('icecreamTruck', { owner = src, branch = truck.branch }, true)
    IC.debug('ربطت عربة netId=%s باللاعب %s', id, src)
end)

lib.callback.register('icecream:server:storeTruck', function(source, branchId)
    local src = source
    local truck = activeTrucks[src]
    if not truck then
        IC.server.notify(src, 'truck_not_yours', 'error')
        return false
    end

    local branch = IC.server.resolveBranch(branchId)
    if not branch or branch.id ~= truck.branch then return false end

    if not IC.isNear(src, branch.truck.park, 15.0) then
        IC.server.notify(src, 'too_far', 'error')
        return false
    end

    activeTrucks[src] = nil
    IC.server.notify(src, 'truck_stored', 'success')
    return { netId = truck.netId }
end)

-- ────────────────────────────────────────────────────────────
-- البيع المتنقل
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:truckSell', function(source, data)
    local src = source

    if not Config.Truck.enabled then return false end
    if type(data) ~= 'table' then
        IC.logs.exploit(src, 'malformed_payload', 'truck_sell')
        return false
    end

    local truck = activeTrucks[src]
    if not truck then
        IC.server.notify(src, 'truck_not_yours', 'error')
        return false
    end

    local branch = Locations.getBranch(truck.branch)
    if not branch then return false end

    local player, reason = IC.validateWorker(src, nil)
    if not player then
        IC.server.notify(src, reason or 'not_employee', 'error')
        return false
    end

    -- المهلة بين البيعات
    local last = lastSale[src]
    if last and (os.time() - last) < Config.Truck.saleCooldown then
        IC.server.notify(src, 'truck_cooldown', 'error')
        return false
    end

    -- النقطة الساخنة
    local spot = resolveSpot(data.spot)
    if not spot then
        IC.logs.exploit(src, 'invalid_truck_spot', tostring(data.spot))
        return false
    end
    if not IC.isNear(src, spot.coords, spot.radius + Config.Truck.maxDistance) then
        IC.logs.exploit(src, 'distance_check', 'truck spot')
        IC.server.notify(src, 'too_far', 'error')
        return false
    end

    -- المنتج: يجب أن يكون منتجًا حقيقيًا من الوصفات وله سعر
    local recipe = type(data.item) == 'string' and Recipes.byResult[data.item] or nil
    if not recipe or not recipe.sellPrice or recipe.sellPrice <= 0 then
        IC.logs.exploit(src, 'invalid_truck_item', tostring(data.item))
        return false
    end

    local qty = IC.toInt(data.count, 1, 10)
    if not qty then return false end

    local ok, ratio = IC.server.takeProduct(src, data.item, qty)
    if not ok then
        IC.server.notify(src, 'truck_no_stock', 'error')
        return false
    end

    lastSale[src] = os.time()

    local total = math.floor(recipe.sellPrice * qty * Config.Truck.priceMultiplier * ratio)
    local tip = IC.society.settleSale(branch.id, src, player, total, data.item, qty, 'truck')

    IC.server.notify(src, 'truck_sold', 'success', qty, recipe.label, IC.money(total))
    IC.debug('بيع متنقل: %s x%s = %s (بقشيش %s)', data.item, qty, total, tip)
    return true
end)

-- نقاط البيع للعميل (يعرضها كبلبس)
lib.callback.register('icecream:server:getTruckSpots', function(source)
    local player = IC.getPlayer(source)
    if not player or player.job.name ~= Config.Job.name then return {} end
    return Locations.TruckSpots
end)

AddEventHandler('playerDropped', function()
    local src = source
    activeTrucks[src] = nil
    lastSale[src] = nil
end)
