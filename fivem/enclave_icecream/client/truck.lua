---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — عربة المثلجات (عميل)
    ----------------------------------------
    إخراج/تخزين العربة، بلبس نقاط البيع، وواجهة البيع المتنقل.
]]

IC = IC or {}
IC.client = IC.client or {}

local myTruck = nil          -- الكيان المحلي للعربة
local spotBlips = {}
local currentSpot = nil      -- فهرس النقطة الساخنة التي يقف فيها اللاعب

-- ────────────────────────────────────────────────────────────
-- بلبس نقاط البيع
-- ────────────────────────────────────────────────────────────

local function clearSpotBlips()
    for i = 1, #spotBlips do
        if DoesBlipExist(spotBlips[i]) then RemoveBlip(spotBlips[i]) end
    end
    spotBlips = {}
end

local function createSpotBlips()
    clearSpotBlips()
    for i = 1, #Locations.TruckSpots do
        local spot = Locations.TruckSpots[i]
        local blip = AddBlipForRadius(spot.coords.x, spot.coords.y, spot.coords.z, spot.radius or 25.0)
        SetBlipColour(blip, 2)
        SetBlipAlpha(blip, 90)
        spotBlips[#spotBlips + 1] = blip

        local marker = AddBlipForCoord(spot.coords.x, spot.coords.y, spot.coords.z)
        SetBlipSprite(marker, 93)
        SetBlipColour(marker, 2)
        SetBlipScale(marker, 0.6)
        SetBlipAsShortRange(marker, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L('truck_spot_hint', spot.label))
        EndTextCommandSetBlipName(marker)
        spotBlips[#spotBlips + 1] = marker
    end
end

-- ────────────────────────────────────────────────────────────
-- إخراج / تخزين العربة
-- ────────────────────────────────────────────────────────────

---@param branch table
local function takeTruck(branch)
    local spawn = branch.truck.spawn

    -- المكان لازم يكون فاضي
    local occupied = false
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - vec3(spawn.x, spawn.y, spawn.z)) < 3.0 then
            occupied = true
            break
        end
    end
    if occupied then
        IC.notify(L('truck_occupied'), 'error')
        return
    end

    local result = lib.callback.await('icecream:server:takeTruck', false, branch.id)
    if not result then return end

    local hash = IC.loadModel(result.model)
    if not hash then
        IC.notify(L('error_generic'), 'error')
        return
    end

    local vehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(vehicle) then
        IC.notify(L('error_generic'), 'error')
        return
    end

    SetVehicleNumberPlateText(vehicle, ('ICE%s'):format(math.random(1000, 9999)))
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleEngineOn(vehicle, false, false, true)
    SetVehicleDoorsLocked(vehicle, 1)

    myTruck = vehicle
    TriggerServerEvent('icecream:server:registerTruck', NetworkGetNetworkIdFromEntity(vehicle))
    createSpotBlips()

    -- مفاتيح العربة لو السيرفر فيه نظام مفاتيح شائع
    if IC.hasResource('qb-vehiclekeys') then
        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))
    elseif IC.hasResource('qbx_vehiclekeys') then
        exports.qbx_vehiclekeys:GiveKeys(vehicle)
    end

    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
end

---@param branch table
local function storeTruck(branch)
    local result = lib.callback.await('icecream:server:storeTruck', false, branch.id)
    if not result then return end

    -- احذف عربتنا لو قريبة، وإلا احذف أقرب عربة من موديل العربة
    local target = myTruck
    if not target or not DoesEntityExist(target) then
        target = nil
        local hash = joaat(Config.Truck.model)
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if GetEntityModel(vehicle) == hash
                and #(GetEntityCoords(vehicle) - branch.truck.park) < 12.0 then
                target = vehicle
                break
            end
        end
    end

    if target and DoesEntityExist(target) then
        SetEntityAsMissionEntity(target, true, true)
        DeleteVehicle(target)
    end

    myTruck = nil
    clearSpotBlips()
end

-- ────────────────────────────────────────────────────────────
-- البيع المتنقل
-- ────────────────────────────────────────────────────────────

---يرجّع فهرس النقطة الساخنة التي يقف فيها اللاعب
---@return number|nil
local function findCurrentSpot()
    local coords = GetEntityCoords(PlayerPedId())
    for i = 1, #Locations.TruckSpots do
        local spot = Locations.TruckSpots[i]
        if #(coords - spot.coords) <= (spot.radius or 25.0) then
            return i
        end
    end
    return nil
end

