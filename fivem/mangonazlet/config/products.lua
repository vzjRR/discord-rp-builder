---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Products & ingredients: the single source of truth.

    Everything downstream is generated from this file:
      • ox_inventory item definitions  (server/installer.lua)
      • qb-core shared item entries    (server/installer.lua)
      • ESX `items` rows               (server/installer.lua)
      • the customer-facing NUI menu   (client/shop.lua)
      • the price list and sell values (server/billing.lua)
      • the supplier catalogue         (client/supply.lua)

    Adding a flavour here makes it appear in-game everywhere, automatically.

    Fields
      name       item name written to the inventory. Always MN.PREFIX-ed.
      label      { en, ar } display name
      desc       { en, ar } description
      weight     grams
      stack      stackable in one slot
      category   'ingredient' | 'scoop' | 'dessert' | 'drink' | 'bakery'
      price      counter price for customers (nil = not sold to walk-ins)
      cost       wholesale unit price from the supplier (ingredients only)
      maxBuy     supplier purchase cap per transaction (ingredients only)
      perishable melts over time (see Config.Melting)
      hunger     ox_inventory hunger restored on use (0-1,000,000)
      thirst     ox_inventory thirst restored on use
      useTime    consume animation length, ms
      consumeAnim 'eating' | 'drinking'
      image      icon filename expected by the inventory
]]

Products = {}

-- ═══════════════════════════════════════════════════════════════
-- Ingredients — bought from the supplier, never sold to customers
-- ═══════════════════════════════════════════════════════════════
Products.ingredients = {
    { name = 'mn_milk',       label = { en = 'Milk',              ar = 'حليب' },        desc = { en = 'Fresh whole milk',            ar = 'حليب طازج كامل الدسم' },   weight = 500, stack = true, category = 'ingredient', cost = 12, maxBuy = 200, image = 'mn_milk.png' },
    { name = 'mn_cream',      label = { en = 'Cream',             ar = 'قشطة' },        desc = { en = 'Heavy cream for churning',    ar = 'قشطة ثقيلة للخفق' },       weight = 400, stack = true, category = 'ingredient', cost = 18, maxBuy = 200, image = 'mn_cream.png' },
    { name = 'mn_sugar',      label = { en = 'Sugar',             ar = 'سكر' },         desc = { en = 'Fine white sugar',            ar = 'سكر أبيض ناعم' },          weight = 300, stack = true, category = 'ingredient', cost = 6,  maxBuy = 300, image = 'mn_sugar.png' },
    { name = 'mn_mango',      label = { en = 'Mango',             ar = 'مانجو' },       desc = { en = 'The house signature fruit',   ar = 'فاكهة المحل المميزة' },    weight = 350, stack = true, category = 'ingredient', cost = 20, maxBuy = 150, image = 'mn_mango.png' },
    { name = 'mn_strawberry', label = { en = 'Strawberries',      ar = 'فراولة' },      desc = { en = 'Ripe strawberries',           ar = 'فراولة ناضجة' },           weight = 200, stack = true, category = 'ingredient', cost = 20, maxBuy = 100, image = 'mn_strawberry.png' },
    { name = 'mn_cocoa',      label = { en = 'Cocoa',             ar = 'كاكاو' },       desc = { en = 'Dark cocoa powder',           ar = 'بودرة كاكاو داكنة' },      weight = 250, stack = true, category = 'ingredient', cost = 22, maxBuy = 100, image = 'mn_cocoa.png' },
    { name = 'mn_vanilla',    label = { en = 'Vanilla',           ar = 'فانيليا' },     desc = { en = 'Vanilla bean extract',        ar = 'خلاصة حبوب الفانيليا' },   weight = 100, stack = true, category = 'ingredient', cost = 25, maxBuy = 100, image = 'mn_vanilla.png' },
    { name = 'mn_pistachio',  label = { en = 'Pistachio',         ar = 'فستق' },        desc = { en = 'Roasted pistachio',           ar = 'فستق محمّص' },             weight = 200, stack = true, category = 'ingredient', cost = 30, maxBuy = 80,  image = 'mn_pistachio.png' },
    { name = 'mn_flour',      label = { en = 'Flour',             ar = 'طحين' },        desc = { en = 'For cones and biscuits',      ar = 'للكونات والبسكويت' },      weight = 400, stack = true, category = 'ingredient', cost = 8,  maxBuy = 200, image = 'mn_flour.png' },
    { name = 'mn_cup',        label = { en = 'Paper Cup',         ar = 'كوب ورقي' },    desc = { en = 'Branded MangoNazlet cup',     ar = 'كوب مانجو نزلة' },         weight = 30,  stack = true, category = 'ingredient', cost = 3,  maxBuy = 400, image = 'mn_cup.png' },
    { name = 'mn_topping',    label = { en = 'Toppings',          ar = 'توبينغ' },      desc = { en = 'Nuts, chips and sprinkles',   ar = 'مكسرات ورقائق وحبيبات' },  weight = 80,  stack = true, category = 'ingredient', cost = 10, maxBuy = 200, image = 'mn_topping.png' },
    { name = 'mn_syrup',      label = { en = 'Mango Syrup',       ar = 'شراب مانجو' },  desc = { en = 'Concentrated mango syrup',    ar = 'شراب مانجو مركّز' },       weight = 150, stack = true, category = 'ingredient', cost = 16, maxBuy = 150, image = 'mn_syrup.png' },
}

