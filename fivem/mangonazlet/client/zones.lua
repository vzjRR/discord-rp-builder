---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Interaction zones.

    Registered once and filtered with canInteract, so clocking in or changing
    rank never rebuilds a zone. Rebuilt only when an admin relocates the shop.
]]

MN = MN or {}

local zones = {}

---Standard gate for staff-only options.
---@param permission? string
---@return function
local function staffOnly(permission)
    return function()
        if not MN.isWorking() then return false end
        if permission and not Permissions.can(MN.job.grade, permission) then return false end
        return not MN.busy
    end
end

local function add(zone) zones[#zones + 1] = MN.addZone(zone) end

local function build()
    local shop = Locations.shop

    -- Staff clock. Visible to any employee, on duty or not.
    add({
        name = 'mn_duty',
        coords = shop.duty.coords, size = shop.duty.size, heading = shop.duty.heading,
        options = { {
            name = 'mn_duty_opt', label = T('duty_target'), icon = 'clipboard-user', distance = 2.0,
            canInteract = function() return MN.isStaff() end,
            onSelect = function() TriggerServerEvent('mangonazlet:server:toggleDuty') end,
        } },
    })

    -- Work stations.
    for _, station in ipairs(shop.stations) do
        add({
            name = ('mn_station_%s'):format(station.id),
            coords = station.coords, size = station.size, heading = station.heading,
            options = { {
                name = ('mn_station_opt_%s'):format(station.id),
                label = T('station_use', Locations.label(station)),
                icon = station.icon, distance = 2.0,
                canInteract = staffOnly(MN.PERM.CRAFT),
                onSelect = function() MN.openCrafting(station) end,
            } },
        })
    end

    -- Staff side of the till.
    add({
        name = 'mn_register',
        coords = shop.register.coords, size = shop.register.size, heading = shop.register.heading,
        options = { {
            name = 'mn_register_opt', label = T('register_target'), icon = 'cash-register', distance = 2.0,
            canInteract = staffOnly(MN.PERM.REGISTER),
            onSelect = function() MN.openRegister() end,
        } },
    })

    -- Customer side of the till: opens the ordering menu for anyone.
    if Config.Counter.enabled then
        add({
            name = 'mn_counter',
            coords = shop.counter.coords, size = shop.counter.size, heading = shop.counter.heading,
            options = { {
                name = 'mn_counter_opt', label = T('shop_target'), icon = 'ice-cream', distance = 2.5,
                canInteract = function() return not MN.busy end,
                onSelect = function() MN.openShop() end,
            } },
        })
    end

    -- Display case: staff stock it and pull from it.
    add({
        name = 'mn_display',
        coords = shop.display.coords, size = shop.display.size, heading = shop.display.heading,
        options = { {
            name = 'mn_display_opt', label = T('register_menu'), icon = 'store', distance = 2.0,
            canInteract = staffOnly(MN.PERM.REGISTER),
            onSelect = function() MN.openDisplayCase() end,
        } },
    })

    -- Freezer and pantry (ox_inventory stashes).
    if MN.inventory == MN.INV.OX then
        add({
            name = 'mn_freezer',
            coords = shop.freezer.coords, size = shop.freezer.size, heading = shop.freezer.heading,
            options = { {
                name = 'mn_freezer_opt', label = T('storage_target'), icon = 'snowflake', distance = 2.0,
                canInteract = staffOnly(MN.PERM.STORAGE),
                onSelect = function()
                    exports.ox_inventory:openInventory('stash', ('mn_freezer_%s'):format(shop.id))
                end,
            } },
        })

        add({
            name = 'mn_pantry',
            coords = shop.pantry.coords, size = shop.pantry.size, heading = shop.pantry.heading,
            options = { {
                name = 'mn_pantry_opt', label = T('storage_ing'), icon = 'boxes-stacked', distance = 2.0,
                canInteract = staffOnly(MN.PERM.STORAGE),
                onSelect = function()
                    exports.ox_inventory:openInventory('stash', ('mn_pantry_%s'):format(shop.id))
                end,
            } },
        })
    end

    -- Supplier.
    if Config.Supply.enabled then
        local options = { {
            name = 'mn_supply_opt', label = T('supply_target'), icon = 'box-open', distance = 2.5,
            canInteract = staffOnly(MN.PERM.SUPPLY),
            onSelect = function() MN.openSupply() end,
        } }

        if Config.Supply.run.enabled then
            options[#options + 1] = {
                name = 'mn_supply_run_opt', label = T('supply_run'), icon = 'truck-ramp-box', distance = 2.5,
                canInteract = staffOnly(MN.PERM.SUPPLY),
                onSelect = function() MN.toggleSupplyRun() end,
            }
        end

        add({
            name = 'mn_supply',
            coords = shop.supply.coords, size = shop.supply.size, heading = shop.supply.heading,
            options = options,
        })
    end

    -- Management office.
    add({
        name = 'mn_office',
        coords = shop.office.coords, size = shop.office.size, heading = shop.office.heading,
        options = { {
            name = 'mn_office_opt', label = T('boss_target'), icon = 'briefcase', distance = 2.0,
            canInteract = staffOnly(MN.PERM.MANAGE),
            onSelect = function() MN.openManagement() end,
        } },
    })

    -- Truck bay.
    if Config.Truck.enabled then
        local spawn = shop.truck.spawn
        add({
            name = 'mn_truck',
            coords = vec3(spawn.x, spawn.y, spawn.z), size = vec3(5.0, 7.0, 3.0), heading = spawn.w,
            options = { {
                name = 'mn_truck_opt', label = T('truck_target'), icon = 'truck', distance = 3.5,
                canInteract = staffOnly(),
                onSelect = function() MN.openTruck() end,
            } },
        })
    end

    MN.debug('registered %d interaction zones', #zones)
end

local function clear()
    for i = 1, #zones do MN.removeZone(zones[i]) end
    zones = {}
end

CreateThread(function()
    Wait(1200)
    build()
end)

-- An admin moved something: rebuild in place.
AddEventHandler('mangonazlet:client:relocated', function()
    clear()
    build()
end)

-- ═══════════════════════════════════════════════════════════════
-- Clock hint at the duty point
-- ═══════════════════════════════════════════════════════════════

if Config.UI.textUI then
    CreateThread(function()
        local shown = false

        while true do
            local sleep = 1000
            local near = false

            if MN.isStaff() and MN.nearShop then
                local distance = #(GetEntityCoords(PlayerPedId()) - Locations.shop.duty.coords)
                near = distance <= 3.0
                if distance < 15.0 then sleep = 400 end
            end

            if near and not shown then
                lib.showTextUI(T('duty_hint'), { position = 'left-center', icon = 'clipboard-user' })
                shown = true
            elseif not near and shown then
                lib.hideTextUI()
                shown = false
            end

            Wait(sleep)
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    clear()
end)
