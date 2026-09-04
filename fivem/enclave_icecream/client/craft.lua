---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — واجهة التصنيع
    ---------------------------------
    القائمة تعرض المكونات المتوفرة/الناقصة، ثم شريط تقدم واختبار مهارة اختياري.
    كل ما يهم أمنيًا يُعاد التحقق منه على السيرفر — هذا للعرض والتجربة فقط.
]]

IC = IC or {}
IC.client = IC.client or {}

---يبني سطر ميتاداتا للمكونات مع الكميات المتوفرة
---@param recipe table
---@param batch number
---@return table metadata, boolean canMake
local function buildMetadata(recipe, batch)
    local metadata = {
        { label = L('craft_ingredients'), value = ('%s'):format(#recipe.ingredients) },
    }
    local canMake = true

    for _, ing in ipairs(recipe.ingredients) do
        local need = ing.count * batch
        local have = IC.countWithWildcard(ing.item)
        local label = ing.item == Recipes.ScoopWildcard and 'أي كرة مثلجات' or ing.item
        if have < need then canMake = false end
        metadata[#metadata + 1] = {
            label = label,
            value = ('%s / %s'):format(have, need),
        }
    end

    metadata[#metadata + 1] = {
        label = L('craft_makes'),
        value = ('%s'):format(recipe.result.count * batch),
    }
    metadata[#metadata + 1] = {
        label = L('craft_time'),
        value = ('%.1f ث'):format((recipe.time * batch * Config.Crafting.timeMultiplier) / 1000),
    }
    metadata[#metadata + 1] = {
        label = L('craft_price'),
        value = ('%s%s'):format(L('money_symbol'), IC.money(recipe.sellPrice or 0)),
    }

    return metadata, canMake
end

---ينفّذ عملية التصنيع كاملة
---@param branch table
---@param station table
---@param recipe table
---@param batch number
local function runCraft(branch, station, recipe, batch)
    if IC.busy then
        IC.notify(L('busy'), 'error')
        return
    end

    local payload = {
        branch = branch.id,
        station = station.id,
        recipe = recipe.id,
        batch = batch,
    }

    -- المرحلة 1: السيرفر يتحقق ويخصم المكونات
    local start = lib.callback.await('icecream:server:startCraft', false, payload)
    if not start then return end

    IC.client.setBusy(true)
    IC.client.playAnim(start.anim)

    -- progressCircle يرجّع false عند الإلغاء (لا nil)، فنفرّق بأنفسنا بين
    -- «ألغى الشريط» و«فشل اختبار المهارة» لعرض الرسالة الصحيحة.
    local completed = lib.progressCircle({
        label = ('%s — %s'):format(L('craft_progress'), start.label),
        duration = start.duration,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = start.anim and { dict = start.anim.dict, clip = start.anim.clip } or nil,
    })

    local success = completed == true
    local failedCheck = false

    -- اختبار المهارة بعد شريط التقدم (لو الوصفة صعبة)
    if success and start.skillCheck then
        local difficulty = math.min(math.max(start.difficulty or 1, 1), 5)
        local checks = {
            [1] = { 'easy' },
            [2] = { 'easy', 'easy' },
            [3] = { 'easy', 'medium' },
            [4] = { 'medium', 'medium', 'hard' },
            [5] = { 'hard', 'hard', 'hard' },
        }
        success = lib.skillCheck(checks[difficulty], { 'w', 'a', 's', 'd' }) == true
        failedCheck = not success
    end

    IC.client.stopAnim()
    IC.client.setBusy(false)

    -- المرحلة 2: السيرفر يسلّم المنتج (أو لا)
    payload.success = success
    local delivered = lib.callback.await('icecream:server:finishCraft', false, payload)

    if not delivered and not success then
        IC.notify(failedCheck and L('craft_failed') or L('craft_cancelled'),
            failedCheck and 'error' or 'inform')
    end
end

---يسأل عن الكمية ثم يصنع
---@param branch table
---@param station table
---@param recipe table
local function askAmountAndCraft(branch, station, recipe)
    local maxBatch = Config.Crafting.maxBatch

    if maxBatch <= 1 then
        runCraft(branch, station, recipe, 1)
        return
    end

    local input = lib.inputDialog(L('craft_amount_title'), {
        {
            type = 'slider',
            label = recipe.label,
            description = L('craft_amount_desc', maxBatch),
            default = 1,
            min = 1,
            max = maxBatch,
        },
    })

    if not input or not input[1] then return end
    runCraft(branch, station, recipe, math.floor(input[1]))
end

---يفتح قائمة محطة عمل
---@param branch table
---@param station table
function IC.client.openCraftMenu(branch, station)
    if not IC.checkAccess('canCraft') then return end

    local recipes = Recipes.forStation(station.id)
    if #recipes == 0 then
        IC.notify(L('craft_no_recipes'), 'error')
        return
    end

    local options = {}
    for i = 1, #recipes do
        local recipe = recipes[i]
        local locked = IC.job.grade < (recipe.grade or 0)
        local metadata, canMake = buildMetadata(recipe, 1)

        options[#options + 1] = {
            title = recipe.label,
            description = locked
                and L('craft_grade_locked', IC.gradeInfo(recipe.grade).label)
                or recipe.description,
            icon = recipe.icon or 'ice-cream',
            iconColor = locked and '#8a8a8a' or (canMake and '#4ade80' or '#f87171'),
            disabled = locked,
            metadata = metadata,
            onSelect = function()
                askAmountAndCraft(branch, station, recipe)
            end,
        }
    end

    lib.registerContext({
        id = 'icecream_craft_menu',
        title = L('craft_menu_title', station.label),
        description = L('craft_menu_subtitle'),
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_craft_menu')
end
