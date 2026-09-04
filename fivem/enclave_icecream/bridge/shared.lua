---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — الجسر المشترك
    ---------------------------------
    اكتشاف الموارد الموجودة + أدوات تُستخدم على الطرفين.
    كل ما يلي يعمل على العميل والسيرفر.
]]

IC = IC or {}
IC.resource = GetCurrentResourceName()

-- ────────────────────────────────────────────────────────────
-- اكتشاف الموارد
-- ────────────────────────────────────────────────────────────

---هل المورد موجود ومشتغل؟
---@param name string
---@return boolean
function IC.hasResource(name)
    return GetResourceState(name):find('start') ~= nil
end

local function detectFramework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if IC.hasResource('qbx_core') then return 'qbx' end
    if IC.hasResource('qb-core') then return 'qb' end
    if IC.hasResource('es_extended') then return 'esx' end
    return 'standalone'
end

local function detectInventory()
    if Config.Inventory ~= 'auto' then return Config.Inventory end
    if IC.hasResource('ox_inventory') then return 'ox' end
    if IC.hasResource('qb-inventory') then return 'qb' end
    if IC.hasResource('es_extended') then return 'esx' end
    return 'none'
end

local function detectTarget()
    if Config.Target ~= 'auto' then return Config.Target end
    if IC.hasResource('ox_target') then return 'ox' end
    if IC.hasResource('qb-target') then return 'qb' end
    return 'ox'
end

IC.framework = detectFramework()
IC.inventory = detectInventory()
IC.targetSystem = detectTarget()

-- ────────────────────────────────────────────────────────────
-- التسجيل في الكونسول
-- ────────────────────────────────────────────────────────────

---@param fmt string
function IC.print(fmt, ...)
    local msg = select('#', ...) > 0 and fmt:format(...) or fmt
    print(('[%s] %s'):format(IC.resource, msg))
end

---@param fmt string
function IC.debug(fmt, ...)
    if not Config.Debug then return end
    local msg = select('#', ...) > 0 and fmt:format(...) or fmt
    print(('[%s] ^5DEBUG^7 %s'):format(IC.resource, msg))
end

---@param fmt string
function IC.warn(fmt, ...)
    local msg = select('#', ...) > 0 and fmt:format(...) or fmt
    print(('[%s] ^3تحذير:^7 %s'):format(IC.resource, msg))
end

-- ────────────────────────────────────────────────────────────
-- الترجمة
-- ────────────────────────────────────────────────────────────
-- ox_lib يحمّل locales/<Config.Locale>.json تلقائيًا عبر lib.locale()،
-- ونغلّفه بدالة آمنة ترجّع المفتاح نفسه لو الترجمة ناقصة بدل ما تنهار.

-- ox_lib الموثّق يقرأ اللغة من convar `ox:locale`، وبعض الإصدارات تقبل مفتاحًا صريحًا.
-- نجرّب تجاوز الكونفق أولًا، وإذا ما دعمه الإصدار نرجع للسلوك الافتراضي.
do
    local ok = pcall(lib.locale, Config.Locale)
    if not ok then
        pcall(lib.locale)
    end
end

---الترجمة الآمنة: ترجّع المفتاح نفسه لو الترجمة ناقصة بدل ما تنهار
---@param key string
---@return string
function L(key, ...)
    local ok, value = pcall(locale, key, ...)
    if not ok or value == nil or value == '' then return key end
    return value
end

-- ────────────────────────────────────────────────────────────
-- أدوات عامة
-- ────────────────────────────────────────────────────────────

---تنسيق مبلغ مالي بفواصل الآلاف
---@param amount number
---@return string
function IC.money(amount)
    local n = math.floor(tonumber(amount) or 0)
    local sign = n < 0 and '-' or ''
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    out = out:gsub('^,', '')
    return sign .. out
end

---تقريب لأقرب عدد صحيح آمن
---@param value any
---@param min number|nil
---@param max number|nil
---@return number|nil
function IC.toInt(value, min, max)
    local n = tonumber(value)
    if not n or n ~= n then return nil end          -- nil أو NaN
    n = math.floor(n)
    if min and n < min then return nil end
    if max and n > max then return nil end
    return n
end

---اختيار عنصر عشوائي موزون من قائمة فيها حقل weight
---@param pool table
---@return table|nil
function IC.weightedPick(pool)
    if not pool or #pool == 0 then return nil end
    local total = 0
    for i = 1, #pool do total = total + (pool[i].weight or 1) end
    if total <= 0 then return pool[1] end
    local roll = math.random() * total
    local acc = 0
    for i = 1, #pool do
        acc = acc + (pool[i].weight or 1)
        if roll <= acc then return pool[i] end
    end
    return pool[#pool]
end

---قراءة تعريف الرتبة من الكونفق
---@param grade number
---@return table
function IC.gradeInfo(grade)
    local g = Config.Job.grades[grade]
    if g then return g end
    -- رتبة غير معرّفة: أعطِ أقل صلاحيات
    return Config.Job.grades[0] or {
        label = tostring(grade), canCraft = false, canRegister = false,
        canFreezer = false, canSupply = false, isBoss = false,
    }
end

---أعلى رتبة معرّفة في الكونفق
---@return number
function IC.maxGrade()
    local max = 0
    for grade in pairs(Config.Job.grades) do
        if grade > max then max = grade end
    end
    return max
end

---هل الرتبة تملك صلاحية معينة؟
---@param grade number
---@param permission string
---@return boolean
function IC.can(grade, permission)
    return IC.gradeInfo(grade)[permission] == true
end

---يوسّع مكوّن الوايلدكارد (ic_scoop_any) لقائمة العناصر المقبولة
---@param item string
---@return string[]
function IC.expandItem(item)
    if item == Recipes.ScoopWildcard then
        return Recipes.ScoopItems
    end
    return { item }
end

---الحصول على وصفة موثوقة من معرّف جاء من العميل
---@param recipeId any
---@param stationId any
---@return table|nil
function IC.resolveRecipe(recipeId, stationId)
    if type(recipeId) ~= 'string' then return nil end
    local recipe = Recipes.byId[recipeId]
    if not recipe then return nil end
    -- المحطة المرسلة يجب أن تطابق محطة الوصفة الحقيقية
    if stationId ~= nil and recipe.station ~= stationId then return nil end
    return recipe
end

IC.debug('framework=%s inventory=%s target=%s', IC.framework, IC.inventory, IC.targetSystem)
