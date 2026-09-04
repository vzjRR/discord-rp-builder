---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — الوصفات وقائمة الأسعار
    -------------------------------------------
    كل محطة (station) لها قائمة وصفات. المفتاح الأعلى = station.id في locations.lua

    شكل الوصفة:
      id            معرّف فريد على مستوى المورد كله (يُستخدم في التحقق السيرفري)
      label         الاسم المعروض
      description   وصف اختياري
      result        { item = 'اسم العنصر', count = العدد الناتج }
      ingredients   قائمة { item = '...', count = n }  — تُخصم من حقيبة اللاعب
      time          مدة التصنيع بالملي ثانية (قبل تطبيق Config.Crafting.timeMultiplier)
      grade         أقل رتبة مطلوبة
      difficulty    1..5 — يحدد صعوبة اختبار المهارة
      anim          { dict = '...', clip = '...' } أنيميشن التصنيع
      icon          أيقونة Font Awesome في القائمة
      sellPrice     سعر بيع القطعة للزبون (يُستخدم في الطلبات والفوترة والعربة)
      perishable    هل المنتج يذوب؟ (يخضع لـ Config.Melting)
]]

Recipes = {}

-- ────────────────────────────────────────────────────────────
-- ماكينة السوفت سيرف — الكرات الأساسية
-- ────────────────────────────────────────────────────────────
Recipes.softserve = {
    {
        id = 'scoop_vanilla',
        label = 'كرة فانيليا',
        description = 'الكلاسيكية اللي ما تخيب',
        result = { item = 'ic_scoop_vanilla', count = 2 },
        ingredients = {
            { item = 'ic_milk', count = 1 },
            { item = 'ic_cream', count = 1 },
            { item = 'ic_sugar', count = 1 },
            { item = 'ic_vanilla', count = 1 },
        },
        time = 6000,
        grade = 0,
        difficulty = 1,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 45,
        perishable = true,
    },
    {
        id = 'scoop_chocolate',
        label = 'كرة شوكولاتة',
        description = 'كاكاو داكن',
        result = { item = 'ic_scoop_chocolate', count = 2 },
        ingredients = {
            { item = 'ic_milk', count = 1 },
            { item = 'ic_cream', count = 1 },
            { item = 'ic_sugar', count = 1 },
            { item = 'ic_cocoa', count = 1 },
        },
        time = 6000,
        grade = 0,
        difficulty = 1,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 50,
        perishable = true,
    },
    {
        id = 'scoop_strawberry',
        label = 'كرة فراولة',
        description = 'فراولة طازجة',
        result = { item = 'ic_scoop_strawberry', count = 2 },
        ingredients = {
            { item = 'ic_milk', count = 1 },
            { item = 'ic_cream', count = 1 },
            { item = 'ic_sugar', count = 1 },
            { item = 'ic_strawberry', count = 1 },
        },
        time = 6500,
        grade = 0,
        difficulty = 2,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 55,
        perishable = true,
    },
    {
        id = 'scoop_mango',
        label = 'كرة مانجو',
        description = 'سوربيه مانجو منعش',
        result = { item = 'ic_scoop_mango', count = 2 },
        ingredients = {
            { item = 'ic_cream', count = 1 },
            { item = 'ic_sugar', count = 1 },
            { item = 'ic_mango', count = 2 },
        },
        time = 7000,
        grade = 1,
        difficulty = 2,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 60,
        perishable = true,
    },
    {
        id = 'scoop_pistachio',
        label = 'كرة فستق',
        description = 'فستق حلبي — التوقيع الخاص بالمحل',
        result = { item = 'ic_scoop_pistachio', count = 2 },
        ingredients = {
            { item = 'ic_milk', count = 1 },
            { item = 'ic_cream', count = 2 },
            { item = 'ic_sugar', count = 1 },
            { item = 'ic_pistachio', count = 2 },
        },
        time = 9000,
        grade = 2,
        difficulty = 4,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 95,
        perishable = true,
    },
}

