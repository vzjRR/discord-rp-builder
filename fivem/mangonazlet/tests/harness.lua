--[[
    MangoNazlet — offline test harness.

    Loads the real config and re-uses the real algorithm bodies, extracted from
    the resource files, so these tests exercise shipping code rather than a
    copy of it. Run with:  lua5.4 tests/harness.lua
]]

-- ── FiveM stubs ────────────────────────────────────────────────
function vec3(x, y, z) return { x = x, y = y, z = z } end
function vec4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
function GetCurrentResourceName() return 'mangonazlet' end
function GetResourceState() return 'started' end
function GetGameTimer() return math.floor(os.clock() * 1000) end
GlobalState = {}

-- ── Load the resource's shared layer in manifest order ─────────
dofile('shared/constants.lua')
dofile('locales/en.lua')
dofile('locales/ar.lua')
dofile('config/config.lua')
dofile('config/permissions.lua')
dofile('config/products.lua')
dofile('config/recipes.lua')
dofile('config/locations.lua')
dofile('shared/locale.lua')
dofile('shared/utils.lua')

-- ── Extract real function bodies from the server files ─────────
local function extract(path, pattern)
    local source = assert(io.open(path)):read('a')
    local body = source:match(pattern)
    assert(body, 'could not extract from ' .. path)
    local chunk = assert(load(body, path))
    chunk()
end

-- A fake inventory the extracted functions operate on.
local INV = {}
function MN.itemCount(_, item) return INV[item] or 0 end
function MN.removeItem(_, item, count)
    if (INV[item] or 0) < count then return false end
    INV[item] = INV[item] - count
    return true
end

MN.crafting = MN.crafting or {}
extract('server/inventory.lua', '(function MN%.crafting%.check.-\nend)\n')
extract('server/inventory.lua', '(function MN%.crafting%.consume.-\n    return true\nend)\n')
extract('server/inventory.lua', '(function MN%.crafting%.freshness.-\n    return math%.max.-\nend)\n')

-- ── Tiny assertion helpers ─────────────────────────────────────
local pass, fail = 0, 0
local section = ''

local function group(name) section = name; print('\n── ' .. name) end
local function check(name, condition)
    if condition then
        pass = pass + 1
        print('  PASS  ' .. name)
    else
        fail = fail + 1
        print('  FAIL  ' .. name)
    end
end

-- ═══════════════════════════════════════════════════════════════
group('configuration integrity')
-- ═══════════════════════════════════════════════════════════════

check('economy split totals 1.0',
    math.abs(Config.Economy.businessShare + Config.Economy.employeeTip - 1.0) < 0.001)

check('every station has recipes', (function()
    for _, station in ipairs(Locations.shop.stations) do
        if #Recipes.forStation(station.id) == 0 then return false end
    end
    return true
end)())

check('every recipe targets a real station', (function()
    for _, recipe in pairs(Recipes.byId) do
        if not Locations.station(recipe.station) then return false end
    end
    return true
end)())

check('every recipe ingredient is a real product', (function()
    for _, recipe in pairs(Recipes.byId) do
        for _, ingredient in ipairs(recipe.ingredients) do
            if ingredient.item ~= Products.SCOOP_ANY and not Products.get(ingredient.item) then
                return false
            end
        end
    end
    return true
end)())

check('every recipe output is a real product', (function()
    for _, recipe in pairs(Recipes.byId) do
        if not Products.get(recipe.result.item) then return false end
    end
    return true
end)())

check('every menu item can be made', (function()
    for _, product in ipairs(Products.menu()) do
        if not Recipes.byResult[product.name] then return false end
    end
    return true
end)())

check('every ticket item can be made', (function()
    for _, entry in ipairs(Recipes.ticketPool) do
        if not Recipes.byResult[entry.item] then return false end
    end
    return true
end)())

check('every recipe grade exists', (function()
    for _, recipe in pairs(Recipes.byId) do
        if not Permissions.grades[recipe.grade or 0] then return false end
    end
    return true
end)())

