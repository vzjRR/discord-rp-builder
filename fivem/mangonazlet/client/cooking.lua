---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Preparing product at a station.

    The menu shows what is possible; the server decides what actually happens.
    Ingredients are already gone by the time the progress bar starts, which is
    why a failed skill check costs something.
]]

MN = MN or {}

---Ingredient lines plus yield, time and value, for the context menu.
---@param recipe table
---@param batch number
---@return table metadata, boolean possible
local function describe(recipe, batch)
    local metadata = {}
    local possible = true

    for _, ingredient in ipairs(recipe.ingredients) do
        local need = ingredient.count * batch
        local have = MN.countIngredient(ingredient.item)
        if have < need then possible = false end

        metadata[#metadata + 1] = {
            label = Products.label(ingredient.item),
            value = ('%s / %s'):format(have, need),
        }
    end

    metadata[#metadata + 1] = {
        label = T('craft_yield'),
        value = tostring(recipe.result.count * batch),
    }
    metadata[#metadata + 1] = {
        label = T('craft_duration'),
        value = ('%.1f%s'):format(
            (recipe.time * batch * Config.Crafting.timeMultiplier) / 1000, T('seconds_short')),
    }
    metadata[#metadata + 1] = {
        label = T('craft_price'),
        value = ('%s%s'):format(T('currency'), MN.money(Products.price(recipe.result.item))),
    }

    return metadata, possible
end

---Run one preparation from start to finish.
---@param station table
---@param recipe table
---@param batch number
local function prepare(station, recipe, batch)
    if MN.busy then
        MN.notify(T('busy'), 'error')
        return
    end

    local payload = { station = station.id, recipe = recipe.id, batch = batch }

    local start = lib.callback.await('mangonazlet:server:craftStart', false, payload)
    if not start then return end

    MN.setBusy(true)
    MN.playAnim(start.anim)

    local completed = lib.progressCircle({
        label = ('%s — %s'):format(T('craft_working'), start.label),
        duration = start.duration,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = start.anim and { dict = start.anim.dict, clip = start.anim.clip } or nil,
    })

    local success = completed == true
    local failedCheck = false

    if success and start.skillCheck then
        local difficulty = math.min(math.max(start.difficulty or 1, 1), 5)
        local levels = {
            [1] = { 'easy' },
            [2] = { 'easy', 'easy' },
            [3] = { 'easy', 'medium' },
            [4] = { 'medium', 'medium', 'hard' },
            [5] = { 'hard', 'hard', 'hard' },
        }
        success = lib.skillCheck(levels[difficulty], { 'w', 'a', 's', 'd' }) == true
        failedCheck = not success
    end

    MN.stopAnim()
    MN.setBusy(false)

    payload.success = success
    local delivered = lib.callback.await('mangonazlet:server:craftFinish', false, payload)

    if not delivered and not success then
        MN.notify(failedCheck and T('craft_failed') or T('craft_cancelled'),
            failedCheck and 'error' or 'inform')
    end
end

---Ask how many batches, then prepare.
---@param station table
---@param recipe table
local function askBatch(station, recipe)
    local maxBatch = Config.Crafting.maxBatch

    if maxBatch <= 1 then
        prepare(station, recipe, 1)
        return
    end

    local input = lib.inputDialog(Products.label(recipe.result.item), { {
        type = 'slider',
        label = T('craft_amount_t'),
        description = T('craft_amount', maxBatch),
        default = 1, min = 1, max = maxBatch,
    } })

    if not input or not input[1] then return end
    prepare(station, recipe, math.floor(input[1]))
end

---@param station table
function MN.openCrafting(station)
    if not MN.checkAccess(MN.PERM.CRAFT) then return end

    local recipes = Recipes.forStation(station.id)
    if #recipes == 0 then
        MN.notify(T('craft_none'), 'error')
        return
    end

    local options = {}
    for i = 1, #recipes do
        local recipe = recipes[i]
        local locked = MN.job.grade < (recipe.grade or 0)
        local metadata, possible = describe(recipe, 1)
        local product = Products.get(recipe.result.item)

        options[#options + 1] = {
            title = Products.label(recipe.result.item),
            description = locked
                and T('craft_locked', Permissions.gradeLabel(recipe.grade))
                or (product and product.desc and product.desc[Config.Locale]) or nil,
            icon = recipe.icon,
            iconColor = locked and '#8a8a8a' or (possible and Config.UI.theme.leaf or '#c0392b'),
            disabled = locked,
            metadata = metadata,
            onSelect = function() askBatch(station, recipe) end,
        }
    end

    lib.registerContext({
        id = 'mn_crafting',
        title = Locations.label(station),
        description = T('craft_subtitle'),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_crafting')
end