-- ────────────────────────────────────────────────────────────
-- طاولة التحضير — المنتجات النهائية
-- ────────────────────────────────────────────────────────────
Recipes.prep = {
    {
        id = 'cone_single',
        label = 'كون كرة واحدة',
        description = 'كون وافل + كرة على اختيارك',
        result = { item = 'ic_cone_single', count = 1 },
        ingredients = {
            { item = 'ic_waffle_cone', count = 1 },
            { item = 'ic_scoop_any', count = 1 },
        },
        time = 3500,
        grade = 0,
        difficulty = 1,
        anim = { dict = 'amb@prop_human_parking_meter@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 110,
        perishable = true,
    },
    {
        id = 'cone_double',
        label = 'كون كرتين',
        description = 'كرتين فوق بعض — يحتاج يد ثابتة',
        result = { item = 'ic_cone_double', count = 1 },
        ingredients = {
            { item = 'ic_waffle_cone', count = 1 },
            { item = 'ic_scoop_any', count = 2 },
        },
        time = 5000,
        grade = 1,
        difficulty = 3,
        anim = { dict = 'amb@prop_human_parking_meter@male@base', clip = 'base' },
        icon = 'ice-cream',
        sellPrice = 175,
        perishable = true,
    },
    {
        id = 'sundae',
        label = 'صنداي',
        description = 'كوب + ثلاث كرات + توبينغ',
        result = { item = 'ic_sundae', count = 1 },
        ingredients = {
            { item = 'ic_cup', count = 1 },
            { item = 'ic_scoop_any', count = 3 },
            { item = 'ic_topping', count = 1 },
        },
        time = 7000,
        grade = 1,
        difficulty = 3,
        anim = { dict = 'amb@prop_human_parking_meter@male@base', clip = 'base' },
        icon = 'bowl-food',
        sellPrice = 240,
        perishable = true,
    },
    {
        id = 'banana_split',
        label = 'بنانا سبليت',
        description = 'الطبق الأشهر — ثلاث نكهات وموز',
        result = { item = 'ic_banana_split', count = 1 },
        ingredients = {
            { item = 'ic_cup', count = 1 },
            { item = 'ic_scoop_any', count = 3 },
            { item = 'ic_topping', count = 2 },
            { item = 'ic_cream', count = 1 },
        },
        time = 9000,
        grade = 2,
        difficulty = 4,
        anim = { dict = 'amb@prop_human_parking_meter@male@base', clip = 'base' },
        icon = 'bowl-food',
        sellPrice = 320,
        perishable = true,
    },
    {
        id = 'ice_sandwich',
        label = 'ساندويتش مثلجات',
        description = 'براوني + كرة في النص',
        result = { item = 'ic_sandwich', count = 1 },
        ingredients = {
            { item = 'ic_brownie', count = 2 },
            { item = 'ic_scoop_any', count = 1 },
        },
        time = 5500,
        grade = 2,
        difficulty = 3,
        anim = { dict = 'amb@prop_human_parking_meter@male@base', clip = 'base' },
        icon = 'cookie',
        sellPrice = 210,
        perishable = true,
    },
}

-- ────────────────────────────────────────────────────────────
-- الخلاط — المشروبات
-- ────────────────────────────────────────────────────────────
Recipes.blender = {
    {
        id = 'milkshake_vanilla',
        label = 'ميلك شيك فانيليا',
        result = { item = 'ic_shake_vanilla', count = 1 },
        ingredients = {
            { item = 'ic_cup', count = 1 },
            { item = 'ic_milk', count = 2 },
            { item = 'ic_scoop_vanilla', count = 1 },
        },
        time = 5000,
        grade = 0,
        difficulty = 1,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'blender',
        sellPrice = 140,
        perishable = true,
    },
    {
        id = 'milkshake_chocolate',
        label = 'ميلك شيك شوكولاتة',
        result = { item = 'ic_shake_chocolate', count = 1 },
        ingredients = {
            { item = 'ic_cup', count = 1 },
            { item = 'ic_milk', count = 2 },
            { item = 'ic_scoop_chocolate', count = 1 },
        },
        time = 5000,
        grade = 0,
        difficulty = 1,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'blender',
        sellPrice = 150,
        perishable = true,
    },
    {
        id = 'smoothie_mango',
        label = 'سموذي مانجو',
        result = { item = 'ic_smoothie_mango', count = 1 },
        ingredients = {
            { item = 'ic_cup', count = 1 },
            { item = 'ic_mango', count = 2 },
            { item = 'ic_sugar', count = 1 },
        },
        time = 5500,
        grade = 1,
        difficulty = 2,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'blender',
        sellPrice = 165,
        perishable = true,
    },
    {
        id = 'smoothie_strawberry',
        label = 'سموذي فراولة',
        result = { item = 'ic_smoothie_strawberry', count = 1 },
        ingredients = {
            { item = 'ic_cup', count = 1 },
            { item = 'ic_strawberry', count = 2 },
            { item = 'ic_milk', count = 1 },
        },
        time = 5500,
        grade = 1,
        difficulty = 2,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'blender',
        sellPrice = 160,
        perishable = true,
    },
}

-- ────────────────────────────────────────────────────────────
-- الفرن — الأساسيات المخبوزة (غير قابلة للذوبان)
-- ────────────────────────────────────────────────────────────
Recipes.oven = {
    {
        id = 'waffle_cone',
        label = 'كون وافل',
        description = 'أساس كل كون — اخبز دفعة قبل الزحمة',
        result = { item = 'ic_waffle_cone', count = 4 },
        ingredients = {
            { item = 'ic_flour', count = 2 },
            { item = 'ic_sugar', count = 1 },
            { item = 'ic_milk', count = 1 },
        },
        time = 8000,
        grade = 0,
        difficulty = 2,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'fire-burner',
        sellPrice = 25,
        perishable = false,
    },
    {
        id = 'brownie',
        label = 'براوني',
        result = { item = 'ic_brownie', count = 4 },
        ingredients = {
            { item = 'ic_flour', count = 2 },
            { item = 'ic_cocoa', count = 1 },
            { item = 'ic_sugar', count = 2 },
        },
        time = 9000,
        grade = 1,
        difficulty = 2,
        anim = { dict = 'amb@prop_human_bbq@male@base', clip = 'base' },
        icon = 'cookie',
        sellPrice = 60,
        perishable = false,
    },
}

-- ────────────────────────────────────────────────────────────
-- «أي كرة» — المكوّن الشبح
-- الوصفات اللي تطلب ic_scoop_any تقبل أي عنصر من هذه القائمة.
-- ────────────────────────────────────────────────────────────
Recipes.ScoopWildcard = 'ic_scoop_any'
Recipes.ScoopItems = {
    'ic_scoop_vanilla',
    'ic_scoop_chocolate',
    'ic_scoop_strawberry',
    'ic_scoop_mango',
    'ic_scoop_pistachio',
}

-- ────────────────────────────────────────────────────────────
-- ما الذي يطلبه زبائن NPC؟ (المنتجات النهائية فقط)
-- weight = وزن الاحتمالية
-- ────────────────────────────────────────────────────────────
Recipes.OrderPool = {
    { item = 'ic_cone_single',        weight = 10, maxCount = 2 },
    { item = 'ic_cone_double',        weight = 7,  maxCount = 2 },
    { item = 'ic_sundae',             weight = 6,  maxCount = 1 },
    { item = 'ic_shake_vanilla',      weight = 6,  maxCount = 2 },
    { item = 'ic_shake_chocolate',    weight = 6,  maxCount = 2 },
    { item = 'ic_smoothie_mango',     weight = 4,  maxCount = 1 },
    { item = 'ic_smoothie_strawberry',weight = 4,  maxCount = 1 },
    { item = 'ic_sandwich',           weight = 3,  maxCount = 1 },
    { item = 'ic_banana_split',       weight = 2,  maxCount = 1 },
}

-- ────────────────────────────────────────────────────────────
-- فهارس محسوبة مسبقًا — تُبنى مرة واحدة عند تحميل المورد
-- تُستخدم في التحقق السيرفري (O(1) بدل البحث الخطي)
-- ────────────────────────────────────────────────────────────

---@type table<string, table> recipeId -> recipe (مع stationId مضاف)
Recipes.byId = {}
---@type table<string, table> itemName -> recipe التي تنتجه
Recipes.byResult = {}
---@type table<string, boolean>
Recipes.isScoop = {}

do
    for _, name in ipairs(Recipes.ScoopItems) do
        Recipes.isScoop[name] = true
    end

    for stationId, list in pairs(Recipes) do
        -- تجاهل الحقول اللي مو قوائم وصفات
        if type(list) == 'table' and stationId ~= 'byId' and stationId ~= 'byResult'
            and stationId ~= 'isScoop' and stationId ~= 'ScoopItems'
            and stationId ~= 'OrderPool' and type(list[1]) == 'table' and list[1].id then
            for i = 1, #list do
                local recipe = list[i]
                recipe.station = stationId
                if Recipes.byId[recipe.id] then
                    print(('[enclave_icecream] ^1تحذير: معرّف وصفة مكرر "%s"^7'):format(recipe.id))
                end
                Recipes.byId[recipe.id] = recipe
                Recipes.byResult[recipe.result.item] = recipe
            end
        end
    end
end

---سعر بيع عنصر (من الوصفة التي تنتجه)
---@param item string
---@return number
function Recipes.getSellPrice(item)
    local recipe = Recipes.byResult[item]
    return recipe and recipe.sellPrice or 0
end

---هل العنصر قابل للذوبان؟
---@param item string
---@return boolean
function Recipes.isPerishable(item)
    local recipe = Recipes.byResult[item]
    return recipe ~= nil and recipe.perishable == true
end

---يرجّع وصفات محطة معينة
---@param stationId string
---@return table
function Recipes.forStation(stationId)
    local list = Recipes[stationId]
    if type(list) == 'table' and type(list[1]) == 'table' and list[1].id then
        return list
    end
    return {}
end