local function openSellMenu()
    local spot = findCurrentSpot()
    if not spot then
        IC.notify(L('truck_no_customers'), 'error')
        return
    end

    -- ما الذي معنا للبيع؟
    local options = {}
    for item, recipe in pairs(Recipes.byResult) do
        if recipe.sellPrice and recipe.sellPrice > 0 then
            local have = IC.getItemCount(item)
            if have > 0 then
                local price = math.floor(recipe.sellPrice * Config.Truck.priceMultiplier)
                options[#options + 1] = {
                    title = recipe.label,
                    description = ('$%s × %s'):format(IC.money(price), have),
                    icon = recipe.icon or 'ice-cream',
                    metadata = {
                        { label = L('craft_price'), value = ('$%s'):format(IC.money(price)) },
                    },
                    _price = price,
                    onSelect = function()
                        local maxQty = math.min(have, 10)
                        local input = maxQty > 1 and lib.inputDialog(recipe.label, {
                            {
                                type = 'slider',
                                label = L('supply_amount_input'),
                                default = 1, min = 1, max = maxQty,
                            },
                        }) or { 1 }

                        if not input or not input[1] then return end

                        IC.client.setBusy(true)
                        local ok = lib.progressCircle({
                            label = recipe.label,
                            duration = 2500,
                            position = 'bottom',
                            canCancel = true,
                            disable = { move = true, car = true, combat = true },
                        })
                        IC.client.setBusy(false)
                        if not ok then return end

                        lib.callback.await('icecream:server:truckSell', false, {
                            spot = spot,
                            item = item,
                            count = math.floor(input[1]),
                        })
                    end,
                }
            end
        end
    end

    if #options == 0 then
        IC.notify(L('truck_no_stock'), 'error')
        return
    end

    table.sort(options, function(a, b) return (a._price or 0) > (b._price or 0) end)

    lib.registerContext({
        id = 'icecream_truck_sell',
        title = L('truck_sell'),
        description = L('truck_spot_hint', Locations.TruckSpots[spot].label),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_truck_sell')
end

-- TextUI ونافذة البيع عند الوقوف في نقطة ساخنة مع العربة
CreateThread(function()
    local shown = false

    while true do
        local sleep = 1500

        if IC.isWorking() and Config.Truck.enabled and myTruck and DoesEntityExist(myTruck) then
            local ped = PlayerPedId()
            local nearTruck = #(GetEntityCoords(ped) - GetEntityCoords(myTruck)) <= Config.Truck.maxDistance
            local spot = nearTruck and findCurrentSpot() or nil

            if spot then
                sleep = 0
                currentSpot = spot

                if not shown and Config.UI.textUI then
                    lib.showTextUI(('[E] %s — %s'):format(L('truck_sell'), Locations.TruckSpots[spot].label), {
                        position = 'left-center',
                        icon = 'ice-cream',
                    })
                    shown = true
                end

                if IsControlJustReleased(0, 38) then  -- E
                    lib.hideTextUI()
                    shown = false
                    openSellMenu()
                end
            elseif shown then
                lib.hideTextUI()
                shown = false
                currentSpot = nil
            end
        elseif shown then
            lib.hideTextUI()
            shown = false
            currentSpot = nil
        end

        Wait(sleep)
    end
end)

-- ────────────────────────────────────────────────────────────
-- قائمة العربة
-- ────────────────────────────────────────────────────────────

---@param branch table
function IC.client.openTruckMenu(branch)
    if not IC.checkAccess() then return end
    if IC.job.grade < Config.Truck.requireGrade then
        IC.notify(L('no_permission'), 'error')
        return
    end

    local hasTruck = myTruck ~= nil and DoesEntityExist(myTruck)

    lib.registerContext({
        id = 'icecream_truck',
        title = L('truck_menu_title'),
        position = Config.UI.contextPosition,
        options = {
            {
                title = L('truck_take'),
                description = L('truck_take_desc', IC.money(Config.Truck.rentalFee)),
                icon = 'truck',
                disabled = hasTruck,
                onSelect = function() takeTruck(branch) end,
            },
            {
                title = L('truck_store'),
                icon = 'warehouse',
                disabled = not hasTruck,
                onSelect = function() storeTruck(branch) end,
            },
        },
    })
    lib.showContext('icecream_truck')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= IC.resource then return end
    clearSpotBlips()
    lib.hideTextUI()
    if myTruck and DoesEntityExist(myTruck) then
        DeleteVehicle(myTruck)
    end
end)
