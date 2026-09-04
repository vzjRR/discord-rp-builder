---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — The mobile truck: take it out, sell at hotspots, put it back.
]]

MN = MN or {}

local truck = nil
local spotBlips = {}

-- ═══════════════════════════════════════════════════════════════
-- Hotspot blips, shown only while the truck is out
-- ═══════════════════════════════════════════════════════════════

local function clearSpots()
    for i = 1, #spotBlips do
        if DoesBlipExist(spotBlips[i]) then RemoveBlip(spotBlips[i]) end
    end
    spotBlips = {}
end

local function showSpots()
    clearSpots()

    for i = 1, #Locations.truckSpots do
        local spot = Locations.truckSpots[i]

        local area = AddBlipForRadius(spot.coords.x, spot.coords.y, spot.coords.z, spot.radius)
        SetBlipColour(area, 46)
        SetBlipAlpha(area, 80)
        spotBlips[#spotBlips + 1] = area

        local pin = AddBlipForCoord(spot.coords.x, spot.coords.y, spot.coords.z)
        SetBlipSprite(pin, 93)
        SetBlipColour(pin, 46)
        SetBlipScale(pin, 0.6)
        SetBlipAsShortRange(pin, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(T('truck_spot', Locations.label(spot)))
        EndTextCommandSetBlipName(pin)
        spotBlips[#spotBlips + 1] = pin
    end
end

---@return number|nil index
local function currentSpot()
    local coords = GetEntityCoords(PlayerPedId())
    for i = 1, #Locations.truckSpots do
        local spot = Locations.truckSpots[i]
        if #(coords - spot.coords) <= spot.radius then return i end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- Taking and storing
-- ═══════════════════════════════════════════════════════════════

local function takeTruck()
    local spawn = Locations.shop.truck.spawn

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - vec3(spawn.x, spawn.y, spawn.z)) < 3.5 then
            MN.notify(T('truck_blocked'), 'error')
            return
        end
    end

    local result = lib.callback.await('mangonazlet:server:truckTake', false)
    if not result then return end

    local hash = MN.loadModel(result.model)
    if not hash then
        MN.notify(T('error_generic'), 'error')
        return
    end

    local vehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(vehicle) then
        MN.notify(T('error_generic'), 'error')
        return
    end

    SetVehicleNumberPlateText(vehicle, ('MNZ%s'):format(math.random(1000, 9999)))
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleDoorsLocked(vehicle, 1)
    truck = vehicle

    TriggerServerEvent('mangonazlet:server:truckRegister', NetworkGetNetworkIdFromEntity(vehicle))

    if MN.hasResource('qbx_vehiclekeys') then
        exports.qbx_vehiclekeys:GiveKeys(vehicle)
    elseif MN.hasResource('qb-vehiclekeys') then
        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))
    end

    showSpots()
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
end

local function storeTruck()
    local result = lib.callback.await('mangonazlet:server:truckStore', false)
    if not result then return end

    local target = truck
    if not target or not DoesEntityExist(target) then
        target = nil
        local hash = joaat(Config.Truck.model)
        local park = Locations.shop.truck.spawn
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if GetEntityModel(vehicle) == hash
                and #(GetEntityCoords(vehicle) - vec3(park.x, park.y, park.z)) < 15.0 then
                target = vehicle
                break
            end
        end
    end

    if target and DoesEntityExist(target) then
        SetEntityAsMissionEntity(target, true, true)
        DeleteVehicle(target)
    end

    truck = nil
    clearSpots()
end

-- ═══════════════════════════════════════════════════════════════
-- Selling from the window
-- ═══════════════════════════════════════════════════════════════

local function sellMenu()
    local spot = currentSpot()
    if not spot then
        MN.notify(T('truck_nobody'), 'error')
        return
    end

    local options = {}
    local menu = Products.menu()

    for i = 1, #menu do
        local product = menu[i]
        local carried = MN.itemCount(product.name)

        if carried > 0 then
            local price = math.floor(product.price * Config.Truck.priceMultiplier)

            options[#options + 1] = {
                title = Products.label(product.name),
                description = ('%s%s × %s'):format(T('currency'), MN.money(price), carried),
                icon = 'ice-cream',
                onSelect = function()
                    local cap = math.min(carried, 10)
                    local quantity = 1

                    if cap > 1 then
                        local input = lib.inputDialog(Products.label(product.name), { {
                            type = 'slider', label = T('shop_qty'),
                            default = 1, min = 1, max = cap,
                        } })
                        if not input or not input[1] then return end
                        quantity = math.floor(input[1])
                    end

                    MN.setBusy(true)
                    local ok = lib.progressCircle({
                        label = Products.label(product.name),
                        duration = 2500,
                        position = 'bottom',
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                    })
                    MN.setBusy(false)
                    if not ok then return end

                    lib.callback.await('mangonazlet:server:truckSell', false, {
                        spot = spot, item = product.name, quantity = quantity,
                    })
                end,
            }
        end
    end

    if #options == 0 then
        MN.notify(T('truck_nostock'), 'error')
        return
    end

    lib.registerContext({
        id = 'mn_truck_sell',
        title = T('truck_sell'),
        description = T('truck_spot', Locations.label(Locations.truckSpots[spot])),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_truck_sell')
end

-- Prompt at a hotspot while standing by the truck.
CreateThread(function()
    local shown = false

    while true do
        local sleep = 1500

        if Config.Truck.enabled and MN.isWorking() and truck and DoesEntityExist(truck) then
            local near = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(truck)) <= Config.Truck.maxDistance
            local spot = near and currentSpot() or nil

            if spot then
                sleep = 0

                if not shown and Config.UI.textUI then
                    lib.showTextUI(('[E] %s'):format(T('truck_sell')), {
                        position = 'left-center', icon = 'ice-cream',
                    })
                    shown = true
                end

                if IsControlJustReleased(0, 38) then   -- E
                    lib.hideTextUI()
                    shown = false
                    sellMenu()
                end
            elseif shown then
                lib.hideTextUI()
                shown = false
            end
        elseif shown then
            lib.hideTextUI()
            shown = false
        end

        Wait(sleep)
    end
end)

function MN.openTruck()
    if not MN.checkAccess() then return end
    if MN.job.grade < Config.Truck.requireGrade then
        MN.notify(T('no_permission'), 'error')
        return
    end

    local out = truck ~= nil and DoesEntityExist(truck)

    lib.registerContext({
        id = 'mn_truck',
        title = T('truck_title'),
        position = Config.UI.contextPosition,
        options = {
            {
                title = T('truck_take'),
                description = T('truck_fee', MN.money(Config.Truck.fee)),
                icon = 'truck',
                disabled = out,
                onSelect = takeTruck,
            },
            {
                title = T('truck_store'),
                icon = 'warehouse',
                disabled = not out,
                onSelect = storeTruck,
            },
        },
    })
    lib.showContext('mn_truck')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    clearSpots()
    if MN.has.oxLib then lib.hideTextUI() end
    if truck and DoesEntityExist(truck) then
        SetEntityAsMissionEntity(truck, true, true)
        DeleteVehicle(truck)
    end
end)
