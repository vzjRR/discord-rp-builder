---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — التوريد (عميل)
    ----------------------------------
    قائمة شراء المواد الخام + جولة التوريد بالشاحنة مع بلبس ونقاط تحميل.
]]

IC = IC or {}
IC.client = IC.client or {}

-- الجولة النشطة محليًا
local activeRun = nil
local runBlips = {}
local runZones = {}
local runVehicle = nil

-- ────────────────────────────────────────────────────────────
-- شراء المواد الخام
-- ────────────────────────────────────────────────────────────

---@param branch table
---@param entry table
local function buyItem(branch, entry, balance)
    local maxQty = math.min(entry.max or Config.Supply.maxQuantity, Config.Supply.maxQuantity)
    if Config.Supply.payFrom == 'society' and entry.price > 0 then
        maxQty = math.min(maxQty, math.max(math.floor(balance / entry.price), 0))
    end

    if maxQty < 1 then
        IC.notify(L('supply_no_funds', IC.money(entry.price)), 'error')
        return
    end

    local input = lib.inputDialog(entry.label, {
        {
            type = 'slider',
            label = L('supply_amount_input'),
            description = L('supply_unit_price', IC.money(entry.price)),
            default = math.min(10, maxQty),
            min = 1,
            max = maxQty,
        },
    })

    if not input or not input[1] then return end

    local bought = lib.callback.await('icecream:server:buySupply', false, {
        branch = branch.id,
        item = entry.item,
        quantity = math.floor(input[1]),
    })

    if bought then
        IC.client.openSupplyMenu(branch)
    end
end