-- ═══════════════════════════════════════════════════════════════
-- Scoops — intermediate stock, not sold directly at the counter
-- ═══════════════════════════════════════════════════════════════
Products.scoops = {
    { name = 'mn_scoop_mango',      label = { en = 'Mango Scoop',      ar = 'كرة مانجو' },      desc = { en = 'The one people queue for',   ar = 'اللي يجون عشانها' },      weight = 120, stack = true, category = 'scoop', perishable = true, image = 'mn_scoop_mango.png' },
    { name = 'mn_scoop_vanilla',    label = { en = 'Vanilla Scoop',    ar = 'كرة فانيليا' },    desc = { en = 'Classic and dependable',     ar = 'كلاسيكية ما تخيب' },      weight = 120, stack = true, category = 'scoop', perishable = true, image = 'mn_scoop_vanilla.png' },
    { name = 'mn_scoop_chocolate',  label = { en = 'Chocolate Scoop',  ar = 'كرة شوكولاتة' },   desc = { en = 'Dark cocoa, no shortcuts',   ar = 'كاكاو داكن بلا اختصارات' },weight = 120, stack = true, category = 'scoop', perishable = true, image = 'mn_scoop_chocolate.png' },
    { name = 'mn_scoop_strawberry', label = { en = 'Strawberry Scoop', ar = 'كرة فراولة' },     desc = { en = 'Made with real fruit',       ar = 'بفواكه حقيقية' },         weight = 120, stack = true, category = 'scoop', perishable = true, image = 'mn_scoop_strawberry.png' },
    { name = 'mn_scoop_pistachio',  label = { en = 'Pistachio Scoop',  ar = 'كرة فستق' },       desc = { en = 'House speciality',           ar = 'تخصص المحل' },            weight = 120, stack = true, category = 'scoop', perishable = true, image = 'mn_scoop_pistachio.png' },
}

-- ═══════════════════════════════════════════════════════════════
-- Bakery — shelf-stable bases, also sold cheap at the counter
-- ═══════════════════════════════════════════════════════════════
Products.bakery = {
    { name = 'mn_cone',    label = { en = 'Waffle Cone', ar = 'كون وافل' }, desc = { en = 'Baked fresh each morning', ar = 'يُخبز طازجًا كل صباح' }, weight = 60,  stack = true, category = 'bakery', price = 25, hunger = 40000,  useTime = 2000, consumeAnim = 'eating', image = 'mn_cone.png' },
    { name = 'mn_brownie', label = { en = 'Brownie',     ar = 'براوني' },   desc = { en = 'Fudgy cocoa brownie',      ar = 'براوني كاكاو طري' },     weight = 150, stack = true, category = 'bakery', price = 60, hunger = 120000, useTime = 2500, consumeAnim = 'eating', image = 'mn_brownie.png' },
}

