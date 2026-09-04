---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Recipes

    Every recipe belongs to a station id declared in config/locations.lua.
    The server reads a recipe ONLY by id from this table; nothing about a
    recipe is ever taken from the client's message.

    Fields
      id           unique across the whole resource (used in wire validation)
      station      station id it can be made at
      result       { item = <product name>, count = n }
      ingredients  list of { item = <product name | Products.SCOOP_ANY>, count = n }
      time         milliseconds, before Config.Crafting.timeMultiplier
      grade        minimum job grade
      difficulty   1..5 — drives the skill check
      anim         { dict, clip } played while preparing
      icon         Font Awesome name used in the menu
]]

Recipes = {}

local ANY = Products.SCOOP_ANY
local CHURN  = { dict = 'amb@prop_human_bbq@male@base',            clip = 'base' }
local BENCH  = { dict = 'amb@prop_human_parking_meter@male@base',  clip = 'base' }

Recipes.list = {

    -- ── Churn: base scoops ────────────────────────────────────
    { id = 'scoop_mango',      station = 'churn', icon = 'ice-cream', time = 6500, grade = 0, difficulty = 2, anim = CHURN,
      result = { item = 'mn_scoop_mango', count = 2 },
      ingredients = { { item = 'mn_milk', count = 1 }, { item = 'mn_cream', count = 1 }, { item = 'mn_sugar', count = 1 }, { item = 'mn_mango', count = 2 } } },

    { id = 'scoop_vanilla',    station = 'churn', icon = 'ice-cream', time = 6000, grade = 0, difficulty = 1, anim = CHURN,
      result = { item = 'mn_scoop_vanilla', count = 2 },
      ingredients = { { item = 'mn_milk', count = 1 }, { item = 'mn_cream', count = 1 }, { item = 'mn_sugar', count = 1 }, { item = 'mn_vanilla', count = 1 } } },

    { id = 'scoop_chocolate',  station = 'churn', icon = 'ice-cream', time = 6000, grade = 0, difficulty = 1, anim = CHURN,
      result = { item = 'mn_scoop_chocolate', count = 2 },
      ingredients = { { item = 'mn_milk', count = 1 }, { item = 'mn_cream', count = 1 }, { item = 'mn_sugar', count = 1 }, { item = 'mn_cocoa', count = 1 } } },

    { id = 'scoop_strawberry', station = 'churn', icon = 'ice-cream', time = 6500, grade = 0, difficulty = 2, anim = CHURN,
      result = { item = 'mn_scoop_strawberry', count = 2 },
      ingredients = { { item = 'mn_milk', count = 1 }, { item = 'mn_cream', count = 1 }, { item = 'mn_sugar', count = 1 }, { item = 'mn_strawberry', count = 2 } } },

    { id = 'scoop_pistachio',  station = 'churn', icon = 'ice-cream', time = 9000, grade = 2, difficulty = 4, anim = CHURN,
      result = { item = 'mn_scoop_pistachio', count = 2 },
      ingredients = { { item = 'mn_milk', count = 1 }, { item = 'mn_cream', count = 2 }, { item = 'mn_sugar', count = 1 }, { item = 'mn_pistachio', count = 2 } } },

    -- ── Oven: shelf-stable bases ──────────────────────────────
    { id = 'bake_cone',    station = 'oven', icon = 'fire-burner', time = 8000, grade = 0, difficulty = 2, anim = CHURN,
      result = { item = 'mn_cone', count = 4 },
      ingredients = { { item = 'mn_flour', count = 2 }, { item = 'mn_sugar', count = 1 }, { item = 'mn_milk', count = 1 } } },

    { id = 'bake_brownie', station = 'oven', icon = 'cookie', time = 9000, grade = 1, difficulty = 2, anim = CHURN,
      result = { item = 'mn_brownie', count = 4 },
      ingredients = { { item = 'mn_flour', count = 2 }, { item = 'mn_cocoa', count = 1 }, { item = 'mn_sugar', count = 2 } } },

    -- ── Assembly bench: the counter menu ──────────────────────
    { id = 'cone_single',  station = 'assembly', icon = 'ice-cream', time = 3500, grade = 0, difficulty = 1, anim = BENCH,
      result = { item = 'mn_cone_single', count = 1 },
      ingredients = { { item = 'mn_cone', count = 1 }, { item = ANY, count = 1 } } },

    { id = 'cone_double',  station = 'assembly', icon = 'ice-cream', time = 5000, grade = 1, difficulty = 3, anim = BENCH,
      result = { item = 'mn_cone_double', count = 1 },
      ingredients = { { item = 'mn_cone', count = 1 }, { item = ANY, count = 2 } } },

    { id = 'mango_cup',    station = 'assembly', icon = 'cup-togo', time = 5500, grade = 0, difficulty = 2, anim = BENCH,
      result = { item = 'mn_mango_cup', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = 'mn_scoop_mango', count = 2 }, { item = 'mn_syrup', count = 1 } } },

    { id = 'sundae',       station = 'assembly', icon = 'bowl-food', time = 7000, grade = 1, difficulty = 3, anim = BENCH,
      result = { item = 'mn_sundae', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = ANY, count = 3 }, { item = 'mn_topping', count = 1 } } },

    { id = 'mango_sundae', station = 'assembly', icon = 'bowl-food', time = 8000, grade = 2, difficulty = 4, anim = BENCH,
      result = { item = 'mn_mango_sundae', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = 'mn_scoop_mango', count = 2 }, { item = ANY, count = 1 }, { item = 'mn_syrup', count = 1 }, { item = 'mn_topping', count = 1 } } },

    { id = 'sandwich',     station = 'assembly', icon = 'cookie-bite', time = 5500, grade = 2, difficulty = 3, anim = BENCH,
      result = { item = 'mn_sandwich', count = 1 },
      ingredients = { { item = 'mn_brownie', count = 2 }, { item = ANY, count = 1 } } },

    { id = 'family_box',   station = 'assembly', icon = 'box-open', time = 11000, grade = 2, difficulty = 4, anim = BENCH,
      result = { item = 'mn_family_box', count = 1 },
      ingredients = { { item = 'mn_cup', count = 2 }, { item = ANY, count = 6 }, { item = 'mn_topping', count = 2 } } },

    -- ── Blender: drinks ───────────────────────────────────────
    { id = 'shake_mango',      station = 'blender', icon = 'blender', time = 5000, grade = 0, difficulty = 2, anim = CHURN,
      result = { item = 'mn_shake_mango', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = 'mn_milk', count = 2 }, { item = 'mn_scoop_mango', count = 1 }, { item = 'mn_syrup', count = 1 } } },

    { id = 'shake_vanilla',    station = 'blender', icon = 'blender', time = 5000, grade = 0, difficulty = 1, anim = CHURN,
      result = { item = 'mn_shake_vanilla', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = 'mn_milk', count = 2 }, { item = 'mn_scoop_vanilla', count = 1 } } },

    { id = 'shake_chocolate',  station = 'blender', icon = 'blender', time = 5000, grade = 0, difficulty = 1, anim = CHURN,
      result = { item = 'mn_shake_chocolate', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = 'mn_milk', count = 2 }, { item = 'mn_scoop_chocolate', count = 1 } } },

    { id = 'shake_strawberry', station = 'blender', icon = 'blender', time = 5500, grade = 1, difficulty = 2, anim = CHURN,
      result = { item = 'mn_shake_strawberry', count = 1 },
      ingredients = { { item = 'mn_cup', count = 1 }, { item = 'mn_milk', count = 1 }, { item = 'mn_scoop_strawberry', count = 1 }, { item = 'mn_strawberry', count = 1 } } },
}

