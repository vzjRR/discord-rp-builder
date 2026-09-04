--[[
    enclave_icecream — تعريفات العناصر
    -----------------------------------
    ⚠️ هذا الملف مرجعي فقط — المورد لا يحمّله (مو مذكور في fxmanifest.lua).
       انسخ محتواه إلى ملف العناصر عند فريمويركك:

       • ox_inventory  →  ox_inventory/data/items.lua   (انسخ القسم الأول)
       • qb-core       →  qb-core/shared/items.lua      (انسخ القسم الثاني)
       • ESX           →  نفّذ استعلام SQL في القسم الثالث

    الصور: ضع أيقونات PNG بنفس اسم العنصر في
           ox_inventory/web/images/  →  مثال: ic_scoop_vanilla.png
           لو ما وضعت صورًا، تظهر أيقونة افتراضية — المورد يشتغل عادي.
]]

-- ════════════════════════════════════════════════════════════
-- 1) ox_inventory  →  ox_inventory/data/items.lua
-- ════════════════════════════════════════════════════════════
--[[

    -- ── المواد الخام ───────────────────────────────────────
    ['ic_milk'] = {
        label = 'حليب', weight = 500, stack = true, close = false,
        description = 'كرتون حليب طازج',
    },
    ['ic_cream'] = {
        label = 'قشطة', weight = 400, stack = true, close = false,
        description = 'قشطة ثقيلة للمثلجات',
    },
    ['ic_sugar'] = {
        label = 'سكر', weight = 300, stack = true, close = false,
    },
    ['ic_cocoa'] = {
        label = 'كاكاو', weight = 250, stack = true, close = false,
    },
    ['ic_vanilla'] = {
        label = 'فانيليا', weight = 100, stack = true, close = false,
    },
    ['ic_strawberry'] = {
        label = 'فراولة', weight = 200, stack = true, close = false,
    },
    ['ic_mango'] = {
        label = 'مانجو', weight = 350, stack = true, close = false,
    },
    ['ic_pistachio'] = {
        label = 'فستق', weight = 200, stack = true, close = false,
    },
    ['ic_flour'] = {
        label = 'طحين', weight = 400, stack = true, close = false,
    },
    ['ic_cup'] = {
        label = 'كوب ورقي', weight = 30, stack = true, close = false,
    },
    ['ic_topping'] = {
        label = 'توبينغ', weight = 80, stack = true, close = false,
        description = 'مكسرات وشوكولاتة وحبيبات ملونة',
    },

    -- ── نصف مصنّع ─────────────────────────────────────────
    ['ic_waffle_cone'] = {
        label = 'كون وافل', weight = 60, stack = true, close = false,
    },
    ['ic_brownie'] = {
        label = 'براوني', weight = 150, stack = true, close = true,
        client = { status = { hunger = 60000 }, anim = 'eating', prop = 'burger',
                   usetime = 2500, notification = 'أكلت براوني' },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },

    -- ── الكرات (تذوب: degrade يطابق Config.Melting.ruinMinutes) ─
    ['ic_scoop_vanilla'] = {
        label = 'كرة فانيليا', weight = 120, stack = true, close = false,
        degrade = 45, decay = true,
    },
    ['ic_scoop_chocolate'] = {
        label = 'كرة شوكولاتة', weight = 120, stack = true, close = false,
        degrade = 45, decay = true,
    },
    ['ic_scoop_strawberry'] = {
        label = 'كرة فراولة', weight = 120, stack = true, close = false,
        degrade = 45, decay = true,
    },
    ['ic_scoop_mango'] = {
        label = 'كرة مانجو', weight = 120, stack = true, close = false,
        degrade = 45, decay = true,
    },
    ['ic_scoop_pistachio'] = {
        label = 'كرة فستق', weight = 120, stack = true, close = false,
        degrade = 45, decay = true,
    },

    -- ── المنتجات النهائية ─────────────────────────────────
    ['ic_cone_single'] = {
        label = 'كون كرة واحدة', weight = 200, stack = true, close = true,
        degrade = 45, decay = true,
        client = { status = { hunger = 80000, thirst = 40000 }, anim = 'eating',
                   prop = 'burger', usetime = 3000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_cone_double'] = {
        label = 'كون كرتين', weight = 320, stack = true, close = true,
        degrade = 45, decay = true,
        client = { status = { hunger = 140000, thirst = 60000 }, anim = 'eating',
                   prop = 'burger', usetime = 3500 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_sundae'] = {
        label = 'صنداي', weight = 450, stack = true, close = true,
        degrade = 40, decay = true,
        client = { status = { hunger = 200000, thirst = 80000 }, anim = 'eating',
                   prop = 'burger', usetime = 4000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_banana_split'] = {
        label = 'بنانا سبليت', weight = 600, stack = true, close = true,
        degrade = 35, decay = true,
        client = { status = { hunger = 280000, thirst = 100000 }, anim = 'eating',
                   prop = 'burger', usetime = 5000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_sandwich'] = {
        label = 'ساندويتش مثلجات', weight = 350, stack = true, close = true,
        degrade = 45, decay = true,
        client = { status = { hunger = 180000 }, anim = 'eating',
                   prop = 'burger', usetime = 3500 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },

    -- ── المشروبات ─────────────────────────────────────────
    ['ic_shake_vanilla'] = {
        label = 'ميلك شيك فانيليا', weight = 500, stack = true, close = true,
        degrade = 50, decay = true,
        client = { status = { thirst = 200000, hunger = 50000 }, anim = 'drinking',
                   prop = 'cup', usetime = 3000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_shake_chocolate'] = {
        label = 'ميلك شيك شوكولاتة', weight = 500, stack = true, close = true,
        degrade = 50, decay = true,
        client = { status = { thirst = 200000, hunger = 50000 }, anim = 'drinking',
                   prop = 'cup', usetime = 3000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_smoothie_mango'] = {
        label = 'سموذي مانجو', weight = 500, stack = true, close = true,
        degrade = 50, decay = true,
        client = { status = { thirst = 220000, hunger = 30000 }, anim = 'drinking',
                   prop = 'cup', usetime = 3000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },
    ['ic_smoothie_strawberry'] = {
        label = 'سموذي فراولة', weight = 500, stack = true, close = true,
        degrade = 50, decay = true,
        client = { status = { thirst = 220000, hunger = 30000 }, anim = 'drinking',
                   prop = 'cup', usetime = 3000 },
        server = { export = 'enclave_icecream.consume' },
        consume = 1,
    },

]]

-- ════════════════════════════════════════════════════════════
-- 2) qb-core  →  qb-core/shared/items.lua
-- ════════════════════════════════════════════════════════════
--[[

    ['ic_milk']               = { name = 'ic_milk',               label = 'حليب',              weight = 500, type = 'item', image = 'ic_milk.png',               unique = false, useable = false, shouldClose = false, combinable = nil, description = 'كرتون حليب طازج' },
    ['ic_cream']              = { name = 'ic_cream',              label = 'قشطة',              weight = 400, type = 'item', image = 'ic_cream.png',              unique = false, useable = false, shouldClose = false, combinable = nil, description = 'قشطة ثقيلة' },
    ['ic_sugar']              = { name = 'ic_sugar',              label = 'سكر',               weight = 300, type = 'item', image = 'ic_sugar.png',              unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_cocoa']              = { name = 'ic_cocoa',              label = 'كاكاو',             weight = 250, type = 'item', image = 'ic_cocoa.png',              unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_vanilla']            = { name = 'ic_vanilla',            label = 'فانيليا',            weight = 100, type = 'item', image = 'ic_vanilla.png',            unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_strawberry']         = { name = 'ic_strawberry',         label = 'فراولة',            weight = 200, type = 'item', image = 'ic_strawberry.png',         unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_mango']              = { name = 'ic_mango',              label = 'مانجو',             weight = 350, type = 'item', image = 'ic_mango.png',              unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_pistachio']          = { name = 'ic_pistachio',          label = 'فستق',              weight = 200, type = 'item', image = 'ic_pistachio.png',          unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_flour']              = { name = 'ic_flour',              label = 'طحين',              weight = 400, type = 'item', image = 'ic_flour.png',              unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_cup']                = { name = 'ic_cup',                label = 'كوب ورقي',          weight = 30,  type = 'item', image = 'ic_cup.png',                unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_topping']            = { name = 'ic_topping',            label = 'توبينغ',            weight = 80,  type = 'item', image = 'ic_topping.png',            unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_waffle_cone']        = { name = 'ic_waffle_cone',        label = 'كون وافل',          weight = 60,  type = 'item', image = 'ic_waffle_cone.png',        unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_brownie']            = { name = 'ic_brownie',            label = 'براوني',            weight = 150, type = 'item', image = 'ic_brownie.png',            unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_scoop_vanilla']      = { name = 'ic_scoop_vanilla',      label = 'كرة فانيليا',        weight = 120, type = 'item', image = 'ic_scoop_vanilla.png',      unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_scoop_chocolate']    = { name = 'ic_scoop_chocolate',    label = 'كرة شوكولاتة',       weight = 120, type = 'item', image = 'ic_scoop_chocolate.png',    unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_scoop_strawberry']   = { name = 'ic_scoop_strawberry',   label = 'كرة فراولة',         weight = 120, type = 'item', image = 'ic_scoop_strawberry.png',   unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_scoop_mango']        = { name = 'ic_scoop_mango',        label = 'كرة مانجو',          weight = 120, type = 'item', image = 'ic_scoop_mango.png',        unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_scoop_pistachio']    = { name = 'ic_scoop_pistachio',    label = 'كرة فستق',           weight = 120, type = 'item', image = 'ic_scoop_pistachio.png',    unique = false, useable = false, shouldClose = false, combinable = nil, description = '' },
    ['ic_cone_single']        = { name = 'ic_cone_single',        label = 'كون كرة واحدة',      weight = 200, type = 'item', image = 'ic_cone_single.png',        unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_cone_double']        = { name = 'ic_cone_double',        label = 'كون كرتين',          weight = 320, type = 'item', image = 'ic_cone_double.png',        unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_sundae']             = { name = 'ic_sundae',             label = 'صنداي',              weight = 450, type = 'item', image = 'ic_sundae.png',             unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_banana_split']       = { name = 'ic_banana_split',       label = 'بنانا سبليت',         weight = 600, type = 'item', image = 'ic_banana_split.png',       unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_sandwich']           = { name = 'ic_sandwich',           label = 'ساندويتش مثلجات',    weight = 350, type = 'item', image = 'ic_sandwich.png',           unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_shake_vanilla']      = { name = 'ic_shake_vanilla',      label = 'ميلك شيك فانيليا',    weight = 500, type = 'item', image = 'ic_shake_vanilla.png',      unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_shake_chocolate']    = { name = 'ic_shake_chocolate',    label = 'ميلك شيك شوكولاتة',   weight = 500, type = 'item', image = 'ic_shake_chocolate.png',    unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_smoothie_mango']     = { name = 'ic_smoothie_mango',     label = 'سموذي مانجو',         weight = 500, type = 'item', image = 'ic_smoothie_mango.png',     unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },
    ['ic_smoothie_strawberry']= { name = 'ic_smoothie_strawberry',label = 'سموذي فراولة',        weight = 500, type = 'item', image = 'ic_smoothie_strawberry.png',unique = false, useable = true,  shouldClose = true,  combinable = nil, description = '' },

]]

-- ════════════════════════════════════════════════════════════
-- 3) ESX (جدول items في قاعدة البيانات)
-- ════════════════════════════════════════════════════════════
--[[

INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('ic_milk','حليب',1,0,1), ('ic_cream','قشطة',1,0,1), ('ic_sugar','سكر',1,0,1),
    ('ic_cocoa','كاكاو',1,0,1), ('ic_vanilla','فانيليا',1,0,1), ('ic_strawberry','فراولة',1,0,1),
    ('ic_mango','مانجو',1,0,1), ('ic_pistachio','فستق',1,0,1), ('ic_flour','طحين',1,0,1),
    ('ic_cup','كوب ورقي',1,0,1), ('ic_topping','توبينغ',1,0,1), ('ic_waffle_cone','كون وافل',1,0,1),
    ('ic_brownie','براوني',1,0,1), ('ic_scoop_vanilla','كرة فانيليا',1,0,1),
    ('ic_scoop_chocolate','كرة شوكولاتة',1,0,1), ('ic_scoop_strawberry','كرة فراولة',1,0,1),
    ('ic_scoop_mango','كرة مانجو',1,0,1), ('ic_scoop_pistachio','كرة فستق',1,0,1),
    ('ic_cone_single','كون كرة واحدة',1,0,1), ('ic_cone_double','كون كرتين',1,0,1),
    ('ic_sundae','صنداي',1,0,1), ('ic_banana_split','بنانا سبليت',1,0,1),
    ('ic_sandwich','ساندويتش مثلجات',1,0,1), ('ic_shake_vanilla','ميلك شيك فانيليا',1,0,1),
    ('ic_shake_chocolate','ميلك شيك شوكولاتة',1,0,1), ('ic_smoothie_mango','سموذي مانجو',1,0,1),
    ('ic_smoothie_strawberry','سموذي فراولة',1,0,1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

]]

-- ════════════════════════════════════════════════════════════
-- 4) الوظيفة — أضفها لملف الوظائف عند فريمويركك
-- ════════════════════════════════════════════════════════════
--[[

-- qbx_core → qbx_core/shared/jobs.lua   |   qb-core → qb-core/shared/jobs.lua
['icecream'] = {
    label = 'محل المثلجات',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        [0] = { name = 'متدرب',       payment = 250  },
        [1] = { name = 'موزّع',        payment = 400  },
        [2] = { name = 'صانع مثلجات',  payment = 600  },
        [3] = { name = 'مساعد مدير',   payment = 850  },
        [4] = { name = 'المالك', isboss = true, bankAuth = true, payment = 1200 },
    },
},

-- ESX → جدول jobs و job_grades:
INSERT INTO `jobs` (`name`, `label`) VALUES ('icecream','محل المثلجات')
    ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
    ('icecream',0,'trainee','متدرب',250,'{}','{}'),
    ('icecream',1,'server','موزّع',400,'{}','{}'),
    ('icecream',2,'maker','صانع مثلجات',600,'{}','{}'),
    ('icecream',3,'assistant','مساعد مدير',850,'{}','{}'),
    ('icecream',4,'boss','المالك',1200,'{}','{}')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

]]