-- ═══════════════════════════════════════════════════════════════
-- Desserts & drinks — the counter menu
-- ═══════════════════════════════════════════════════════════════
Products.desserts = {
    { name = 'mn_cone_single',  label = { en = 'Single Scoop Cone', ar = 'كون كرة واحدة' }, desc = { en = 'One scoop, one cone, no fuss',  ar = 'كرة وكون وبس' },            weight = 200, stack = true, category = 'dessert', price = 110, perishable = true, hunger = 80000,  thirst = 40000,  useTime = 3000, consumeAnim = 'eating', image = 'mn_cone_single.png' },
    { name = 'mn_cone_double',  label = { en = 'Double Scoop Cone', ar = 'كون كرتين' },     desc = { en = 'Two scoops stacked high',       ar = 'كرتين فوق بعض' },           weight = 320, stack = true, category = 'dessert', price = 175, perishable = true, hunger = 140000, thirst = 60000,  useTime = 3500, consumeAnim = 'eating', image = 'mn_cone_double.png' },
    { name = 'mn_mango_cup',    label = { en = 'Mango Cup',         ar = 'كوب مانجو' },     desc = { en = 'Mango scoops, mango syrup',     ar = 'كرات مانجو وشراب مانجو' },  weight = 380, stack = true, category = 'dessert', price = 190, perishable = true, hunger = 150000, thirst = 70000,  useTime = 3500, consumeAnim = 'eating', image = 'mn_mango_cup.png' },
    { name = 'mn_sundae',       label = { en = 'Sundae',            ar = 'صنداي' },         desc = { en = 'Three scoops under toppings',   ar = 'ثلاث كرات تحت التوبينغ' },  weight = 450, stack = true, category = 'dessert', price = 240, perishable = true, hunger = 200000, thirst = 80000,  useTime = 4000, consumeAnim = 'eating', image = 'mn_sundae.png' },
    { name = 'mn_mango_sundae', label = { en = 'Mango Sundae',      ar = 'صنداي مانجو' },   desc = { en = 'The MangoNazlet signature',     ar = 'توقيع مانجو نزلة' },        weight = 480, stack = true, category = 'dessert', price = 290, perishable = true, hunger = 220000, thirst = 90000,  useTime = 4000, consumeAnim = 'eating', image = 'mn_mango_sundae.png' },
    { name = 'mn_sandwich',     label = { en = 'Ice Cream Sandwich',ar = 'ساندويتش مثلجات' },desc = { en = 'A scoop between two brownies',  ar = 'كرة بين قطعتي براوني' },    weight = 350, stack = true, category = 'dessert', price = 210, perishable = true, hunger = 180000,                  useTime = 3500, consumeAnim = 'eating', image = 'mn_sandwich.png' },
    { name = 'mn_family_box',   label = { en = 'Family Box',        ar = 'بوكس عائلي' },    desc = { en = 'Six scoops packed to travel',   ar = 'ست كرات معبّأة للطريق' },   weight = 900, stack = true, category = 'dessert', price = 520, perishable = true, hunger = 300000, thirst = 120000, useTime = 5000, consumeAnim = 'eating', image = 'mn_family_box.png' },
}

