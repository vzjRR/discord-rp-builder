---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Buying ingredients and running the delivery van.
]]

MN = MN or {}

local run = nil
local runBlips = {}
local runZones = {}
local van = nil

-- ═══════════════════════════════════════════════════════════════
-- Supplier counter
-- ═══════════════════════════════════════════════════════════════

---@param entry table
---@param balance number
---@param payFrom string
local function buy(entry, balance, payFrom)
    local cap = entry.maxBuy
    if payFrom == 'business' and entry.cost > 0 then
        cap = math.min(cap, math.max(math.floor(balance / entry.cost), 0))
    end

    if cap < 1 then
        MN.notify(T('supply_short', MN.money(entry.cost)), 'error')
        return
    end

    local input = lib.inputDialog(Products.label(entry.item), { {
        type = 'slider',
        label = T('supply_qty'),
        description = T('supply_unit', MN.money(entry.cost)),
        default = math.min(10, cap), min = 1, max = cap,
    } })
    if not input or not input[1] then return end

    local ok = lib.callback.await('mangonazlet:server:buySupply', false, {
        item = entry.item, quantity = math.floor(input[1]),
    })
    if ok then SetTimeout(150, MN.openSupply) end
end

function MN.openSupply()
    if not MN.checkAccess(MN.PERM.SUPPLY) then return end

    local data = lib.callback.await('mangonazlet:server:catalogue', false)
    if type(data) ~= 'table' then
        MN.notify(T('error_generic'), 'error')
        return
    end

    local options = {}
    for i = 1, #data.catalogue do
        local entry = data.catalogue[i]
        local affordable = data.payFrom ~= 'business' or data.balance >= entry.cost

        options[#options + 1] = {
            title = Products.label(entry.item),
            description = T('supply_unit', MN.money(entry.cost)),
            icon = 'box',
            iconColor = affordable and Config.UI.theme.leaf or '#c0392b',
            disabled = not affordable,
            onSelect = function() buy(entry, data.balance, data.payFrom) end,
        }
    end

    -- The van run belongs with the supplier, so one interaction reaches both.
    if Config.Supply.enabled and Config.Supply.run.enabled then
        table.insert(options, 1, {
            title = T('supply_run'),
            description = run and T('supply_run_back') or nil,
            icon = 'truck-ramp-box',
            iconColor = run and Config.UI.theme.mango or nil,
            onSelect = MN.toggleSupplyRun,
        })
    end

    lib.registerContext({
        id = 'mn_supply',
        title = T('supply_title'),
        description = ('%s • %s%s'):format(T('supply_sub'), T('currency'), MN.money(data.balance)),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_supply')
end

-- ═══════════════════════════════════════════════════════════════
-- Delivery van run
-- ═══════════════════════════════════════════════════════════════

local function removeVan()
    if van and DoesEntityExist(van) then
        SetEntityAsMissionEntity(van, true, true)
        DeleteVehicle(van)
    end
    van = nil
end

local function clearRun()
    removeVan()

    for i = 1, #runBlips do
        if DoesBlipExist(runBlips[i]) then RemoveBlip(runBlips[i]) end
    end
    runBlips = {}

    for i = 1, #runZones do MN.removeZone(runZones[i]) end
    runZones = {}
end

---Route the map to the first pickup still outstanding.
local function routeNext()
    for i = 1, #runBlips do
        if DoesBlipExist(runBlips[i]) then
            SetBlipRoute(runBlips[i], true)
            return
        end
    end
end

---@param point table
local function addPickup(point)
    local blip = AddBlipForCoord(point.coords.x, point.coords.y, point.coords.z)
    SetBlipSprite(blip, 478)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Locations.label(point))
    EndTextCommandSetBlipName(blip)
    runBlips[#runBlips + 1] = blip

    runZones[#runZones + 1] = MN.addZone({
        name = ('mn_pickup_%s'):format(point.index),
        coords = point.coords,
        size = vec3(4.5, 4.5, 3.0),
        heading = 0.0,
        options = { {
            name = ('mn_pickup_opt_%s'):format(point.index),
            label = Locations.label(point),
            icon = 'box-open',
            distance = 3.0,
            canInteract = function()
                return run ~= nil and not point.collected and not MN.busy
            end,
            onSelect = function()
                -- The van carries the shipment, so it has to be here.
                if van and DoesEntityExist(van)
                    and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(van)) > 12.0 then
                    MN.notify(T('supply_run_veh'), 'error')
                    return
                end

                MN.setBusy(true)
                local ok = lib.progressCircle({
                    label = Locations.label(point),
                    duration = 6000,
                    position = 'bottom',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
                })
                MN.setBusy(false)
                if not ok then return end

                local result = lib.callback.await('mangonazlet:server:runCollect', false, point.index)
                if not result then return end

                point.collected = true
                if DoesBlipExist(blip) then RemoveBlip(blip) end

                if result.collected >= result.total then
                    local drop = Locations.shop.supply.coords
                    local dropBlip = AddBlipForCoord(drop.x, drop.y, drop.z)
                    SetBlipSprite(dropBlip, 478)
                    SetBlipColour(dropBlip, 2)
                    SetBlipRoute(dropBlip, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(Locations.label(Locations.shop))
                    EndTextCommandSetBlipName(dropBlip)
                    runBlips[#runBlips + 1] = dropBlip
                else
                    routeNext()
                end
            end,
        } },
    })
end

---Spawn the delivery van at the shop's van bay.
---@param model string
local function spawnVan(model)
    local bay = Locations.shop.van and Locations.shop.van.spawn
    if not bay then return end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(vehicle) - vec3(bay.x, bay.y, bay.z)) < 3.5 then
            MN.notify(T('truck_blocked'), 'error')
            return
        end
    end

    local hash = MN.loadModel(model)
    if not hash then return end

    local vehicle = CreateVehicle(hash, bay.x, bay.y, bay.z, bay.w, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(vehicle) then return end

    SetVehicleNumberPlateText(vehicle, ('MNZ%s'):format(math.random(1000, 9999)))
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleDoorsLocked(vehicle, 1)
    van = vehicle

    if MN.hasResource('qbx_vehiclekeys') then
        exports.qbx_vehiclekeys:GiveKeys(vehicle)
    elseif MN.hasResource('qb-vehiclekeys') then
        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))
    end
