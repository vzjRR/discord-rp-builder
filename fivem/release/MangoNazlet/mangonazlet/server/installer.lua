---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Automatic installation.

    This is what removes the manual setup an ice cream job normally demands.
    On every start it makes the running server match config/products.lua and
    config/permissions.lua, by whichever route that framework actually supports:

      JOB
        qbx_core   exports.qbx_core:CreateJobs()   runtime, re-applied each start
        qb-core    exports['qb-core']:AddJobs()    runtime, re-applied each start
        ESX        INSERT into jobs / job_grades   persistent
        standalone handled internally by this resource

      ITEMS
        qb-core        exports['qb-core']:AddItems()   runtime, no restart needed
        ox_inventory   no runtime API exists, so data/items.lua is patched inside
                       a clearly marked block, after a backup, and only when the
                       block is missing or stale
        ESX (no ox)    INSERT into the items table
        qs/qb-inv      served by the qb-core shared table above

    Everything here is idempotent: running it a hundred times changes nothing
    after the first.
]]

MN = MN or {}
MN.installer = {}

local report = {}

local function note(line, ...)
    local text = select('#', ...) > 0 and line:format(...) or line
    report[#report + 1] = text
    MN.print(text)
end

-- ═══════════════════════════════════════════════════════════════
-- Job registration
-- ═══════════════════════════════════════════════════════════════

---Build the job table in the shape the detected framework expects.
---
---The two frameworks key their grades differently, and getting it wrong is not
---cosmetic. qb-core's paycheck loop looks a grade up as
---    jobData['grades'][tostring(player.job.grade.level)]
---so a numerically keyed table yields nil there, the payment falls through to
---nil, and qb-core then errors comparing nil with a number on every payday.
---qbx_core uses numeric keys. So: strings for qb-core, numbers for qbx_core.
---@param stringKeys boolean
---@return table
local function buildJob(stringKeys)
    local grades = {}

    for _, entry in ipairs(Permissions.ordered()) do
        local key = stringKeys and tostring(entry.level) or entry.level
        grades[key] = {
            name = Permissions.gradeLabel(entry.level, 'en'),
            label = Permissions.gradeLabel(entry.level, 'en'),
            payment = entry.def.pay,
            isboss = entry.def.owner == true or nil,
            bankAuth = entry.def.owner == true or nil,
        }
    end

    return {
        label = 'MangoNazlet',
        type = 'mangonazlet',
        defaultDuty = false,
        offDutyPay = false,
        grades = grades,
    }
end

---@return boolean
function MN.installer.job()
    if not Config.AutoInstall.job then return false end

    if MN.framework == MN.FW.QBX then
        local job = buildJob(false)   -- qbx_core: numeric grade keys
        local ok, err = pcall(function()
            return exports.qbx_core:CreateJobs({ [Permissions.job] = job })
        end)
        if ok then
            note('job "%s" registered with qbx_core (%s grades)', Permissions.job, MN.count(job.grades))
            return true
        end
        MN.warn('qbx_core job registration failed: %s', tostring(err))
        return false

    elseif MN.framework == MN.FW.QB then
        local job = buildJob(true)    -- qb-core: string grade keys
        local ok, err = pcall(function()
            return exports['qb-core']:AddJobs({ [Permissions.job] = job })
        end)
        if ok then
            note('job "%s" registered with qb-core (%s grades, string keys)',
                Permissions.job, MN.count(job.grades))
            return true
        end
        MN.warn('qb-core job registration failed: %s', tostring(err))
        return false

    elseif MN.framework == MN.FW.ESX then
        if not MN.db.ready then
            MN.warn('cannot register the ESX job without a database connection.')
            return false
        end

        MySQL.update.await(
            'INSERT INTO `jobs` (`name`, `label`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `label` = VALUES(`label`)',
            { Permissions.job, 'MangoNazlet' })

        for _, entry in ipairs(Permissions.ordered()) do
            MySQL.update.await([[INSERT INTO `job_grades`
                (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`)
                VALUES (?, ?, ?, ?, ?, '{}', '{}')
                ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `salary` = VALUES(`salary`)]],
                {
                    Permissions.job, entry.level,
                    ('grade%s'):format(entry.level),
                    Permissions.gradeLabel(entry.level, 'en'),
                    entry.def.pay,
                })
        end

        note('job "%s" written to the ESX jobs tables (%s grades)',
            Permissions.job, #Permissions.ordered())
        return true
    end

    note('standalone mode — employment is managed by MangoNazlet itself')
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- Item definitions
-- ═══════════════════════════════════════════════════════════════

---Every item this resource owns, in ox_inventory shape.
---@return table
local function oxItems()
    local items = {}

    for i = 1, #Products.all do
        local product = Products.all[i]

        local client = { image = product.image }
        if product.hunger or product.thirst then
            client.status = {}
            if product.hunger then client.status.hunger = product.hunger end
            if product.thirst then client.status.thirst = product.thirst end
        end
        if product.consumeAnim then client.anim = product.consumeAnim end
        if product.useTime then client.usetime = product.useTime end
        if product.consumeAnim == 'eating' then client.prop = 'burger'
        elseif product.consumeAnim == 'drinking' then client.prop = 'cup' end

        local entry = {
            label = product.label.en,
            weight = product.weight,
            stack = product.stack ~= false,
            close = product.useTime ~= nil,
            description = product.desc and product.desc.en or nil,
            client = client,
        }

        -- Melting products decay in the inventory too, so what the player sees
        -- matches what the shop pays for it.
        if product.perishable and Config.Melting.ruinMinutes > 0 then
            entry.degrade = Config.Melting.ruinMinutes
            entry.decay = true
        end

        -- Consumables run through our export so a melted item cannot be eaten.
        if product.useTime then
            entry.consume = 1
            entry.server = { export = ('%s.consume'):format(MN.RESOURCE) }
        end

        items[product.name] = entry
    end

    return items
end

---Serialise an ox_inventory item entry as Lua source.
---@param name string
---@param entry table
---@return string
local function serialiseOxItem(name, entry)
    local parts = {}
    local function add(line, ...) parts[#parts + 1] = ('\t\t' .. line):format(...) end

    local function quote(value)
        return "'" .. tostring(value):gsub('\\', '\\\\'):gsub("'", "\\'") .. "'"
    end

    add('label = %s,', quote(entry.label))
    add('weight = %d,', entry.weight)
    add('stack = %s,', tostring(entry.stack))
    add('close = %s,', tostring(entry.close))
    if entry.description then add('description = %s,', quote(entry.description)) end
    if entry.degrade then add('degrade = %d,', entry.degrade) end
    if entry.decay then add('decay = true,') end
    if entry.consume then add('consume = %s,', tostring(entry.consume)) end

    local client = entry.client
    if client then
        local inner = {}
        if client.image then inner[#inner + 1] = ('image = %s'):format(quote(client.image)) end
        if client.status then
            local status = {}
            if client.status.hunger then status[#status + 1] = ('hunger = %d'):format(client.status.hunger) end
            if client.status.thirst then status[#status + 1] = ('thirst = %d'):format(client.status.thirst) end
            inner[#inner + 1] = ('status = { %s }'):format(table.concat(status, ', '))
        end
        if client.anim then inner[#inner + 1] = ('anim = %s'):format(quote(client.anim)) end
        if client.prop then inner[#inner + 1] = ('prop = %s'):format(quote(client.prop)) end
        if client.usetime then inner[#inner + 1] = ('usetime = %d'):format(client.usetime) end
        add('client = { %s },', table.concat(inner, ', '))
    end

    if entry.server and entry.server.export then
        add('server = { export = %s },', quote(entry.server.export))
    end

    return ("\t['%s'] = {\n%s\n\t},"):format(name, table.concat(parts, '\n'))
end

---Build the block written into ox_inventory/data/items.lua.
---@return string block, string signature
local function buildOxBlock()
    local items = oxItems()

    local names = {}
    for name in pairs(items) do names[#names + 1] = name end
    table.sort(names)

    local body = {}
    for i = 1, #names do
        body[#body + 1] = serialiseOxItem(names[i], items[names[i]])
    end

    -- The signature changes whenever the item set changes, which is how a stale
    -- block is detected and replaced on a later start.
    local signature = ('%s|%d'):format(MN.VERSION, #names)

    local block = ('%s\n\t-- signature: %s\n\t-- Generated by %s. Edit config/products.lua instead.\n%s\n\t%s')
        :format(MN.PATCH_BEGIN, signature, MN.BRAND, table.concat(body, '\n'), MN.PATCH_END)

    return block, signature
end

---Patch ox_inventory/data/items.lua.
---@return 'unchanged'|'written'|'failed'
local function installOxItems()
    local target = 'ox_inventory'
    local path = 'data/items.lua'

    local current = LoadResourceFile(target, path)
    if not current then
        MN.warn('could not read %s/%s — item installation skipped.', target, path)
        return 'failed'
    end

    local block, signature = buildOxBlock()

    -- Already present and current? Nothing to do.
    local existing = current:match(MN.PATCH_BEGIN:gsub('%p', '%%%0') .. '.-signature: ([^\n]+)')
    if existing and existing == signature then
        return 'unchanged'
    end

    -- Strip any previous block so repeated installs never stack.
    local beginPattern = MN.PATCH_BEGIN:gsub('%p', '%%%0')
    local endPattern = MN.PATCH_END:gsub('%p', '%%%0')
    local stripped = current:gsub('\n?' .. beginPattern .. '.-' .. endPattern .. '\n?', '\n')

    -- The file is one `return { ... }` table; insert before its final brace.
    local lastBrace = stripped:match('.*()}')
    if not lastBrace then
        MN.warn('%s/%s is not in the expected format — item installation skipped.', target, path)
        return 'failed'
    end

    local patched = stripped:sub(1, lastBrace - 1) .. '\n' .. block .. '\n' .. stripped:sub(lastBrace)

    if Config.AutoInstall.backup then
        local backup = LoadResourceFile(target, 'data/items.mangonazlet.bak')
        if not backup then
            SaveResourceFile(target, 'data/items.mangonazlet.bak', current, -1)
        end
    end

    if not SaveResourceFile(target, path, patched, -1) then
        MN.warn('could not write %s/%s — check file permissions.', target, path)
        return 'failed'
    end

    return 'written'
end

---@return boolean
function MN.installer.items()
    if not Config.AutoInstall.items then return false end

    local count = #Products.all

    -- qb-core keeps items in a shared table that accepts runtime additions.
    if MN.framework == MN.FW.QB or (MN.inventory == MN.INV.QB and MN.hasResource('qb-core')) then
        local items = {}
        for i = 1, #Products.all do
            local product = Products.all[i]
            items[product.name] = {
                name = product.name,
                label = product.label.en,
                weight = product.weight,
                type = 'item',
                image = product.image,
                unique = false,
                useable = product.useTime ~= nil,
                shouldClose = product.useTime ~= nil,
                combinable = nil,
                description = product.desc and product.desc.en or '',
            }
        end

        local ok, err = pcall(function() return exports['qb-core']:AddItems(items) end)
        if ok then
            note('%d items registered with qb-core at runtime', count)
        else
            MN.warn('qb-core item registration failed: %s', tostring(err))
        end
    end

    -- ox_inventory: file patch, because it has no runtime item API.
    if MN.inventory == MN.INV.OX then
        local result = installOxItems()

        if result == 'unchanged' then
            note('%d items already present in ox_inventory', count)
        elseif result == 'written' then
            note('%d items written into ox_inventory/data/items.lua (backup kept)', count)
            MN.installer.inventoryNeedsRestart = true
        else
            note('^3could not install items into ox_inventory — see the warning above^7')
            return false
        end
    end

    -- ESX without ox_inventory keeps items in the database.
    if MN.framework == MN.FW.ESX and MN.inventory == MN.INV.ESX then
        if not MN.db.ready then
            MN.warn('cannot write ESX items without a database connection.')
            return false
        end
        for i = 1, #Products.all do
            local product = Products.all[i]
            MySQL.update.await([[INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`)
                VALUES (?, ?, 1, 0, 1) ON DUPLICATE KEY UPDATE `label` = VALUES(`label`)]],
                { product.name, product.label.en })
        end
        note('%d items written to the ESX items table', count)
    end

    return true
end

-- ═══════════════════════════════════════════════════════════════
-- Applying an ox_inventory patch without the owner typing anything
-- ═══════════════════════════════════════════════════════════════

---Restart ox_inventory so freshly written items take effect. Only done on an
---empty server: restarting it under players would disturb open inventories.
function MN.installer.applyInventoryRestart()
    if not MN.installer.inventoryNeedsRestart then return end
    if not Config.AutoInstall.restartInventory then
        note('^3restart ox_inventory to load the new MangoNazlet items^7')
        return
    end

    local players = GetNumPlayerIndices()
    if players > 0 then
        note('^3%d players online — ox_inventory will pick up the new items on the next empty restart^7', players)
        return
    end

    note('restarting ox_inventory to load the new items…')
    CreateThread(function()
        Wait(500)
        ExecuteCommand('ensure ox_inventory')
        Wait(2000)
        -- Our own resource holds references into ox_inventory's exports, so it
        -- restarts too and comes back against the refreshed item list.
        ExecuteCommand(('ensure %s'):format(MN.RESOURCE))
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- Verification — prove the install worked rather than assume it
-- ═══════════════════════════════════════════════════════════════

---@return boolean ok, string[] problems
function MN.installer.verify()
    local problems = {}

    -- Are the items actually visible to the inventory now?
    if MN.inventory == MN.INV.OX then
        local ok, list = pcall(function() return exports.ox_inventory:Items() end)
        if ok and type(list) == 'table' then
            local missing = 0
            for i = 1, #Products.all do
                if not list[Products.all[i].name] then missing = missing + 1 end
            end
            if missing > 0 then
                problems[#problems + 1] =
                    ('%d of %d items are not loaded in ox_inventory yet'):format(missing, #Products.all)
            end
        end
    end

    -- Is the job known to the framework?
    if MN.framework == MN.FW.QBX then
        local ok, jobs = pcall(function() return exports.qbx_core:GetJobs() end)
        if ok and type(jobs) == 'table' and not jobs[Permissions.job] then
            problems[#problems + 1] = ('job "%s" is not registered with qbx_core'):format(Permissions.job)
        end
    end

    return #problems == 0, problems
end

-- ═══════════════════════════════════════════════════════════════
-- Entry point
-- ═══════════════════════════════════════════════════════════════

---@return string[] report
function MN.installer.run()
    report = {}

    note('%s v%s starting', MN.BRAND, MN.VERSION)
    note('framework=%s inventory=%s target=%s database=%s',
        MN.framework, MN.inventory, MN.target, tostring(MN.db.ready))

    if not MN.has.oxLib then
        MN.error('ox_lib is required and is not running. Add `ensure ox_lib` BEFORE `ensure %s`.', MN.RESOURCE)
        note('^1ox_lib missing — menus, dialogs and progress bars will not work^7')
    end

    MN.installer.job()
    MN.installer.items()
    MN.installer.applyInventoryRestart()

    local ok, problems = MN.installer.verify()
    if not ok then
        for i = 1, #problems do note('^3%s^7', problems[i]) end
    end

    return report
end
