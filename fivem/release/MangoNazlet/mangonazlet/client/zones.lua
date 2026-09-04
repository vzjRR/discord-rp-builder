---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Interaction points.

    Each point is declared once, here, and then driven two ways:

      • the server's target resource (ox_target / qb-target), and
      • a plain [E] prompt when you stand on it.

    The second exists because the first is not universal: a player who has
    never used their server's target key sees a prompt and nothing happens when
    they press the key it names. Declaring the points once and feeding both
    keeps the two from drifting apart.
]]

MN = MN or {}

local zones = {}

---Standard gate for staff-only points.
---@param permission? string
---@return function
local function staffOnly(permission)
    return function()
        if not MN.isWorking() then return false end
        if permission and not Permissions.can(MN.job.grade, permission) then return false end
        return not MN.busy
    end
end

-- ═══════════════════════════════════════════════════════════════
-- The points themselves
-- ═══════════════════════════════════════════════════════════════

---Build the interaction list from the current (possibly relocated) layout.
---@return table[]  { id, coords, size, heading, label, icon, range, can, run }
local function buildPoints()
    local shop = Locations.shop
    local points = {}

    local function add(point) points[#points + 1] = point end

    -- Clock. Shown to any employee, on duty or not: it is how you go on duty.
    add({
        id = 'duty',
        coords = shop.duty.coords, size = shop.duty.size, heading = shop.duty.heading,
        label = T('duty_target'), icon = 'clipboard-user', range = 2.0,
        can = function() return MN.isStaff() and not MN.busy end,
        run = function() TriggerServerEvent('mangonazlet:server:toggleDuty') end,
    })

    -- Work stations.
    for _, station in ipairs(shop.stations) do
        add({
            id = 'station_' .. station.id,
            coords = station.coords, size = station.size, heading = station.heading,
            label = T('station_use', Locations.label(station)), icon = station.icon, range = 2.0,
            can = staffOnly(MN.PERM.CRAFT),
            run = function() MN.openCrafting(station) end,
        })
    end

    -- Staff side of the till.
    add({
        id = 'register',
        coords = shop.register.coords, size = shop.register.size, heading = shop.register.heading,
        label = T('register_target'), icon = 'cash-register', range = 2.0,
        can = staffOnly(MN.PERM.REGISTER),
        run = function() MN.openRegister() end,
    })

    -- Customer side of the till.
    if Config.Counter.enabled then
        add({
            id = 'counter',
            coords = shop.counter.coords, size = shop.counter.size, heading = shop.counter.heading,
            label = T('shop_target'), icon = 'ice-cream', range = 2.5,
            can = function() return not MN.busy end,
            run = function() MN.openShop() end,
        })
    end

    -- Display case.
    add({
        id = 'display',
        coords = shop.display.coords, size = shop.display.size, heading = shop.display.heading,
        label = T('register_menu'), icon = 'store', range = 2.0,
        can = staffOnly(MN.PERM.REGISTER),
        run = function() MN.openDisplayCase() end,
    })

    -- Storage. ox_inventory stashes only; nothing else exposes one.
    if MN.inventory == MN.INV.OX then
        add({
            id = 'freezer',
            coords = shop.freezer.coords, size = shop.freezer.size, heading = shop.freezer.heading,
            label = T('storage_target'), icon = 'snowflake', range = 2.0,
            can = staffOnly(MN.PERM.STORAGE),
            run = function()
                exports.ox_inventory:openInventory('stash', ('mn_freezer_%s'):format(shop.id))
            end,
        })
        add({
            id = 'pantry',
            coords = shop.pantry.coords, size = shop.pantry.size, heading = shop.pantry.heading,
            label = T('storage_ing'), icon = 'boxes-stacked', range = 2.0,
            can = staffOnly(MN.PERM.STORAGE),
            run = function()
                exports.ox_inventory:openInventory('stash', ('mn_pantry_%s'):format(shop.id))
            end,
        })
    end

    -- Supplier, and the van run alongside it.
    if Config.Supply.enabled then
        add({
            id = 'supply',
            coords = shop.supply.coords, size = shop.supply.size, heading = shop.supply.heading,
            label = T('supply_target'), icon = 'box-open', range = 2.5,
            can = staffOnly(MN.PERM.SUPPLY),
            -- The van run lives inside this menu rather than as a second
            -- option on the point, so one key reaches both.
            run = function() MN.openSupply() end,
        })
    end

    -- Management.
    add({
        id = 'office',
        coords = shop.office.coords, size = shop.office.size, heading = shop.office.heading,
        label = T('boss_target'), icon = 'briefcase', range = 2.0,
        can = staffOnly(MN.PERM.MANAGE),
        run = function() MN.openManagement() end,
    })

    -- Truck bay.
    if Config.Truck.enabled then
        local spawn = shop.truck.spawn
        add({
            id = 'truck',
            coords = vec3(spawn.x, spawn.y, spawn.z),
            size = vec3(5.0, 7.0, 3.0), heading = spawn.w,
            label = T('truck_target'), icon = 'truck', range = 3.5,
            can = staffOnly(),
            run = function() MN.openTruck() end,
        })
    end

    return points
end

local points = {}

-- ═══════════════════════════════════════════════════════════════
-- Target registration
-- ═══════════════════════════════════════════════════════════════

local function registerTargets()
    for i = 1, #points do
        local point = points[i]

        local options = { {
            name = ('mn_%s'):format(point.id),
            label = point.label,
            icon = point.icon,
            distance = point.range,
            canInteract = point.can,
            onSelect = point.run,
        } }

        zones[#zones + 1] = MN.addZone({
            name = ('mn_%s'):format(point.id),
            coords = point.coords,
            size = point.size,
            heading = point.heading,
            options = options,
        })
    end

    MN.debug('registered %d interaction zones', #zones)
end

local function clearTargets()
    for i = 1, #zones do MN.removeZone(zones[i]) end
    zones = {}
end

local function build()
    points = buildPoints()
    registerTargets()
end

CreateThread(function()
    Wait(1200)
    build()
end)

-- An admin moved something: rebuild against the new layout.
AddEventHandler('mangonazlet:client:relocated', function()
    clearTargets()
    build()
end)

-- ═══════════════════════════════════════════════════════════════
-- [E] fallback
--
-- Finds the nearest point the player may currently use and offers it. This is
-- what makes the prompt honest: it names a key that actually does something.
-- ═══════════════════════════════════════════════════════════════

if Config.UI.keyInteract then
    CreateThread(function()
        local shownFor = nil

        local function hide()
            if shownFor then
                lib.hideTextUI()
                shownFor = nil
            end
        end

        while true do
            local sleep = 1000
            local active = nil

            if MN.nearShop and not MN.busy and #points > 0 then
                local coords = GetEntityCoords(PlayerPedId())
                local bestDistance

                for i = 1, #points do
                    local point = points[i]
                    local distance = #(coords - point.coords)

                    if distance <= point.range
                        and (not bestDistance or distance < bestDistance)
                        and point.can() then
                        active, bestDistance = point, distance
                    end

                    if distance < 20.0 and sleep > 250 then sleep = 250 end
                end
            end

            if active then
                -- Frame-accurate only while actually standing on a point.
                sleep = 0

                if shownFor ~= active.id then
                    lib.showTextUI(('[E] %s'):format(active.label), {
                        position = 'left-center',
                        icon = active.icon,
                    })
                    shownFor = active.id
                end

                if IsControlJustReleased(0, 38) then    -- E
                    hide()
                    active.run()
                    Wait(400)                            -- do not re-fire on one press
                end
            else
                hide()
            end

            Wait(sleep)
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    clearTargets()
    if MN.has.oxLib then lib.hideTextUI() end
end)
