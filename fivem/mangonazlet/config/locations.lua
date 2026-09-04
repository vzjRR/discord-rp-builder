---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Placement.

    The default placement is an open-air beachfront kiosk on the Vespucci
    boardwalk. That choice is deliberate: it needs NO MLO and no map resource,
    so the shop is walkable and fully playable on a stock server the moment the
    resource starts.

    Moving the shop does NOT mean editing this file. In game, as an admin:

        /mn:place            → interactive placer, walk and save each anchor
        /mn:place freezer    → save just one anchor where you stand
        /mn:place reset      → back to the defaults below

    Saved placements live in the `mn_locations` table and are applied over
    these defaults on start, so they survive updates to the resource.
]]

Locations = {}

-- Anchors that can be repositioned in game. Order is the order /mn:place walks.
Locations.anchors = {
    'duty', 'register', 'counter', 'customer', 'display',
    'churn', 'assembly', 'blender', 'oven',
    'freezer', 'pantry', 'supply', 'office',
    'truck', 'van',
}

Locations.shop = {
    id = 'vespucci',
    label = { en = 'MangoNazlet — Vespucci', ar = 'مانجو نزلت — فيسبوتشي' },
    centre = vec3(-1223.50, -1576.90, 4.61),

    blip = {
        sprite = 93, colour = 46, scale = 0.80, shortRange = true,
    },

    -- Staff clock, just behind the service window.
    duty     = { coords = vec3(-1225.31, -1580.02, 4.61), size = vec3(1.2, 1.2, 2.0), heading = 35.0 },
    -- Staff side of the till.
    register = { coords = vec3(-1220.05, -1578.30, 4.61), size = vec3(1.6, 1.0, 1.5), heading = 35.0 },
    -- Customer side of the till: where the NUI menu opens.
    counter  = { coords = vec3(-1219.10, -1579.55, 4.61), size = vec3(2.0, 1.2, 1.5), heading = 215.0 },
    -- Where an NPC ticket customer stands to wait.
    customer = { stand = vec4(-1218.95, -1580.35, 4.61, 215.0), approach = vec3(-1212.60, -1585.10, 4.30) },

    -- Work stations. Each id must have recipes in config/recipes.lua.
    stations = {
        { id = 'churn',    icon = 'ice-cream',   label = { en = 'Churn machine',  ar = 'ماكينة التقليب' }, coords = vec3(-1222.90, -1576.20, 4.61), size = vec3(1.4, 1.0, 1.6), heading = 35.0 },
        { id = 'assembly', icon = 'utensils',    label = { en = 'Assembly bench', ar = 'طاولة التحضير' },  coords = vec3(-1224.65, -1574.90, 4.61), size = vec3(2.0, 1.2, 1.5), heading = 35.0 },
        { id = 'blender',  icon = 'blender',     label = { en = 'Blender',        ar = 'الخلاط' },         coords = vec3(-1221.40, -1574.55, 4.61), size = vec3(1.0, 1.0, 1.5), heading = 35.0 },
        { id = 'oven',     icon = 'fire-burner', label = { en = 'Waffle oven',    ar = 'فرن الوافل' },     coords = vec3(-1226.15, -1573.40, 4.61), size = vec3(1.4, 1.0, 1.8), heading = 35.0 },
    },

    -- Display case: staff stock it, walk-in customers buy out of it.
    display  = { coords = vec3(-1221.90, -1579.90, 4.61), size = vec3(1.8, 1.0, 1.4), heading = 35.0 },
    -- Staff freezer (ox_inventory stash) for holding finished goods.
    freezer  = { coords = vec3(-1227.80, -1576.10, 4.61), size = vec3(1.4, 1.4, 2.0), heading = 35.0 },
    -- Raw ingredients.
    pantry   = { coords = vec3(-1229.40, -1574.60, 4.61), size = vec3(1.4, 1.4, 2.0), heading = 35.0 },
    -- Wholesale supplier.
    supply   = { coords = vec3(-1231.20, -1578.50, 4.61), size = vec3(1.6, 1.6, 2.0), heading = 35.0 },
    -- Management.
    office   = { coords = vec3(-1229.10, -1571.90, 4.61), size = vec3(1.2, 1.2, 2.0), heading = 35.0 },

    -- Ice cream truck bay.
    truck    = { spawn = vec4(-1210.35, -1568.20, 3.60, 125.0) },
    -- Supply van bay.
    van      = { spawn = vec4(-1216.10, -1564.85, 3.60, 125.0) },
}

-- ═══════════════════════════════════════════════════════════════
-- Supply run pickups — real, reachable industrial locations
-- ═══════════════════════════════════════════════════════════════
Locations.pickups = {
    { label = { en = 'Dairy depot',    ar = 'مستودع الألبان' }, coords = vec3(96.85, 6412.05, 31.40) },
    { label = { en = 'Fruit farm',     ar = 'مزرعة الفواكه' },  coords = vec3(2225.35, 5157.05, 58.95) },
    { label = { en = 'Cargo docks',    ar = 'ميناء البضائع' },  coords = vec3(-337.15, -2695.45, 6.00) },
    { label = { en = 'Sugar refinery', ar = 'مصنع السكر' },     coords = vec3(1204.15, -3115.65, 5.55) },
    { label = { en = 'Wholesale market', ar = 'سوق الجملة' },   coords = vec3(-1058.05, -1400.75, 5.55) },
}