-- ═══════════════════════════════════════════════════════════════
-- Tickets NPC customers ask for. Weight drives how often.
-- ═══════════════════════════════════════════════════════════════
Recipes.ticketPool = {
    { item = 'mn_cone_single',      weight = 10, maxCount = 2 },
    { item = 'mn_mango_cup',        weight = 9,  maxCount = 2 },
    { item = 'mn_shake_mango',      weight = 8,  maxCount = 2 },
    { item = 'mn_cone_double',      weight = 7,  maxCount = 2 },
    { item = 'mn_sundae',           weight = 6,  maxCount = 1 },
    { item = 'mn_shake_vanilla',    weight = 5,  maxCount = 2 },
    { item = 'mn_shake_chocolate',  weight = 5,  maxCount = 2 },
    { item = 'mn_mango_sundae',     weight = 4,  maxCount = 1 },
    { item = 'mn_shake_strawberry', weight = 4,  maxCount = 1 },
    { item = 'mn_sandwich',         weight = 3,  maxCount = 1 },
    { item = 'mn_family_box',       weight = 1,  maxCount = 1 },
}

-- ═══════════════════════════════════════════════════════════════
-- Derived indexes
-- ═══════════════════════════════════════════════════════════════

---@type table<string, table>
Recipes.byId = {}
---@type table<string, table>
Recipes.byResult = {}
---@type table<string, table[]>
Recipes.byStation = {}

do
    for i = 1, #Recipes.list do
        local recipe = Recipes.list[i]

        if Recipes.byId[recipe.id] then
            print(('[MangoNazlet] ^1duplicate recipe id "%s"^7'):format(recipe.id))
        end
        Recipes.byId[recipe.id] = recipe
        Recipes.byResult[recipe.result.item] = recipe

        local station = Recipes.byStation[recipe.station]
        if not station then
            station = {}
            Recipes.byStation[recipe.station] = station
        end
        station[#station + 1] = recipe
    end
end

---Recipes available at a station, never nil.
---@param stationId string
---@return table[]
function Recipes.forStation(stationId)
    return Recipes.byStation[stationId] or {}
end

---Resolve an id that arrived from a client into a trusted recipe.
---Returns nil when the id is unknown or the station does not match, which the
---caller treats as a tampering attempt.
---@param id any
---@param stationId any
---@return table|nil
function Recipes.resolve(id, stationId)
    if type(id) ~= 'string' then return nil end
    local recipe = Recipes.byId[id]
    if not recipe then return nil end
    if stationId ~= nil and recipe.station ~= stationId then return nil end
    return recipe
end
