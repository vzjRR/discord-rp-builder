---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Building the shop.

    Spawns the props from config/props.lua when a player comes near and removes
    them when they leave. Everything is local to each client: nothing is
    networked, so the build costs the server nothing and cannot desync.

    A model the game does not have is skipped with a warning. A missing prop
    leaves a gap; it never stops the rest of the shop appearing.
]]

MN = MN or {}

local spawned = {}
local built = false

-- ═══════════════════════════════════════════════════════════════
-- Placement helpers
-- ═══════════════════════════════════════════════════════════════

---Rotate a shop-local offset into world space, so the whole build turns with
---the shop instead of every prop needing its own world coordinates.
---@param offset vector3
---@param heading number  shop heading in degrees
---@return vector3
local function toWorld(offset, heading)
    local centre = Locations.shop.centre
    local radians = math.rad(heading)
    local cos, sin = math.cos(radians), math.sin(radians)

    return vec3(
        centre.x + (offset.x * cos - offset.y * sin),
        centre.y + (offset.x * sin + offset.y * cos),
        centre.z + offset.z
    )
end

---The heading the shop as a whole faces. Taken from the serving counter, so
---moving the counter with /mn:place turns the dressing to match.
---@return number
local function shopHeading()
    local counter = Locations.shop.counter
    return (counter and counter.heading) or 0.0
end

---Create one prop.
---@param model string
---@param coords vector3
---@param heading number
---@param ground boolean
---@param zNudge number
---@return number|nil entity
local function place(model, coords, heading, ground, zNudge)
    local hash = MN.loadModel(model)
    if not hash then return nil end

    local object = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(object) then return nil end

    SetEntityHeading(object, heading)

    -- Snapping to the surface is what keeps the build usable after /mn:place
    -- moves an anchor onto ground at a different height.
    if ground ~= false then
        PlaceObjectOnGroundProperly(object)
    end

    if zNudge and zNudge ~= 0.0 then
        local at = GetEntityCoords(object)
        SetEntityCoords(object, at.x, at.y, at.z + zNudge, false, false, false, false)
    end

    FreezeEntityPosition(object, true)
    SetEntityInvincible(object, true)
    -- Props are scenery: players walk around them, never push them about.
    SetEntityCanBeDamaged(object, false)

    spawned[#spawned + 1] = object
    return object
end

-- ═══════════════════════════════════════════════════════════════
-- Build and teardown
-- ═══════════════════════════════════════════════════════════════

local function teardown()
    for i = 1, #spawned do
        local object = spawned[i]
        if object and DoesEntityExist(object) then
            SetEntityAsMissionEntity(object, true, true)
            DeleteObject(object)
        end
    end
    spawned = {}
    built = false
end

local function build()
    if built then return end
    built = true

    local heading = shopHeading()
    local placed, missing = 0, 0

    -- 1. Props that sit on an interaction anchor.
    for anchor, definition in pairs(Props.anchored) do
        local coords = Locations.coords(anchor)
        if coords then
            local anchorHeading = 0.0
            local entry = Locations.shop[anchor] or Locations.station(anchor)
            if entry and entry.heading then anchorHeading = entry.heading end

            local object = place(definition.model, coords,
                anchorHeading + (definition.heading or 0.0),
                definition.ground, definition.z)

            if object then placed = placed + 1 else missing = missing + 1 end
        end
    end

    -- 2. Dressing around the shop centre.
    for i = 1, #Props.decor do
        local definition = Props.decor[i]
        local object = place(definition.model,
            toWorld(definition.offset, heading),
            heading + (definition.heading or 0.0),
            definition.ground, definition.z)

        if object then placed = placed + 1 else missing = missing + 1 end
    end

    -- 3. Items resting on top of an anchored prop.
    for i = 1, #Props.onCounter do
        local definition = Props.onCounter[i]
        local coords = Locations.coords(definition.anchor)

        if coords then
            local entry = Locations.shop[definition.anchor]
            local anchorHeading = (entry and entry.heading) or heading

            -- `side` slides the item along the counter it stands on.
            local radians = math.rad(anchorHeading)
            local side = definition.side or 0.0
            local at = vec3(
                coords.x + math.cos(radians) * side,
                coords.y + math.sin(radians) * side,
                coords.z + (definition.z or 1.0)
            )

            local object = place(definition.model, at,
                anchorHeading + (definition.heading or 0.0), false, nil)

            if object then placed = placed + 1 else missing = missing + 1 end
        end
    end

    MN.debug('shop built: %d props placed, %d unavailable', placed, missing)
    if missing > 0 then
        MN.warn('%d of the shop props are not in this game build and were skipped', missing)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- Only build when somebody is there to see it
-- ═══════════════════════════════════════════════════════════════

if Props.enabled then
    CreateThread(function()
        while true do
            local distance = #(GetEntityCoords(PlayerPedId()) - Locations.shop.centre)

            if distance <= Props.renderDistance then
                build()
            elseif built then
                teardown()
            end

            -- Checking twice a second within sight, once every three seconds far away.
            Wait(distance <= Props.renderDistance * 2 and 500 or 3000)
        end
    end)
end

-- An admin moved something: rebuild so the props follow the anchors.
AddEventHandler('mangonazlet:client:relocated', function()
    if not Props.enabled then return end
    teardown()
    build()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= MN.RESOURCE then return end
    teardown()
end)

-- ═══════════════════════════════════════════════════════════════
-- The sign
--
-- No GTA prop can carry the shop's name, least of all in Arabic, so the name
-- is drawn over the counter instead. It is what makes the build read as
-- MangoNazlet rather than as a generic food stand.
-- ═══════════════════════════════════════════════════════════════

if Props.enabled and Config.UI.sign then
    CreateThread(function()
        while true do
            local sleep = 1000
            local player = GetEntityCoords(PlayerPedId())
            local centre = Locations.shop.centre
            local distance = #(player - centre)

            if distance < Config.UI.signDistance then
                sleep = 0

                -- Fade the name in as you approach rather than popping it on.
                local alpha = math.floor(255 * math.min((Config.UI.signDistance - distance) / 8.0, 1.0))

                SetDrawOrigin(centre.x, centre.y, centre.z + 2.75, 0)

                SetTextFont(4)
                SetTextScale(0.0, 0.62)
                SetTextColour(245, 166, 35, alpha)
                SetTextCentre(true)
                SetTextOutline()
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(T('brand'))
                EndTextCommandDisplayText(0.0, 0.0)

                SetTextFont(4)
                SetTextScale(0.0, 0.34)
                SetTextColour(255, 246, 230, math.floor(alpha * 0.8))
                SetTextCentre(true)
                SetTextOutline()
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(T('tagline'))
                EndTextCommandDisplayText(0.0, 0.055)

                ClearDrawOrigin()
            elseif distance < Config.UI.signDistance * 3 then
                sleep = 250
            end

            Wait(sleep)
        end
    end)
end

-- Exposed so /mn:place can show the build moving without a reconnect.
function MN.rebuildProps()
    teardown()
    build()
end