end

function MN.toggleSupplyRun()
    if not MN.checkAccess(MN.PERM.SUPPLY) then return end

    if run then
        local outstanding = false
        for _, point in ipairs(run.points) do
            if not point.collected then outstanding = true break end
        end

        if not outstanding then
            local done = lib.callback.await('mangonazlet:server:runFinish', false)
            if done then
                run = nil
                clearRun()
            end
            return
        end

        local answer = lib.alertDialog({
            header = T('supply_run'),
            content = T('supply_run_back'),
            centered = true,
            cancel = true,
            labels = { confirm = T('supply_run_stop'), cancel = T('shop_close') },
        })
        if answer == 'confirm' then
            TriggerServerEvent('mangonazlet:server:runCancel')
            run = nil
            clearRun()
        end
        return
    end

    local started = lib.callback.await('mangonazlet:server:runStart', false)
    if not started then return end

    clearRun()
    run = { points = started.points }

    spawnVan(started.vehicle)
    for i = 1, #started.points do addPickup(started.points[i]) end
    routeNext()
end

-- Leaving the job or going off duty ends the run cleanly.
AddEventHandler('mangonazlet:client:jobChanged', function(job)
    if not run then return end
    if job.name ~= Permissions.job or (Config.RequireDuty and not job.onduty) then
        TriggerServerEvent('mangonazlet:server:runCancel')
        run = nil
        clearRun()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    clearRun()
end)
