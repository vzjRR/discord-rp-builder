---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — مناطق التفاعل
    ---------------------------------
    تُسجَّل مرة واحدة عند تحميل المورد. الفلترة تتم عبر canInteract
    حتى لا نضطر لإنشاء/حذف المناطق كل ما تغيّرت حالة اللاعب.
]]

IC = IC or {}

local zones = {}

---شرط الظهور الأساسي: موظف + على الدوام (أو نقطة الدوام نفسها)
---@param permission? string
---@return function
local function requireWork(permission)
    return function()
        if not IC.isEmployee() then return false end
        if Config.RequireDuty and not IC.job.onduty then return false end
        if permission and not IC.can(IC.job.grade, permission) then return false end
        return not IC.busy
    end
end

local function registerBranch(branch)
    -- ── نقطة الدوام: تظهر لكل موظف حتى خارج الدوام
    if branch.duty then
        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_duty_%s'):format(branch.id),
            coords = branch.duty.coords,
            size = branch.duty.size or vec3(1.5, 1.5, 2.0),
            rotation = branch.duty.rotation or 0.0,
            options = {
                {
                    name = ('icecream_duty_opt_%s'):format(branch.id),
                    label = L('duty_target'),
                    icon = 'clipboard-user',
                    distance = 2.0,
                    canInteract = function() return IC.isEmployee() end,
                    onSelect = function()
                        TriggerServerEvent('icecream:server:toggleDuty', branch.id)
                    end,
                },
            },
        })
    end

    -- ── محطات العمل
    for _, station in ipairs(branch.stations or {}) do
        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_station_%s_%s'):format(branch.id, station.id),
            coords = station.coords,
            size = station.size or vec3(1.5, 1.5, 1.5),
            rotation = station.rotation or 0.0,
            options = {
                {
                    name = ('icecream_station_opt_%s_%s'):format(branch.id, station.id),
                    label = L('station_target', station.label),
                    icon = station.icon or 'ice-cream',
                    distance = 2.0,
                    canInteract = requireWork('canCraft'),
                    onSelect = function()
                        IC.client.openCraftMenu(branch, station)
                    end,
                },
            },
        })
    end

    -- ── الكاشير
    if branch.register then
        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_register_%s'):format(branch.id),
            coords = branch.register.coords,
            size = branch.register.size or vec3(1.5, 1.5, 1.5),
            rotation = branch.register.rotation or 0.0,
            options = {
                {
                    name = ('icecream_register_opt_%s'):format(branch.id),
                    label = L('register_target'),
                    icon = 'cash-register',
                    distance = 2.0,
                    canInteract = requireWork('canRegister'),
                    onSelect = function()
                        IC.client.openRegisterMenu(branch)
                    end,
                },
            },
        })
    end

    -- ── الفريزر
    if branch.freezer then
        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_freezer_%s'):format(branch.id),
            coords = branch.freezer.coords,
            size = branch.freezer.size or vec3(1.5, 1.5, 2.0),
            rotation = branch.freezer.rotation or 0.0,
            options = {
                {
                    name = ('icecream_freezer_opt_%s'):format(branch.id),
                    label = L('freezer_target'),
                    icon = 'snowflake',
                    distance = 2.0,
                    canInteract = requireWork('canFreezer'),
                    onSelect = function()
                        if IC.inventory == 'ox' then
                            exports.ox_inventory:openInventory('stash', ('icecream_freezer_%s'):format(branch.id))
                        else
                            IC.notify(L('error_generic'), 'error')
                        end
                    end,
                },
            },
        })
    end

    -- ── المورّد
    if branch.supply and Config.Supply.enabled then
        local options = {
            {
                name = ('icecream_supply_opt_%s'):format(branch.id),
                label = L('supply_target'),
                icon = 'box-open',
                distance = 2.5,
                canInteract = requireWork('canSupply'),
                onSelect = function()
                    IC.client.openSupplyMenu(branch)
                end,
            },
        }

        if Config.Supply.run.enabled then
            options[#options + 1] = {
                name = ('icecream_supplyrun_opt_%s'):format(branch.id),
                label = L('supply_run_start'),
                icon = 'truck-ramp-box',
                distance = 2.5,
                canInteract = requireWork('canSupply'),
                onSelect = function()
                    IC.client.toggleSupplyRun(branch)
                end,
            }
        end

        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_supply_%s'):format(branch.id),
            coords = branch.supply.coords,
            size = branch.supply.size or vec3(1.8, 1.8, 2.0),
            rotation = branch.supply.rotation or 0.0,
            options = options,
        })
    end

    -- ── مكتب الإدارة
    if branch.boss then
        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_boss_%s'):format(branch.id),
            coords = branch.boss.coords,
            size = branch.boss.size or vec3(1.5, 1.5, 2.0),
            rotation = branch.boss.rotation or 0.0,
            options = {
                {
                    name = ('icecream_boss_opt_%s'):format(branch.id),
                    label = L('boss_target'),
                    icon = 'briefcase',
                    distance = 2.0,
                    canInteract = requireWork('isBoss'),
                    onSelect = function()
                        IC.client.openBossMenu(branch)
                    end,
                },
            },
        })
    end

    -- ── عربة المثلجات
    if branch.truck and Config.Truck.enabled then
        zones[#zones + 1] = IC.addBoxZone({
            name = ('icecream_truck_%s'):format(branch.id),
            coords = branch.truck.park,
            size = vec3(4.0, 6.0, 3.0),
            rotation = branch.truck.spawn.w or 0.0,
            options = {
                {
                    name = ('icecream_truck_opt_%s'):format(branch.id),
                    label = L('truck_target'),
                    icon = 'truck',
                    distance = 3.5,
                    canInteract = requireWork(),
                    onSelect = function()
                        IC.client.openTruckMenu(branch)
                    end,
                },
            },
        })
    end
end

local function registerAll()
    for i = 1, #Locations.Branches do
        registerBranch(Locations.Branches[i])
    end
    IC.debug('سجّلت %s منطقة تفاعل', #zones)
end

local function removeAll()
    for i = 1, #zones do
        IC.removeZone(zones[i])
    end
    zones = {}
end

CreateThread(function()
    Wait(1000)
    registerAll()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= IC.resource then return end
    removeAll()
end)
