---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — التصنيع (سيرفري)
    ------------------------------------
    القاعدة: العميل يرسل فقط (recipeId, stationId, branchId, batch).
    كل ما عدا ذلك — الوصفة، المكونات، الوقت، السعر — يُقرأ من الكونفق على السيرفر.
]]

IC = IC or {}

-- اللاعبون الذين لديهم عملية تصنيع جارية: [src] = expiryTimestamp
local crafting = {}

---يبني نص المكونات الناقصة للعرض
---@param missing table
---@return string
local function formatMissing(missing)
    local parts = {}
    for i = 1, #missing do
        local entry = missing[i]
        parts[#parts + 1] = ('%s (%s/%s)'):format(entry.item, entry.have, entry.need)
    end
    return table.concat(parts, '، ')
end

---يتحقق من كل شروط التصنيع ويرجّع الوصفة والفرع
---@param src number
---@param data table
---@return table|nil recipe, table|nil branch, table|nil player, number batch
local function validateCraftRequest(src, data)
    if type(data) ~= 'table' then
        IC.logs.exploit(src, 'malformed_payload', 'craft')
        return nil
    end

    local branch = IC.server.resolveBranch(data.branch)
    if not branch then
        IC.logs.exploit(src, 'invalid_branch', tostring(data.branch))
        return nil
    end

    local station = Locations.getStation(branch.id, data.station)
    if not station then
        IC.logs.exploit(src, 'invalid_station', tostring(data.station))
        return nil
    end

    -- المعرّف يُترجم لوصفة حقيقية، والمحطة يجب أن تطابق محطة الوصفة
    local recipe = IC.resolveRecipe(data.recipe, station.id)
    if not recipe then
        IC.logs.exploit(src, 'invalid_recipe', ('%s @ %s'):format(tostring(data.recipe), station.id))
        return nil
    end

    local batch = IC.toInt(data.batch, 1, Config.Crafting.maxBatch)
    if not batch then
        IC.logs.exploit(src, 'invalid_batch', tostring(data.batch))
        return nil
    end

    local player = IC.server.gate(src, 'canCraft', station.coords, Config.Crafting.maxDistance + 1.0)
    if not player then return nil end

    if player.job.grade < (recipe.grade or 0) then
        IC.server.notify(src, 'craft_grade_locked', 'error', IC.gradeInfo(recipe.grade or 0).label)
        return nil
    end

    return recipe, branch, player, batch
end

-- ────────────────────────────────────────────────────────────
-- المرحلة 1: طلب البدء — نتحقق ونحجز، ونرد بالوقت المسموح
-- ────────────────────────────────────────────────────────────
lib.callback.register('icecream:server:startCraft', function(source, data)
    local src = source

    if not IC.rateLimit(src, 'craft', Config.Crafting.cooldownMs) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end

    local recipe, branch, player, batch = validateCraftRequest(src, data)
    if not recipe then return false end

    if crafting[src] and crafting[src] > os.time() then
        IC.server.notify(src, 'busy', 'error')
        return false
    end

    local ok, missing = IC.hasIngredients(src, recipe.ingredients, batch)
    if not ok then
        IC.server.notify(src, 'craft_missing', 'error', formatMissing(missing))
        return false
    end

    local resultCount = recipe.result.count * batch
    if not IC.canCarry(src, recipe.result.item, resultCount) then
        IC.server.notify(src, 'craft_full', 'error')
        return false
    end

    -- نخصم المكونات الآن — حتى ما يقدر يبدأ عدة عمليات بنفس المكونات
    if not IC.consumeIngredients(src, recipe.ingredients, batch) then
        IC.server.notify(src, 'error_generic', 'error')
        return false
    end

    local duration = math.floor(recipe.time * batch * Config.Crafting.timeMultiplier)
    -- مهلة الحجز = مدة التصنيع + هامش للاتصال
    crafting[src] = os.time() + math.ceil(duration / 1000) + 15

    IC.debug('%s بدأ تصنيع %s x%s (%sms)', player.name, recipe.id, batch, duration)

    return {
        duration = duration,
        skillCheck = Config.Crafting.skillCheck.enabled
            and (recipe.difficulty or 1) >= Config.Crafting.skillCheck.minDifficulty,
        difficulty = recipe.difficulty or 1,
        anim = recipe.anim,
        label = recipe.label,
        resultCount = resultCount,
    }
end)

-- ────────────────────────────────────────────────────────────
-- المرحلة 2: الإنهاء — العميل يبلّغ بالنجاح/الفشل، ونسلّم المنتج
--   المكونات مخصومة أصلًا، فأسوأ ما يقدر عليه الغشاش هو خسارة مكوناته.
-- ────────────────────────────────────────────────────────────
lib.callback.register('icecream:server:finishCraft', function(source, data)
    local src = source

    local reservation = crafting[src]
    crafting[src] = nil

    if not reservation then
        IC.logs.exploit(src, 'finish_without_start', 'craft')
        return false
    end
    if reservation < os.time() then
        IC.debug('حجز تصنيع منتهي الصلاحية للاعب %s', src)
        return false
    end

    local recipe, branch, player, batch = validateCraftRequest(src, data)
    if not recipe then return false end

    -- فشل أو إلغاء: المكونات ضاعت (وهذا مقصود — عقوبة الفشل)
    if data.success ~= true then
        IC.debug('%s فشل/ألغى تصنيع %s', player.name, recipe.id)
        return false
    end

    local resultCount = recipe.result.count * batch
    local metadata
    if Config.Melting.enabled and recipe.perishable then
        metadata = { madeAt = os.time(), branch = branch.id, quality = 100 }
    end

    if not IC.addItem(src, recipe.result.item, resultCount, metadata) then
        IC.server.notify(src, 'craft_full', 'error')
        return false
    end

    IC.db.log(branch.id, player.citizenid, 'craft', ('%s x%s'):format(recipe.id, resultCount), 0)
    IC.server.notify(src, 'craft_success', 'success', resultCount, recipe.label)
    return true
end)

AddEventHandler('playerDropped', function()
    crafting[source] = nil
end)