Products.drinks = {
    { name = 'mn_shake_mango',      label = { en = 'Mango Milkshake',      ar = 'ميلك شيك مانجو' },  desc = { en = 'Thick, cold, unmistakable', ar = 'كثيف وبارد ومميز' },   weight = 500, stack = true, category = 'drink', price = 175, perishable = true, thirst = 220000, hunger = 50000, useTime = 3000, consumeAnim = 'drinking', image = 'mn_shake_mango.png' },
    { name = 'mn_shake_vanilla',    label = { en = 'Vanilla Milkshake',    ar = 'ميلك شيك فانيليا' },desc = { en = 'Simple done properly',      ar = 'البساطة بإتقان' },      weight = 500, stack = true, category = 'drink', price = 140, perishable = true, thirst = 200000, hunger = 50000, useTime = 3000, consumeAnim = 'drinking', image = 'mn_shake_vanilla.png' },
    { name = 'mn_shake_chocolate',  label = { en = 'Chocolate Milkshake',  ar = 'ميلك شيك شوكولاتة' },desc={ en = 'For the cocoa devoted',      ar = 'لعشّاق الكاكاو' },       weight = 500, stack = true, category = 'drink', price = 150, perishable = true, thirst = 200000, hunger = 50000, useTime = 3000, consumeAnim = 'drinking', image = 'mn_shake_chocolate.png' },
    { name = 'mn_shake_strawberry', label = { en = 'Strawberry Milkshake', ar = 'ميلك شيك فراولة' }, desc = { en = 'Pink and honest',           ar = 'وردي وصادق' },          weight = 500, stack = true, category = 'drink', price = 160, perishable = true, thirst = 210000, hunger = 40000, useTime = 3000, consumeAnim = 'drinking', image = 'mn_shake_strawberry.png' },
}

-- ═══════════════════════════════════════════════════════════════
-- Derived indexes — built once at load, O(1) lookups everywhere
-- ═══════════════════════════════════════════════════════════════

---@type table<string, table> every item this resource owns, by name
Products.byName = {}
---@type table[] flat ordered list
Products.all = {}
---@type string[] scoop item names, used by the "any scoop" wildcard
Products.scoopNames = {}
---@type table<string, boolean>
Products.isScoop = {}

do
    local groups = {
        Products.ingredients, Products.scoops, Products.bakery,
        Products.desserts, Products.drinks,
    }

    for _, group in ipairs(groups) do
        for i = 1, #group do
            local product = group[i]
            if Products.byName[product.name] then
                print(('[MangoNazlet] ^1duplicate product name "%s"^7'):format(product.name))
            end
            Products.byName[product.name] = product
            Products.all[#Products.all + 1] = product
        end
    end

    for i = 1, #Products.scoops do
        local name = Products.scoops[i].name
        Products.scoopNames[#Products.scoopNames + 1] = name
        Products.isScoop[name] = true
    end
end

-- The wildcard ingredient token: a recipe asking for this accepts any scoop.
Products.SCOOP_ANY = 'mn_scoop_any'

---@param name string
---@return table|nil
function Products.get(name) return Products.byName[name] end

---Localised label, falling back to the item name.
---@param name string
---@param lang? string
---@return string
function Products.label(name, lang)
    local product = Products.byName[name]
    if not product then
        return name == Products.SCOOP_ANY and T('craft_ingredients') or name
    end
    lang = lang or (Config and Config.Locale) or 'en'
    return product.label[lang] or product.label.en or name
end

---Counter price, 0 when the item is not sold to walk-in customers.
---@param name string
---@return number
function Products.price(name)
    local product = Products.byName[name]
    return product and product.price or 0
end

---@param name string
---@return boolean
function Products.perishable(name)
    local product = Products.byName[name]
    return product ~= nil and product.perishable == true
end

---Items offered on the customer menu, in display order.
---@return table[]
function Products.menu()
    local out = {}
    for i = 1, #Products.all do
        local product = Products.all[i]
        if product.price and product.price > 0 then out[#out + 1] = product end
    end
    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.price < b.price
    end)
    return out
end

---Supplier catalogue, in display order.
---@return table[]
function Products.catalogue()
    local out = {}
    for i = 1, #Products.ingredients do out[i] = Products.ingredients[i] end
    table.sort(out, function(a, b) return a.cost < b.cost end)
    return out
end