check('supply run has enough pickup points',
    #Locations.pickups >= Config.Supply.run.pickups)

check('all product names use the mn_ prefix', (function()
    for _, product in ipairs(Products.all) do
        if product.name:sub(1, 3) ~= MN.PREFIX then return false end
    end
    return true
end)())

check('no duplicate product names',
    MN.count(Products.byName) == #Products.all)

check('ingredients are never sold at the counter', (function()
    for _, product in ipairs(Products.ingredients) do
        if product.price then return false end
    end
    return true
end)())

check('every sellable product has a positive price', (function()
    for _, product in ipairs(Products.menu()) do
        if not product.price or product.price <= 0 then return false end
    end
    return true
end)())

check('ingredient cost is below the value it creates', (function()
    -- A recipe must never cost more in ingredients than its output sells for,
    -- or the business loses money on every sale it makes.
    for id, recipe in pairs(Recipes.byId) do
        local price = Products.price(recipe.result.item) * recipe.result.count
        if price > 0 then
            local cost = 0
            for _, ingredient in ipairs(recipe.ingredients) do
                local product = Products.get(ingredient.item)
                if product and product.cost then
                    cost = cost + product.cost * ingredient.count
                end
            end
            if cost >= price then
                print(('        %s: ingredients %d >= sale %d'):format(id, cost, price))
                return false
            end
        end
    end
    return true
end)())

-- ═══════════════════════════════════════════════════════════════
group('permissions')
-- ═══════════════════════════════════════════════════════════════

check('unknown grade falls back to the lowest, not to full access',
    Permissions.can(999, MN.PERM.MANAGE) == false
    and Permissions.can(-5, MN.PERM.MANAGE) == false
    and Permissions.can(nil, MN.PERM.MANAGE) == false)

check('trainee cannot use the register',
    Permissions.can(0, MN.PERM.REGISTER) == false)

check('only manager and owner may manage',
    Permissions.can(3, MN.PERM.MANAGE) == false
    and Permissions.can(4, MN.PERM.MANAGE) == true
    and Permissions.can(5, MN.PERM.MANAGE) == true)

check('assignable rank stays below owner',
    Permissions.maxAssignable < Permissions.maxGrade())

check('owner grade is flagged as owner',
    Permissions.isOwner(Permissions.maxGrade()) == true
    and Permissions.isOwner(0) == false)

check('every grade has a payroll amount', (function()
    for level in pairs(Permissions.grades) do
        if Permissions.pay(level) <= 0 then return false end
    end
    return true
end)())

-- ═══════════════════════════════════════════════════════════════
group('input validation (MN.int)')
-- ═══════════════════════════════════════════════════════════════

check('rejects nil / text / boolean',
    MN.int(nil) == nil and MN.int('abc') == nil and MN.int(true) == nil)
check('rejects NaN and infinity',
    MN.int(0/0) == nil and MN.int(math.huge) == nil and MN.int(-math.huge) == nil)
check('enforces the lower bound', MN.int(0, 1, 10) == nil)
check('enforces the upper bound', MN.int(11, 1, 10) == nil)
check('accepts inside the range', MN.int(5, 1, 10) == 5)
check('floors a decimal', MN.int(3.9, 1, 10) == 3)
check('rejects a negative quantity', MN.int(-4, 1, 10) == nil)
check('accepts a numeric string', MN.int('7', 1, 10) == 7)

-- ═══════════════════════════════════════════════════════════════
group('money formatting')
-- ═══════════════════════════════════════════════════════════════

check('zero', MN.money(0) == '0')
check('hundreds', MN.money(999) == '999')
check('thousands', MN.money(1000) == '1,000')
check('millions', MN.money(1234567) == '1,234,567')
check('negative', MN.money(-4500) == '-4,500')
check('nil is safe', MN.money(nil) == '0')

-- ═══════════════════════════════════════════════════════════════
group('ingredient checking with the any-scoop wildcard')
-- ═══════════════════════════════════════════════════════════════

local function stock(t) INV = t end

stock({ mn_milk = 5, mn_cream = 5, mn_sugar = 5, mn_vanilla = 5 })
local vanilla = Recipes.byId['scoop_vanilla']
check('sufficient ingredients pass', (MN.crafting.check(1, vanilla.ingredients, 1)))
check('a batch beyond stock is refused', not (MN.crafting.check(1, vanilla.ingredients, 6)))

stock({ mn_cup = 5, mn_topping = 5, mn_scoop_mango = 1, mn_scoop_vanilla = 1, mn_scoop_pistachio = 1 })
local sundae = Recipes.byId['sundae']
check('wildcard draws across flavours', (MN.crafting.check(1, sundae.ingredients, 1)))
check('wildcard refuses beyond the pool', not (MN.crafting.check(1, sundae.ingredients, 2)))

-- The dangerous case: a recipe naming a specific scoop AND the wildcard must
-- never satisfy both from one item.
local mixed = {
    { item = 'mn_scoop_mango', count = 1 },
    { item = Products.SCOOP_ANY, count = 1 },
}
stock({ mn_scoop_mango = 1 })
check('explicit + wildcard cannot double-spend one scoop',
    not (MN.crafting.check(1, mixed, 1)))
stock({ mn_scoop_mango = 2 })
check('explicit + wildcard passes with two of the same', (MN.crafting.check(1, mixed, 1)))
stock({ mn_scoop_mango = 1, mn_scoop_vanilla = 1 })
check('explicit + wildcard passes across two flavours', (MN.crafting.check(1, mixed, 1)))

stock({})
local ok, missing = MN.crafting.check(1, sundae.ingredients, 1)
check('empty inventory is refused', not ok)
check('every shortfall is reported', #missing == 3)

-- ═══════════════════════════════════════════════════════════════
group('ingredient consumption')
-- ═══════════════════════════════════════════════════════════════

stock({ mn_cup = 5, mn_topping = 5, mn_scoop_mango = 1, mn_scoop_vanilla = 1, mn_scoop_pistachio = 1 })
check('consume succeeds when stocked', MN.crafting.consume(1, sundae.ingredients, 1))
check('all three scoops were taken',
    (INV.mn_scoop_mango or 0) == 0 and (INV.mn_scoop_vanilla or 0) == 0
    and (INV.mn_scoop_pistachio or 0) == 0)
check('exactly one cup was taken', INV.mn_cup == 4)
check('no negative quantities', (function()
    for _, v in pairs(INV) do if v < 0 then return false end end
    return true
end)())

stock({ mn_scoop_mango = 1, mn_scoop_vanilla = 1 })
MN.crafting.consume(1, mixed, 1)
check('mixed consumption empties both flavours',
    (INV.mn_scoop_mango or 0) == 0 and (INV.mn_scoop_vanilla or 0) == 0)

stock({ mn_cup = 1 })
check('consume refuses a short inventory without charging',
    MN.crafting.consume(1, sundae.ingredients, 1) == false and INV.mn_cup == 1)

-- ═══════════════════════════════════════════════════════════════
group('melting curve')
-- ═══════════════════════════════════════════════════════════════

local now = os.time()
local function aged(minutes) return { madeAt = now - minutes * 60 } end

check('fresh product is worth full price', MN.crafting.freshness(aged(0)) == 1.0)
check('still full at the freshness limit', MN.crafting.freshness(aged(Config.Melting.freshMinutes)) == 1.0)

local half = MN.crafting.freshness(aged(30))
check('value decays after the limit', half < 1.0 and half > Config.Melting.minValueRatio)
check('decay is monotonic', MN.crafting.freshness(aged(40)) < half)
check('never falls below the floor before ruin',
    MN.crafting.freshness(aged(44)) >= Config.Melting.minValueRatio)

local ruinedRatio, ruined = MN.crafting.freshness(aged(Config.Melting.ruinMinutes))
check('ruined past the limit', ruined == true and ruinedRatio == 0.0)
check('still ruined much later', select(2, MN.crafting.freshness(aged(999))) == true)
check('no metadata means fresh', MN.crafting.freshness(nil) == 1.0)
check('a product 30 minutes old is not ruined', select(2, MN.crafting.freshness(aged(30))) == false)

-- ═══════════════════════════════════════════════════════════════
group('localisation')
-- ═══════════════════════════════════════════════════════════════

check('English and Arabic have identical keys', (function()
    local en, ar = MN.Locales.en, MN.Locales.ar
    for key in pairs(en) do if ar[key] == nil then return false end end
    for key in pairs(ar) do if en[key] == nil then return false end end
    return true
end)())

check('Arabic is marked right-to-left', MN.Locales.ar.dir == 'rtl')
check('English is marked left-to-right', MN.Locales.en.dir == 'ltr')

Config.Locale = 'en'
MN.reloadLocale()
check('translation resolves', T('duty_on') == MN.Locales.en.duty_on)
check('formatting substitutes', T('craft_done', 3, 'Mango Cup'):find('3') ~= nil)
check('a missing key returns the key itself', T('this_key_does_not_exist') == 'this_key_does_not_exist')

Config.Locale = 'ar'
MN.reloadLocale()
check('Arabic resolves', T('duty_on') == MN.Locales.ar.duty_on)
check('direction follows the language', MN.dir() == 'rtl')
check('locale table is complete for the NUI', MN.count(MN.localeTable()) == MN.count(MN.Locales.en))

Config.Locale = 'en'
MN.reloadLocale()

-- ═══════════════════════════════════════════════════════════════
group('product helpers')
-- ═══════════════════════════════════════════════════════════════

check('label falls back to the item name for an unknown product',
    Products.label('nope_not_real') == 'nope_not_real')
check('price of an unsellable item is zero', Products.price('mn_milk') == 0)
check('scoops are perishable', Products.perishable('mn_scoop_mango') == true)
check('bakery is not perishable', Products.perishable('mn_cone') == false)
check('menu is non-empty', #Products.menu() > 0)
check('catalogue is non-empty', #Products.catalogue() > 0)
check('catalogue is ingredients only', (function()
    for _, entry in ipairs(Products.catalogue()) do
        if entry.category ~= 'ingredient' then return false end
    end
    return true
end)())

-- ═══════════════════════════════════════════════════════════════
group('recipe resolution (wire safety)')
-- ═══════════════════════════════════════════════════════════════

check('a real id at its own station resolves',
    Recipes.resolve('sundae', 'assembly') ~= nil)
check('a real id at the wrong station is refused',
    Recipes.resolve('sundae', 'oven') == nil)
check('an unknown id is refused', Recipes.resolve('give_me_money', 'assembly') == nil)
check('a non-string id is refused',
    Recipes.resolve(42, 'assembly') == nil and Recipes.resolve(nil, 'assembly') == nil
    and Recipes.resolve({}, 'assembly') == nil)

-- ═══════════════════════════════════════════════════════════════
group('placement overrides')
-- ═══════════════════════════════════════════════════════════════

local originalX = Locations.shop.freezer.coords.x
Locations.applyOverrides({ freezer = { x = 1.5, y = 2.5, z = 3.5, w = 90.0 } })
check('an override moves the anchor', Locations.shop.freezer.coords.x == 1.5)
check('an override sets the heading', Locations.shop.freezer.heading == 90.0)

Locations.applyOverrides({ churn = { x = 9.0, y = 9.0, z = 9.0 } })
check('a station can be moved', Locations.station('churn').coords.x == 9.0)

Locations.applyOverrides({ truck = { x = 7.0, y = 7.0, z = 7.0, w = 45.0 } })
check('a vehicle bay keeps its heading', Locations.shop.truck.spawn.w == 45.0)

Locations.applyOverrides({ nonsense_anchor = { x = 1, y = 1, z = 1 } })
check('an unknown anchor is ignored safely', true)
Locations.applyOverrides('not a table')
check('a malformed override is ignored safely', true)

Locations.shop.freezer.coords = vec3(originalX, 0, 0)

-- ═══════════════════════════════════════════════════════════════
print(('\n%s\n  %d passed, %d failed\n'):format(string.rep('─', 46), pass, fail))
os.exit(fail == 0 and 0 or 1)
