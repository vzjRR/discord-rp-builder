---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — The physical shop.

    Without this the resource is a set of invisible interaction points on an
    empty patch of grass: the prompt appears, the menus work, and there is
    visibly no restaurant. This file builds one out of props that ship with
    GTA V, so the shop is real on a stock server with no MLO, no stream folder
    and no downloads.

    Every model name below was checked against the game's own object list.
    Anything the client cannot find is skipped with a warning rather than
    breaking the build.

    Two kinds of placement:

      anchored  a prop that sits on one of the interaction anchors in
                config/locations.lua, so what you see is what you can use.
                Move the anchor with /mn:place and the prop follows.

      decor     a prop positioned relative to the shop centre. `offset` is in
                shop-local space — x is right, y is forward, z is up — and is
                rotated to match the shop, so the whole build turns together.

    Fields
      model      object name
      heading    extra rotation in degrees, added to the anchor's own heading
      z          vertical nudge in metres, applied after the prop is grounded
      ground     false to keep the exact z instead of snapping to the surface
]]

Props = {}

-- Set false to run with no physical build at all.
Props.enabled = true

-- Props appear when a player is closer than this and are removed beyond it.
Props.renderDistance = 150.0

-- ═══════════════════════════════════════════════════════════════
-- On the interaction anchors
-- ═══════════════════════════════════════════════════════════════
Props.anchored = {
    -- The serving counter, customer side.
    counter  = { model = 'prop_ff_counter_01', heading = 0.0 },
    -- Till, staff side.
    register = { model = 'prop_ff_counter_02', heading = 180.0 },
    -- Chilled display the walk-in menu sells from.
    display  = { model = 'prop_display_unit_01', heading = 0.0 },

    -- Stations, each one the machine it represents.
    churn    = { model = 'prop_juice_dispenser', heading = 0.0 },
    assembly = { model = 'prop_ff_sink_01', heading = 0.0 },
    blender  = { model = 'prop_kitch_juicer', heading = 0.0 },
    oven     = { model = 'prop_cooker_03', heading = 0.0 },

    -- Storage.
    freezer  = { model = 'prop_cs_ice_locker', heading = 0.0 },
    pantry   = { model = 'prop_ff_shelves_01', heading = 0.0 },

    -- Wholesale drop-off.
    supply   = { model = 'prop_crate_01a', heading = 0.0 },

    -- Back office.
    office   = { model = 'prop_ff_counter_03', heading = 0.0 },

    -- Staff clock: a shelf by the back wall to hang the board on.
    duty     = { model = 'prop_food_bs_bshelf', heading = 0.0 },
}

-- ═══════════════════════════════════════════════════════════════
-- Dressing, relative to the shop centre
-- ═══════════════════════════════════════════════════════════════
Props.decor = {
    -- Shade over the service area.
    { model = 'prop_gazebo_03',    offset = vec3( 0.0,  0.5, 0.0), heading = 0.0 },

    -- Customer seating out front, under parasols.
    { model = 'prop_picnictable_02', offset = vec3(-3.6,  4.2, 0.0), heading =  10.0 },
    { model = 'prop_parasol_02_b',   offset = vec3(-3.6,  4.2, 0.0), heading =   0.0 },
    { model = 'prop_picnictable_02', offset = vec3( 2.4,  5.0, 0.0), heading = -15.0 },
    { model = 'prop_parasol_01',     offset = vec3( 2.4,  5.0, 0.0), heading =   0.0 },
    { model = 'prop_chair_01a',      offset = vec3( 4.6,  3.0, 0.0), heading =  70.0 },
    { model = 'prop_chair_01a',      offset = vec3( 5.4,  3.6, 0.0), heading =  95.0 },

    -- Working clutter behind the counter.
    { model = 'prop_bar_fridge_01', offset = vec3(-2.2, -2.6, 0.0), heading =  35.0 },
    { model = 'prop_bar_fridge_02', offset = vec3(-1.3, -2.9, 0.0), heading =  35.0 },
    { model = 'prop_bar_ice_01',    offset = vec3( 0.4, -2.7, 0.0), heading =  35.0 },
    { model = 'prop_crate_01a',     offset = vec3(-4.4, -1.4, 0.0), heading =  20.0 },
    { model = 'prop_crate_01a',     offset = vec3(-4.4, -1.4, 0.9), heading =  65.0, ground = false },

    -- Bins where customers actually are.
    { model = 'prop_bin_beach_01d', offset = vec3( 4.0,  1.2, 0.0), heading =   0.0 },
    { model = 'prop_food_bin_01',   offset = vec3(-4.8,  2.0, 0.0), heading =   0.0 },
}

-- ═══════════════════════════════════════════════════════════════
-- On the counters
--
-- Placed on top of an anchored prop rather than on the ground, so these are
-- listed separately with the anchor they sit on and never grounded.
-- ═══════════════════════════════════════════════════════════════
Props.onCounter = {
    { anchor = 'counter',  model = 'prop_food_bs_cups01', z = 1.02, side =  0.55, heading = 0.0 },
    { anchor = 'counter',  model = 'prop_food_bs_tray_01', z = 1.02, side = -0.60, heading = 0.0 },
    { anchor = 'register', model = 'prop_food_bs_soda_01', z = 1.02, side =  0.50, heading = 0.0 },
    { anchor = 'display',  model = 'prop_food_bs_cups01', z = 1.02, side = -0.45, heading = 0.0 },
}

-- ═══════════════════════════════════════════════════════════════
-- Staff on shift
--
-- A shop with nobody in it reads as scenery. These are decoration: they stand
-- where staff would stand and do not replace real players, who serve customers
-- through the counter and the register as before.
--
-- Every model name below is in the game's own ped list.
-- ═══════════════════════════════════════════════════════════════
Props.staff = {
    enabled = true,

    -- Offsets are in shop-local space, like Props.decor.
    --   scenario  an ambient animation the ped loops
    --   heading   extra rotation on top of the shop's own
    members = {
        {
            model = 's_f_y_shop_mid',
            offset = vec3(-0.9, -1.15, 0.0),
            heading = 180.0,
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
        {
            model = 's_m_y_shop_mask',
            offset = vec3( 0.9, -1.15, 0.0),
            heading = 180.0,
            scenario = 'WORLD_HUMAN_STAND_MOBILE',
        },
        {
            model = 's_m_y_waiter_01',
            offset = vec3( 2.6,  1.9, 0.0),
            heading = 235.0,
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
    },

    -- Customers milling about out front, so the place looks open.
    customers = {
        { model = 'a_f_y_beach_01',   offset = vec3(-2.1, 1.5, 0.0), heading = 20.0,  scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        { model = 'a_m_y_hipster_01', offset = vec3( 1.4, 2.6, 0.0), heading = 200.0, scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
    },
}

---Total number of props this build will attempt.
---@return number
function Props.count()
    local total = 0
    for _ in pairs(Props.anchored) do total = total + 1 end
    return total + #Props.decor + #Props.onCounter
end
