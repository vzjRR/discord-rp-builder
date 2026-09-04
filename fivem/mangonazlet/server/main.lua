---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Server core: duty tracking, storage, admin commands, boot.
]]

MN = MN or {}

-- [source] = true for everyone currently clocked in
local onDuty = {}

-- ═══════════════════════════════════════════════════════════════
-- Duty roster
-- ═══════════════════════════════════════════════════════════════

---@return number[]
function MN.onDutyList()
    local out = {}
    for src in pairs(onDuty) do
        if GetPlayerName(src) then out[#out + 1] = src else onDuty[src] = nil end
    end
    return out
end

---Send an event to every clocked-in employee.
---@param event string
function MN.broadcastToStaff(event, ...)
    for _, src in ipairs(MN.onDutyList()) do
        TriggerClientEvent(event, src, ...)
    end
end

---@param src number
function MN.clockOut(src)
    onDuty[src] = nil
end

RegisterNetEvent('mangonazlet:server:toggleDuty', function()
    local src = source
    if not MN.rateLimit(src, 'duty', 1500) then return end

    local player = MN.getPlayer(src)
    if not player or player.job.name ~= Permissions.job then
        MN.notify(src, 'not_employee', 'error')
        return
    end

    if not MN.isNear(src, Locations.shop.duty.coords, 5.0) then
        MN.reject(src, 'distance', 'duty point')
        MN.notify(src, 'too_far', 'error')
        return
    end

    local going = not player.job.onduty

    if not going and Config.BlockOffDutyWithStock then
        for i = 1, #Products.all do
            local product = Products.all[i]
            if product.category ~= 'ingredient' and MN.itemCount(src, product.name) > 0 then
                MN.notify(src, 'duty_blocked', 'error')
                return
            end
        end
    end

    MN.setDuty(src, going)
    onDuty[src] = going or nil

    if going then
        MN.db.upsertStaff(player.citizenid, Locations.shop.id, player.name, player.job.grade)
    end

    MN.notify(src, going and 'duty_on' or 'duty_off', 'success')
    MN.debug('%s (%s) duty=%s', player.name, src, tostring(going))
end)

AddEventHandler('playerDropped', function()
    onDuty[source] = nil
end)

-- ═══════════════════════════════════════════════════════════════
-- Storage (ox_inventory stashes)
-- ═══════════════════════════════════════════════════════════════

local function registerStashes()
    if MN.inventory ~= MN.INV.OX then return end

    local shop = Locations.shop
    local group = { [Permissions.job] = 0 }

    exports.ox_inventory:RegisterStash(
        ('mn_freezer_%s'):format(shop.id), T('storage_label'),
        Config.Storage.freezerSlots, Config.Storage.freezerWeight,
        false, group, shop.freezer.coords)

    exports.ox_inventory:RegisterStash(
        ('mn_pantry_%s'):format(shop.id), T('storage_ing_lbl'),
        Config.Storage.pantrySlots, Config.Storage.pantryWeight,
        false, group, shop.pantry.coords)

    MN.debug('registered freezer and pantry stashes')
end

-- ═══════════════════════════════════════════════════════════════
-- Shared state for clients
-- ═══════════════════════════════════════════════════════════════

lib.callback.register('mangonazlet:server:state', function(source)
    if not MN.rateLimit(source, 'state', 1000) then return nil end

    local player = MN.getPlayer(source)

    return {
        stock = MN.business.stockSnapshot(),
        staffOnDuty = #MN.onDutyList(),
        tickets = (player and player.job.name == Permissions.job) and MN.tickets.count() or 0,
        employed = player ~= nil and player.job.name == Permissions.job,
        grade = player and player.job.grade or 0,
    }
end)

lib.callback.register('mangonazlet:server:stats', function(source)
    -- Several aggregate queries run here, so it is rate limited like a write.
    if not MN.rateLimit(source, 'stats', 2000) then return nil end

    local player = MN.gate(source)
    if not player then return nil end

    local stats = MN.db.stats(Locations.shop.id)
    stats.yours = MN.db.staffToday(Locations.shop.id, player.citizenid)
    stats.balance = MN.business.balance()
    return stats
end)

-- Standalone clients ask the server what job they hold.
lib.callback.register('mangonazlet:server:job', function(source)
    if not MN.rateLimit(source, 'job', 1000) then return nil end

    local player = MN.getPlayer(source)
    return player and player.job or nil
end)

-- ═══════════════════════════════════════════════════════════════
-- ox_inventory consumable hook — melted product cannot be eaten
-- ═══════════════════════════════════════════════════════════════

exports('consume', function(event, item, inventory, slot)
    if event ~= 'usingItem' then return end

    local _, ruined = MN.crafting.freshness(slot and slot.metadata)
    if ruined then
        local src = type(inventory) == 'table' and inventory.id or inventory
        MN.notify(src, 'melt_ruined', 'error')
        return false
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- Admin commands
-- ═══════════════════════════════════════════════════════════════

---Permission check we own, rather than FiveM's `restricted` flag.
---
---A restricted command is hidden entirely from players without the ace, which
---reports "No such command" and tells them nothing. /mn:place also has to be
---run in game while standing where the thing should go, so it cannot be moved
---to the console the way /mn:setjob can. Checking here lets the command stay
---visible and explain exactly what is missing.
---@param src number              0 is the server console
---@param allowShopOwner boolean  also accept the shop's own Owner grade
---@return boolean
local function canAdminister(src, allowShopOwner)
    if src == 0 then return true end                                  -- console
    if IsPlayerAceAllowed(src, Config.Server.adminAce) then return true end

    if allowShopOwner then
        local player = MN.getPlayer(src)
        if player and player.job.name == Permissions.job
            and Permissions.isOwner(player.job.grade) then
            return true
        end
    end
    return false
end

---Explain the refusal, and hand over the exact line that fixes it.
---@param src number
---@param allowShopOwner boolean
local function explainDenied(src, allowShopOwner)
    local identifier = MN.identifier(src) or 'your identifier'

    TriggerClientEvent('chat:addMessage', src, {
        color = { 231, 76, 60 }, multiline = true,
        args = { 'MangoNazlet', ('You need the "%s" permission for this.'):format(Config.Server.adminAce) },
    })
    TriggerClientEvent('chat:addMessage', src, {
        color = { 245, 166, 35 }, multiline = true,
        args = { 'MangoNazlet', ('Add this to server.cfg and restart:  add_principal %s %s')
            :format(identifier, Config.Server.adminAce) },
    })

    if allowShopOwner then
        TriggerClientEvent('chat:addMessage', src, {
            color = { 245, 166, 35 }, multiline = true,
            args = { 'MangoNazlet', 'Or become the shop Owner: run  mn:setjob <id> 5  in the server console.' },
        })
    end

    MN.print('%s (%s) was refused an admin command. To grant it, add to server.cfg:',
        GetPlayerName(src) or '?', tostring(src))
    MN.print('   add_principal %s %s', identifier, Config.Server.adminAce)
end

local function registerCommands()
    lib.addCommand('mn:setjob', {
        help = 'Put a player on the MangoNazlet payroll',
        params = {
            -- Optional so ox_lib hands us the call instead of rejecting it, and
            -- we can answer a bare /mn:setjob with usage rather than a parser error.
            { name = 'id', type = 'playerId', help = 'Player server id', optional = true },
            { name = 'grade', type = 'number', optional = true,
              help = ('Grade 0-%s'):format(Permissions.maxGrade()) },
        },
    }, function(source, args)
        if not canAdminister(source, false) then
            explainDenied(source, false)
            return
        end

        local grade = MN.int(args.grade, 0, Permissions.maxGrade())

        if not args.id or not grade then
            local usage = ('usage: mn:setjob <player id> <grade 0-%s>'):format(Permissions.maxGrade())
            local grades = {}
            for _, entry in ipairs(Permissions.ordered()) do
                grades[#grades + 1] = ('%d = %s'):format(entry.level, Permissions.gradeLabel(entry.level, 'en'))
            end

            if source == 0 then
                MN.print('%s', usage)
                MN.print('   %s', table.concat(grades, '  |  '))
            else
                TriggerClientEvent('chat:addMessage', source, {
                    color = { 245, 166, 35 }, multiline = true,
                    args = { 'MangoNazlet', usage .. '\n' .. table.concat(grades, '  |  ') },
                })
            end
            return
        end

        if not MN.setJob(args.id, grade) then
            MN.notify(source, 'error_generic', 'error')
            return
        end

        local target = MN.getPlayer(args.id)
        if target then
            MN.db.upsertStaff(target.citizenid, Locations.shop.id, target.name, grade)
        end
        MN.notify(source, 'boss_ranked', 'success',
            target and target.name or tostring(args.id), Permissions.gradeLabel(grade))
    end)

    lib.addCommand('mn:place', {
        help = 'Move part of the shop to where you stand (saved to the database)',
        params = {
            -- Optional: a bare /mn:place should list the anchors, which it
            -- cannot do if ox_lib rejects the call for a missing argument.
            { name = 'anchor', type = 'string', optional = true,
              help = 'anchor name, "list", or "reset" - omit to list' },
        },
    }, function(source, args)
        -- The shop's Owner may reposition their own shop; only an admin can
        -- make someone an Owner in the first place.
        if not canAdminister(source, true) then
            explainDenied(source, true)
            return
        end

        if source == 0 then
            MN.print('/mn:place has to be run in game - it saves where you are standing.')
            return
        end

        local anchor = tostring(args.anchor or ''):lower()

        if anchor == 'list' or anchor == '' then
            MN.print('placeable anchors: %s', table.concat(Locations.anchors, ', '))
            TriggerClientEvent('chat:addMessage', source, {
                color = { 245, 166, 35 }, multiline = true,
                args = { 'MangoNazlet', table.concat(Locations.anchors, ', ') },
            })
            return
        end

        if anchor == 'reset' then
            MN.db.clearPlacements(Locations.shop.id)
            TriggerClientEvent('chat:addMessage', source, {
                color = { 245, 166, 35 },
                args = { 'MangoNazlet', 'Placements cleared. Restart the resource to apply.' },
            })
            return
        end

        local valid = false
        for i = 1, #Locations.anchors do
            if Locations.anchors[i] == anchor then valid = true break end
        end
        if not valid and not Locations.station(anchor) then
            TriggerClientEvent('chat:addMessage', source, {
                color = { 231, 76, 60 },
                args = { 'MangoNazlet', ('Unknown anchor "%s". Try /mn:place list'):format(anchor) },
            })
            return
        end

        if not MN.db.ready then
            TriggerClientEvent('chat:addMessage', source, {
                color = { 231, 76, 60 },
                args = { 'MangoNazlet', 'A database is required to save placements.' },
            })
            return
        end

        local ped = GetPlayerPed(source)
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        MN.db.savePlacement(Locations.shop.id, anchor, coords.x, coords.y, coords.z, heading)
        Locations.applyOverrides({ [anchor] = { x = coords.x, y = coords.y, z = coords.z, w = heading } })
        TriggerClientEvent('mangonazlet:client:placements', -1,
            { [anchor] = { x = coords.x, y = coords.y, z = coords.z, w = heading } })

        TriggerClientEvent('chat:addMessage', source, {
            color = { 245, 166, 35 },
            args = { 'MangoNazlet', ('Saved "%s" at %.2f, %.2f, %.2f'):format(anchor, coords.x, coords.y, coords.z) },
        })
        MN.print('placement saved: %s = %.2f, %.2f, %.2f (%.1f)', anchor, coords.x, coords.y, coords.z, heading)
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Configuration sanity check
-- ═══════════════════════════════════════════════════════════════

---@return string[]
local function validateConfig()
    local problems = {}

    local split = Config.Economy.businessShare + Config.Economy.employeeTip
    if math.abs(split - 1.0) > 0.001 then
        problems[#problems + 1] =
            ('businessShare + employeeTip = %.2f, expected 1.0'):format(split)
    end

    -- Every station in the layout must have something to make.
    for _, station in ipairs(Locations.shop.stations) do
        if #Recipes.forStation(station.id) == 0 then
            problems[#problems + 1] = ('station "%s" has no recipes'):format(station.id)
        end
    end

    -- Every recipe must belong to a station that exists.
    for id, recipe in pairs(Recipes.byId) do
        if not Locations.station(recipe.station) then
            problems[#problems + 1] = ('recipe "%s" targets unknown station "%s"'):format(id, recipe.station)
        end

        if not Products.get(recipe.result.item) then
            problems[#problems + 1] = ('recipe "%s" produces unknown product "%s"'):format(id, recipe.result.item)
        end

        for _, ingredient in ipairs(recipe.ingredients) do
            if ingredient.item ~= Products.SCOOP_ANY and not Products.get(ingredient.item) then
                problems[#problems + 1] =
                    ('recipe "%s" needs unknown product "%s"'):format(id, ingredient.item)
            end
        end

        if not Permissions.grades[recipe.grade or 0] then
            problems[#problems + 1] = ('recipe "%s" requires undefined grade %s'):format(id, tostring(recipe.grade))
        end
    end

    -- Everything a customer can order must be makeable.
    for _, entry in ipairs(Recipes.ticketPool) do
        if not Recipes.byResult[entry.item] then
            problems[#problems + 1] = ('ticket item "%s" has no recipe'):format(entry.item)
        end
    end

    -- Everything on the menu must be makeable too.
    local menu = Products.menu()
    for i = 1, #menu do
        if not Recipes.byResult[menu[i].name] then
            problems[#problems + 1] = ('menu item "%s" has no recipe'):format(menu[i].name)
        end
    end

    if Config.Supply.run.enabled and #Locations.pickups < Config.Supply.run.pickups then
        problems[#problems + 1] = ('supply run wants %d pickups but only %d are defined')
            :format(Config.Supply.run.pickups, #Locations.pickups)
    end

    return problems
end

-- ═══════════════════════════════════════════════════════════════
-- Boot
-- ═══════════════════════════════════════════════════════════════

CreateThread(function()
    -- Give oxmysql and the framework a moment to come up first.
    Wait(1000)

    MN.db.migrate()
    MN.loadStandaloneJobs()

    -- Saved placements win over the defaults in config/locations.lua.
    local placements = MN.db.loadPlacements(Locations.shop.id)
    if MN.count(placements) > 0 then
        Locations.applyOverrides(placements)
        MN.debug('applied %s saved placements', MN.count(placements))
    end

    MN.business.load()
    registerStashes()
    registerCommands()

    local report = MN.installer.run()

    local problems = validateConfig()
    if #problems > 0 then
        MN.warn('%d configuration problem(s):', #problems)
        for i = 1, #problems do MN.print('  %d) %s', i, problems[i]) end
    end

    -- Hand the placements to clients that connect later.
    GlobalState.mnPlacements = placements

    MN.print('^2ready^7 — %d products, %d recipes, balance $%s',
        #Products.all, MN.count(Recipes.byId), MN.money(MN.business.balance()))

    -- Where to actually go. Printed every start because "I cannot find it" is
    -- the first thing anyone hits on a fresh install.
    local centre = Locations.shop.centre
    MN.print('shop is at %.1f, %.1f, %.1f — players can type /mn:where for a waypoint',
        centre.x, centre.y, centre.z)
    MN.print('to staff yourself: run  mn:setjob <id> 5  in THIS console (no slash)')

    if #problems == 0 then
        report[#report + 1] = ('%d products, %d recipes, configuration OK'):format(#Products.all, MN.count(Recipes.byId))
    end
    MN.logs.install(report)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    MN.business.flush()
end)