-- ═══════════════════════════════════════════════════════════════
-- Mobile truck selling spots
-- ═══════════════════════════════════════════════════════════════
Locations.truckSpots = {
    { label = { en = 'Vespucci Beach',   ar = 'شاطئ فيسبوتشي' },  coords = vec3(-1180.25, -1500.40, 4.35), radius = 35.0, weight = 5 },
    { label = { en = 'Del Perro Pier',   ar = 'رصيف ديل بيرو' },  coords = vec3(-1620.50, -1032.85, 13.15), radius = 30.0, weight = 4 },
    { label = { en = 'Legion Square',    ar = 'حديقة ليجيون' },   coords = vec3(210.35, -935.50, 30.70),   radius = 25.0, weight = 4 },
    { label = { en = 'Vespucci Courts',  ar = 'ملاعب فيسبوتشي' }, coords = vec3(-1231.90, -1470.10, 4.35), radius = 25.0, weight = 3 },
    { label = { en = 'LS Airport',       ar = 'مطار لوس سانتوس' },coords = vec3(-1037.15, -2737.55, 20.15), radius = 30.0, weight = 2 },
    { label = { en = 'Sandy Shores',     ar = 'ساندي شورز' },     coords = vec3(1961.45, 3740.60, 32.35),  radius = 25.0, weight = 2 },
    { label = { en = 'Mount Chiliad',    ar = 'جبل تشيلياد' },    coords = vec3(450.85, 5566.30, 781.20),  radius = 20.0, weight = 1 },
}

-- Customer ped models used for tickets and truck queues.
Locations.customerModels = {
    'a_f_y_beach_01', 'a_m_y_beach_01', 'a_m_y_beach_02',
    'a_f_y_tourist_01', 'a_f_y_hipster_01', 'a_m_m_tourist_01',
    'a_m_y_hipster_01', 'a_f_m_beach_01', 'a_m_m_tourist_01',
    'a_f_y_genhot_01', 'a_m_y_genstreet_01', 'a_f_y_soucent_01',
}

-- ═══════════════════════════════════════════════════════════════
-- Accessors
-- ═══════════════════════════════════════════════════════════════

---@param id string
---@return table|nil
function Locations.station(id)
    for i = 1, #Locations.shop.stations do
        if Locations.shop.stations[i].id == id then return Locations.shop.stations[i] end
    end
    return nil
end

---Localised label for the shop, a station, a pickup or a truck spot.
---@param entry table
---@param lang? string
---@return string
function Locations.label(entry, lang)
    if type(entry) ~= 'table' or type(entry.label) ~= 'table' then return '' end
    lang = lang or (Config and Config.Locale) or 'en'
    return entry.label[lang] or entry.label.en or ''
end

---Coordinates of a named anchor, honouring anything saved by /mn:place.
---@param anchor string
---@return vector3|vector4|nil
function Locations.coords(anchor)
    local shop = Locations.shop
    local entry = shop[anchor]
    if not entry then
        local station = Locations.station(anchor)
        entry = station
    end
    if not entry then return nil end
    return entry.coords or entry.spawn or entry.stand
end

---Move the whole shop so its centre lands on `coords`, facing `heading`,
---keeping every anchor's position relative to the others.
---
---This is what makes "put the shop over there" a single action instead of
---fifteen. Each anchor is converted into shop-local space against the current
---centre and heading, then written back out against the new ones.
---@param coords vector3
---@param heading number
---@return table placements  -- { [anchor] = { x, y, z, w } }, ready to persist
function Locations.relocate(coords, heading)
    local shop = Locations.shop
    local oldCentre = shop.centre
    local oldHeading = (shop.counter and shop.counter.heading) or 0.0

    local delta = math.rad(heading - oldHeading)
    local cos, sin = math.cos(delta), math.sin(delta)

    ---@param point vector3|vector4
    ---@return table
    local function move(point)
        local dx, dy = point.x - oldCentre.x, point.y - oldCentre.y
        return {
            x = coords.x + (dx * cos - dy * sin),
            y = coords.y + (dx * sin + dy * cos),
            z = coords.z + (point.z - oldCentre.z),
        }
    end

    local placements = {}

    for i = 1, #Locations.anchors do
        local anchor = Locations.anchors[i]
        local entry = shop[anchor]
        if entry then
            local point = entry.coords or entry.spawn or entry.stand
            if point then
                local moved = move(point)
                local ownHeading = entry.heading
                    or (entry.spawn and entry.spawn.w)
                    or (entry.stand and entry.stand.w)
                moved.w = ((ownHeading or oldHeading) - oldHeading) + heading
                placements[anchor] = moved
            end
        end
    end

    for i = 1, #shop.stations do
        local station = shop.stations[i]
        local moved = move(station.coords)
        moved.w = (station.heading - oldHeading) + heading
        placements[station.id] = moved
    end

    return placements
end

---Apply placements loaded from the database over the defaults above.
---Called once on start by server/main.lua and mirrored to clients.
---@param overrides table  -- { [anchor] = { x, y, z, w? } }
function Locations.applyOverrides(overrides)
    if type(overrides) ~= 'table' then return end
    local shop = Locations.shop

    for anchor, position in pairs(overrides) do
        if type(position) == 'table' and position.x and position.y and position.z then
            local target = shop[anchor] or Locations.station(anchor)
            if target then
                if target.spawn then
                    target.spawn = vec4(position.x, position.y, position.z, position.w or target.spawn.w or 0.0)
                elseif target.stand then
                    target.stand = vec4(position.x, position.y, position.z, position.w or target.stand.w or 0.0)
                else
                    target.coords = vec3(position.x, position.y, position.z)
                    if position.w then target.heading = position.w + 0.0 end
                end
            end
        end
    end

    -- Keep the blip on the service counter after a move.
    if shop.register and shop.register.coords then
        shop.centre = shop.register.coords
    end
end
