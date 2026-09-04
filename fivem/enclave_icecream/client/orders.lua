---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — طلبات الزبائن (عميل)
    ----------------------------------------
    السيرفر يرسل قائمة الطلبات، والعميل:
      1) يشغّل زبونًا NPC واحدًا على الكاونتر يمثّل أقدم طلب.
      2) يعرض قائمة الطلبات ويسمح بالتسليم.
]]

IC = IC or {}
IC.client = IC.client or {}

-- [branchId] = order[]
local orders = {}
-- الزبون الظاهر حاليًا لكل فرع: [branchId] = ped
local customerPeds = {}
-- معرّف منطقة التفاعل على الزبون: [branchId] = zoneId
local customerZones = {}

-- ────────────────────────────────────────────────────────────
-- الوصول للطلبات
-- ────────────────────────────────────────────────────────────

---@param branchId string
---@return table[]
function IC.client.getOrders(branchId)
    return orders[branchId] or {}
end

RegisterNetEvent('icecream:client:syncOrders', function(branchId, list)
    if type(branchId) ~= 'string' then return end
    orders[branchId] = type(list) == 'table' and list or {}
    TriggerEvent('icecream:client:ordersChanged', branchId)
end)

---يطلب مزامنة يدوية من السيرفر
---@param branchId string
local function refreshOrders(branchId)
    if not branchId then return end
    local list = lib.callback.await('icecream:server:getOrders', false, branchId)
    orders[branchId] = type(list) == 'table' and list or {}
    TriggerEvent('icecream:client:ordersChanged', branchId)
end

AddEventHandler('icecream:client:jobChanged', function(job)
    if job.name == Config.Job.name and job.onduty and IC.currentBranch then
        refreshOrders(IC.currentBranch)
    end
end)

AddEventHandler('icecream:client:branchChanged', function(branchId)
    if branchId and IC.isWorking() then
        refreshOrders(branchId)
    end
end)

-- ────────────────────────────────────────────────────────────
-- الزبون NPC
-- ────────────────────────────────────────────────────────────

---أقدم طلب معلّق في الفرع — هو ما يحمله الزبون الظاهر
---@param branchId string
---@return table|nil
local function frontOrder(branchId)
    local list = orders[branchId]
    return list and list[1] or nil
end

local function despawnCustomer(branchId)
    local ped = customerPeds[branchId]

    -- خيارات addLocalEntity تُزال بـ removeLocalEntity، لا removeZone
    if customerZones[branchId] and ped and DoesEntityExist(ped) then
        pcall(function()
            exports.ox_target:removeLocalEntity(ped, customerZones[branchId])
        end)
    end
    customerZones[branchId] = nil

    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end
    customerPeds[branchId] = nil
end

---@param branch table
local function spawnCustomer(branch)
    if customerPeds[branch.id] and DoesEntityExist(customerPeds[branch.id]) then return end
    if not branch.customer then return end

    local modelName = Locations.CustomerModels[math.random(#Locations.CustomerModels)]
    local hash = IC.loadModel(modelName)
    if not hash then return end

    local stand = branch.customer.stand
    local ped = CreatePed(4, hash, stand.x, stand.y, stand.z - 1.0, stand.w, false, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(ped) then return end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedDiesWhenInjured(ped, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    customerPeds[branch.id] = ped

    -- خيار تسليم الطلب مباشرة للزبون (بديل أسرع من قائمة الكاشير)
    if IC.targetSystem == 'ox' then
        local optionName = ('icecream_customer_%s'):format(branch.id)
        customerZones[branch.id] = optionName
        exports.ox_target:addLocalEntity(ped, {
            {
                name = optionName,
                label = L('order_deliver'),
                icon = 'hand-holding-heart',
                distance = 2.5,
                canInteract = function()
                    return IC.isWorking()
                        and IC.can(IC.job.grade, 'canRegister')
                        and frontOrder(branch.id) ~= nil
                        and not IC.busy
                end,
                onSelect = function()
                    local order = frontOrder(branch.id)
                    if not order then
                        IC.notify(L('register_no_orders'), 'inform')
                        return
                    end
                    local delivered = lib.callback.await('icecream:server:deliverOrder', false, branch.id, order.id)
                    if delivered then refreshOrders(branch.id) end
                end,
            },
        })
    end
end

-- يبقي زبونًا واحدًا ظاهرًا طالما في طلبات معلّقة واللاعب قريب
CreateThread(function()
    while true do
        local sleep = 3000

        if IC.isWorking() and IC.currentBranch then
            local branch = Locations.getBranch(IC.currentBranch)
            if branch then
                local pending = orders[branch.id] or {}
                local distance = #(GetEntityCoords(PlayerPedId()) - branch.center)

                if #pending > 0 and distance < 60.0 then
                    sleep = 2000
                    if not customerPeds[branch.id] then
                        spawnCustomer(branch)
                        if customerPeds[branch.id] then
                            IC.notify(L('order_waiting'), 'inform')
                        end
                    end
                else
                    despawnCustomer(branch.id)
                end
            end
        else
            for branchId in pairs(customerPeds) do
                despawnCustomer(branchId)
            end
        end

        Wait(sleep)
    end
end)

-- ────────────────────────────────────────────────────────────
-- قائمة الطلبات
-- ────────────────────────────────────────────────────────────

---@param branch table
function IC.client.openOrdersMenu(branch)
    if not IC.checkAccess('canRegister') then return end

    refreshOrders(branch.id)
    local pending = orders[branch.id] or {}

    if #pending == 0 then
        IC.notify(L('register_no_orders'), 'inform')
        return
    end

    local now = os.time()
    local options = {}

    for i = 1, #pending do
        local order = pending[i]
        local recipe = Recipes.byResult[order.item]
        local have = IC.getItemCount(order.item)
        local ready = have >= order.count
        local secondsLeft = math.max((order.expiresAt or now) - now, 0)

        options[#options + 1] = {
            title = L('order_item_line', order.count, order.label or (recipe and recipe.label) or order.item),
            description = ('%s • %s'):format(
                L('order_value', IC.money(order.price or 0)),
                L('order_time_left', secondsLeft)
            ),
            icon = ready and 'circle-check' or 'circle-exclamation',
            iconColor = ready and '#4ade80' or '#f87171',
            progress = math.floor((secondsLeft / math.max(Config.Orders.expiry, 1)) * 100),
            colorScheme = ready and 'green' or 'red',
            metadata = {
                { label = L('craft_makes'), value = ('%s / %s'):format(have, order.count) },
            },
            onSelect = function()
                local delivered = lib.callback.await('icecream:server:deliverOrder', false, branch.id, order.id)
                if delivered then
                    refreshOrders(branch.id)
                end
            end,
        }
    end

    lib.registerContext({
        id = 'icecream_orders',
        title = L('order_list_title'),
        menu = 'icecream_register',
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_orders')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= IC.resource then return end
    for branchId in pairs(customerPeds) do
        despawnCustomer(branchId)
    end
end)
