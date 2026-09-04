---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Crafting and ingredient accounting.

    The client sends only { station, recipe, batch }. Everything that decides
    what is consumed and produced comes from config/recipes.lua on the server.

    Ingredients are taken BEFORE the progress bar runs, so a player cannot start
    several crafts against one set of ingredients. A finish call with no matching
    start is rejected and logged.
]]

MN = MN or {}
MN.crafting = {}

-- [source] = { recipe, batch, expires }
local reservations = {}

-- ═══════════════════════════════════════════════════════════════
-- Ingredient checking, with the "any scoop" wildcard
-- ═══════════════════════════════════════════════════════════════

---Does the player hold everything this recipe needs, batch times over?
---Explicit ingredients are reserved first, then the wildcard draws only from
---what is left, so a recipe asking for both a specific scoop and "any scoop"
---can never satisfy both from the same single item.
---@param src number
---@param ingredients table
---@param batch number
---@return boolean ok, table missing
function MN.crafting.check(src, ingredients, batch)
    batch = batch or 1
    local missing, reserved, counts = {}, {}, {}

    local function have(name)
        if counts[name] == nil then counts[name] = MN.itemCount(src, name) end
        return counts[name]
    end

    local wildcards = {}

    for i = 1, #ingredients do
        local ingredient = ingredients[i]
        local need = ingredient.count * batch

        if ingredient.item == Products.SCOOP_ANY then
            wildcards[#wildcards + 1] = need
        else
            local available = have(ingredient.item) - (reserved[ingredient.item] or 0)
            if available < need then
                missing[#missing + 1] = {
                    item = ingredient.item, need = need, have = math.max(available, 0),
                }
            else
                reserved[ingredient.item] = (reserved[ingredient.item] or 0) + need
            end
        end
    end

    for i = 1, #wildcards do
        local need = wildcards[i]
        local pool = 0
        for _, name in ipairs(Products.scoopNames) do
            pool = pool + math.max(have(name) - (reserved[name] or 0), 0)
        end

        if pool < need then
            missing[#missing + 1] = { item = Products.SCOOP_ANY, need = need, have = pool }
        else
            local remaining = need
            for _, name in ipairs(Products.scoopNames) do
                if remaining <= 0 then break end
                local free = math.max(have(name) - (reserved[name] or 0), 0)
                local take = math.min(free, remaining)
                if take > 0 then
                    reserved[name] = (reserved[name] or 0) + take
                    remaining = remaining - take
                end
            end
        end
    end

    return #missing == 0, missing
end

---Consume the ingredients. Builds the whole removal plan first and only then
---applies it, so a shortfall discovered halfway cannot leave a half-charged
---player.
---@param src number
---@param ingredients table
---@param batch number
---@return boolean
function MN.crafting.consume(src, ingredients, batch)
    batch = batch or 1
    local plan = {}

    for i = 1, #ingredients do
        local ingredient = ingredients[i]
        local need = ingredient.count * batch

        if ingredient.item == Products.SCOOP_ANY then
            local remaining = need
            for _, name in ipairs(Products.scoopNames) do
                if remaining <= 0 then break end
                local free = MN.itemCount(src, name) - (plan[name] or 0)
                local take = math.min(math.max(free, 0), remaining)
                if take > 0 then
                    plan[name] = (plan[name] or 0) + take
                    remaining = remaining - take
                end
            end
            if remaining > 0 then return false end
        else
            plan[ingredient.item] = (plan[ingredient.item] or 0) + need
            if MN.itemCount(src, ingredient.item) < plan[ingredient.item] then return false end
        end
    end

    for item, count in pairs(plan) do
        if not MN.removeItem(src, item, count) then
            MN.error('failed removing %sx %s from %s mid-craft', count, item, src)
            return false
        end
    end
    return true
end

---Human-readable list of what is short, for the notification.
---@param missing table
---@return string
local function describeMissing(missing)
    local parts = {}
    for i = 1, #missing do
        local entry = missing[i]
        parts[#parts + 1] = ('%s (%s/%s)'):format(
            Products.label(entry.item), entry.have, entry.need)
    end
    return table.concat(parts, ', ')
end

-- ═══════════════════════════════════════════════════════════════
-- Melting
-- ═══════════════════════════════════════════════════════════════

---Remaining value of a product given when it was made.
---@param metadata table|nil
---@return number ratio, boolean ruined
function MN.crafting.freshness(metadata)
    if not Config.Melting.enabled then return 1.0, false end

    local madeAt = metadata and tonumber(metadata.madeAt)
    if not madeAt then return 1.0, false end

    local ageMinutes = (os.time() - madeAt) / 60
    if ageMinutes <= Config.Melting.freshMinutes then return 1.0, false end

    if Config.Melting.ruinMinutes > 0 and ageMinutes >= Config.Melting.ruinMinutes then
        return 0.0, true
    end

    local endpoint = Config.Melting.ruinMinutes > 0
        and Config.Melting.ruinMinutes
        or (Config.Melting.freshMinutes * 3)
    local span = math.max(endpoint - Config.Melting.freshMinutes, 1)
    local decayed = (ageMinutes - Config.Melting.freshMinutes) / span
    local ratio = 1.0 - decayed * (1.0 - Config.Melting.minValueRatio)

    return math.max(ratio, Config.Melting.minValueRatio), false
end

---Take a finished product from a player, freshest first, and report the
---average freshness of what was taken so the sale can be priced honestly.
---@param src number
---@param item string
---@param count number
---@return boolean ok, number ratio
function MN.crafting.takeProduct(src, item, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false, 0 end

    -- Only ox_inventory carries per-slot metadata; everywhere else a product is
    -- simply a product.
    if MN.inventory ~= MN.INV.OX or not Config.Melting.enabled or not Products.perishable(item) then
        if MN.itemCount(src, item) < count then return false, 0 end
        return MN.removeItem(src, item, count), 1.0
    end

    local slots = exports.ox_inventory:Search(src, 'slots', item)
    if type(slots) ~= 'table' then return false, 0 end

    table.sort(slots, function(a, b)
        local am = (a.metadata and tonumber(a.metadata.madeAt)) or math.huge
        local bm = (b.metadata and tonumber(b.metadata.madeAt)) or math.huge
        return am > bm
    end)

    local plan, remaining, weighted = {}, count, 0.0
    for i = 1, #slots do
        if remaining <= 0 then break end
        local slot = slots[i]
        local available = math.floor(tonumber(slot.count) or 0)
        if available > 0 then
            local ratio, ruined = MN.crafting.freshness(slot.metadata)
            if not ruined then
                local take = math.min(available, remaining)
                plan[#plan + 1] = { slot = slot.slot, count = take }
                weighted = weighted + ratio * take
                remaining = remaining - take
            end
        end
    end

    if remaining > 0 then return false, 0 end

    for i = 1, #plan do
        if not exports.ox_inventory:RemoveItem(src, item, plan[i].count, nil, plan[i].slot) then
            MN.error('failed removing %s from slot %s', item, plan[i].slot)
            return false, 0
        end
    end

    return true, weighted / count
end

-- ═══════════════════════════════════════════════════════════════
-- Craft: start
-- ═══════════════════════════════════════════════════════════════

---Validate a craft request end to end. Returns nil when anything is off.
---@param src number
---@param payload any
---@return table|nil recipe, table|nil player, number batch
local function validate(src, payload)
    if type(payload) ~= 'table' then
        MN.reject(src, 'payload', 'craft')
        return nil
    end

    local station = Locations.station(payload.station)
    if not station then
        MN.reject(src, 'station', tostring(payload.station))
        return nil
    end

    local recipe = Recipes.resolve(payload.recipe, station.id)
    if not recipe then
        MN.reject(src, 'recipe', ('%s @ %s'):format(tostring(payload.recipe), station.id))
        return nil
    end

    local batch = MN.int(payload.batch, 1, Config.Crafting.maxBatch)
    if not batch then
        MN.reject(src, 'batch', tostring(payload.batch))
        return nil
    end

    local player = MN.gate(src, MN.PERM.CRAFT, station.coords, Config.Crafting.maxDistance + 1.0)
    if not player then return nil end

    if player.job.grade < (recipe.grade or 0) then
        MN.notify(src, 'craft_locked', 'error', Permissions.gradeLabel(recipe.grade))
        return nil
    end

    return recipe, player, batch
end

lib.callback.register('mangonazlet:server:craftStart', function(source, payload)
    local src = source

    if not MN.rateLimit(src, 'craft', Config.Crafting.cooldownMs) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local recipe, player, batch = validate(src, payload)
    if not recipe then return false end

    local existing = reservations[src]
    if existing and existing.expires > os.time() then
        MN.notify(src, 'busy', 'error')
        return false
    end

    local ok, missing = MN.crafting.check(src, recipe.ingredients, batch)
    if not ok then
        MN.notify(src, 'craft_missing', 'error', describeMissing(missing))
        return false
    end

    local yield = recipe.result.count * batch
    if not MN.canCarry(src, recipe.result.item, yield) then
        MN.notify(src, 'inventory_full', 'error')
        return false
    end

    if not MN.crafting.consume(src, recipe.ingredients, batch) then
        MN.notify(src, 'error_generic', 'error')
        return false
    end

    local duration = math.floor(recipe.time * batch * Config.Crafting.timeMultiplier)
    reservations[src] = {
        recipe = recipe.id,
        batch = batch,
        expires = os.time() + math.ceil(duration / 1000) + 15,
    }

    MN.debug('%s started %s x%s', player.name, recipe.id, batch)

    return {
        duration = duration,
        skillCheck = Config.Crafting.skillCheck.enabled
            and (recipe.difficulty or 1) >= Config.Crafting.skillCheck.minDifficulty,
        difficulty = recipe.difficulty or 1,
        anim = recipe.anim,
        label = Products.label(recipe.result.item),
        yield = yield,
    }
end)

-- ═══════════════════════════════════════════════════════════════
-- Craft: finish
-- ═══════════════════════════════════════════════════════════════

lib.callback.register('mangonazlet:server:craftFinish', function(source, payload)
    local src = source
    if not MN.rateLimit(src, 'craftfinish', 250) then return false end

    local reservation = reservations[src]
    reservations[src] = nil

    if not reservation then
        MN.reject(src, 'craft_finish_without_start')
        return false
    end
    if reservation.expires < os.time() then
        MN.debug('stale craft reservation for %s', src)
        return false
    end

    local recipe, player, batch = validate(src, payload)
    if not recipe then return false end

    -- The reservation is the authority on what was actually started, so a client
    -- cannot start a cheap recipe and finish an expensive one.
    if recipe.id ~= reservation.recipe or batch ~= reservation.batch then
        MN.reject(src, 'craft_mismatch',
            ('started %s x%s, finished %s x%s'):format(reservation.recipe, reservation.batch, recipe.id, batch))
        return false
    end

    -- A failed skill check costs the ingredients. That is the intended penalty.
    if payload.success ~= true then
        MN.debug('%s failed or cancelled %s', player.name, recipe.id)
        return false
    end

    local yield = recipe.result.count * batch
    local metadata
    if Config.Melting.enabled and Products.perishable(recipe.result.item) then
        metadata = { madeAt = os.time(), quality = 100 }
    end

    if not MN.addItem(src, recipe.result.item, yield, metadata) then
        MN.notify(src, 'inventory_full', 'error')
        return false
    end

    MN.db.log(Locations.shop.id, player.citizenid, 'craft',
        ('%s x%s'):format(recipe.id, yield), 0)
    MN.notify(src, 'craft_done', 'success', yield, Products.label(recipe.result.item))
    return true
end)

AddEventHandler('playerDropped', function()
    reservations[source] = nil
end)