---@param branch table
function IC.client.openSupplyMenu(branch)
    if not IC.checkAccess('canSupply') then return end

    local data = lib.callback.await('icecream:server:getCatalog', false, branch.id)
    if not data then
        IC.notify(L('error_generic'), 'error')
        return
    end

    local options = {}
    for i = 1, #data.catalog do
        local entry = data.catalog[i]
        local affordable = Config.Supply.payFrom ~= 'society' or data.balance >= entry.price

        options[#options + 1] = {
            title = entry.label,
            description = L('supply_unit_price', IC.money(entry.price)),
            icon = 'box',
            iconColor = affordable and '#4ade80' or '#f87171',
            disabled = not affordable,
            metadata = {
                { label = 'الحد الأقصى', value = tostring(entry.max or Config.Supply.maxQuantity) },
            },
            onSelect = function() buyItem(branch, entry, data.balance) end,
        }
    end

    lib.registerContext({
        id = 'icecream_supply',
        title = L('supply_menu_title'),
        description = ('%s • %s: $%s'):format(
            L('supply_menu_subtitle'), L('boss_balance'), IC.money(data.balance)),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_supply')
end

-- ────────────────────────────────────────────────────────────
-- جولة التوريد
-- ────────────────────────────────────────────────────────────

---يحذف شاحنة الجولة إن كانت موجودة وفاضية
local function removeRunVehicle()
    if runVehicle and DoesEntityExist(runVehicle) then
        SetEntityAsMissionEntity(runVehicle, true, true)
        DeleteVehicle(runVehicle)
    end
    runVehicle = nil
end

local function clearRunMarkers()
    removeRunVehicle()

    for i = 1, #runBlips do
        if DoesBlipExist(runBlips[i]) then RemoveBlip(runBlips[i]) end
    end
    runBlips = {}

    for i = 1, #runZones do
        IC.removeZone(runZones[i])
    end
    runZones = {}
end

local function finishRun(branch)
    local done = lib.callback.await('icecream:server:finishSupplyRun', false)
    if done then
        activeRun = nil
        clearRunMarkers()
    end
end

---@param branch table
---@param point table
local function addPickupPoint(branch, point)
    local blip = AddBlipForCoord(point.coords.x, point.coords.y, point.coords.z)
    SetBlipSprite(blip, 478)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.8)
    SetBlipRoute(blip, #runBlips == 0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(point.label)
    EndTextCommandSetBlipName(blip)
    runBlips[#runBlips + 1] = blip

    runZones[#runZones + 1] = IC.addBoxZone({
        name = ('icecream_pickup_%s'):format(point.index),
        coords = point.coords,
        size = vec3(4.0, 4.0, 3.0),
        rotation = 0.0,
        options = {
            {
                name = ('icecream_pickup_opt_%s'):format(point.index),
                label = point.label,
                icon = 'box-open',
                distance = 3.0,
                canInteract = function()
                    return activeRun ~= nil and not point.collected and not IC.busy
                end,
                onSelect = function()
                    -- الشحنة تُحمَّل في الشاحنة، فلازم تكون واقفة معك
                    if runVehicle and DoesEntityExist(runVehicle)
                        and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(runVehicle)) > 12.0 then
                        IC.notify(L('supply_run_no_vehicle'), 'error')
                        return
                    end

                    IC.client.setBusy(true)
                    local ok = lib.progressCircle({
                        label = point.label,
                        duration = 6000,
                        position = 'bottom',
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
                    })
                    IC.client.setBusy(false)
                    if not ok then return end

                    local result = lib.callback.await('icecream:server:collectSupply', false, point.index)
                    if not result then return end

                    point.collected = true
                    if DoesBlipExist(blip) then RemoveBlip(blip) end

                    -- وجّه المسار للنقطة التالية أو للمحل
                    if result.collected >= result.total then
                        local dropBlip = AddBlipForCoord(branch.supply.coords.x, branch.supply.coords.y, branch.supply.coords.z)
                        SetBlipSprite(dropBlip, 478)
                        SetBlipColour(dropBlip, 2)
                        SetBlipRoute(dropBlip, true)
                        BeginTextCommandSetBlipName('STRING')
                        AddTextComponentSubstringPlayerName(branch.label)
                        EndTextCommandSetBlipName(dropBlip)
                        runBlips[#runBlips + 1] = dropBlip
                    else
                        for i = 1, #runBlips do
                            if DoesBlipExist(runBlips[i]) then
                                SetBlipRoute(runBlips[i], true)
                                break
                            end
                        end
                    end
                end,
            },
        },
    })
end

---يبدأ أو ينهي جولة التوريد
---@param branch table
function IC.client.toggleSupplyRun(branch)
    if not IC.checkAccess('canSupply') then return end

    -- جولة جارية: نحاول التسليم
    if activeRun then
        local allCollected = true
        for _, point in ipairs(activeRun.points) do
            if not point.collected then allCollected = false break end
        end

        if allCollected then
            finishRun(branch)
        else
            local confirm = lib.alertDialog({
                header = L('supply_run_start'),
                content = L('supply_run_deliver'),
                centered = true,
                cancel = true,
                labels = { confirm = 'إلغاء الجولة', cancel = 'متابعة' },
            })
            if confirm == 'confirm' then
                TriggerServerEvent('icecream:server:cancelSupplyRun')
                activeRun = nil
                clearRunMarkers()
            end
        end
        return
    end

    local run = lib.callback.await('icecream:server:startSupplyRun', false, branch.id)
    if not run then return end

    activeRun = { branch = branch.id, points = run.points }
    clearRunMarkers()

    -- إخراج شاحنة الجولة (لو الفرع معرّف له نقطة إخراج وموديل صالح)
    local spawnPoint = branch.supplyVehicle and branch.supplyVehicle.spawn
    if spawnPoint and run.vehicle then
        local blocked = false
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if #(GetEntityCoords(vehicle) - vec3(spawnPoint.x, spawnPoint.y, spawnPoint.z)) < 3.5 then
                blocked = true
                break
            end
        end

        if blocked then
            IC.notify(L('truck_occupied'), 'error')
        else
            local hash = IC.loadModel(run.vehicle)
            if hash then
                local vehicle = CreateVehicle(hash, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w, true, false)
                SetModelAsNoLongerNeeded(hash)
                if DoesEntityExist(vehicle) then
                    SetVehicleNumberPlateText(vehicle, ('ICS%s'):format(math.random(1000, 9999)))
                    SetEntityAsMissionEntity(vehicle, true, true)
                    SetVehicleDoorsLocked(vehicle, 1)
                    runVehicle = vehicle

                    if IC.hasResource('qb-vehiclekeys') then
                        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(vehicle))
                    elseif IC.hasResource('qbx_vehiclekeys') then
                        exports.qbx_vehiclekeys:GiveKeys(vehicle)
                    end
                end
            end
        end
    end

    for i = 1, #run.points do
        addPickupPoint(branch, run.points[i])
    end
end

AddEventHandler('icecream:client:jobChanged', function(job)
    -- خرج من الوظيفة/الدوام أثناء جولة → نظّف
    if activeRun and (job.name ~= Config.Job.name or (Config.RequireDuty and not job.onduty)) then
        TriggerServerEvent('icecream:server:cancelSupplyRun')
        activeRun = nil
        clearRunMarkers()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= IC.resource then return end
    clearRunMarkers()
end)
