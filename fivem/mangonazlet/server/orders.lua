---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — NPC customer tickets.

    The server owns the ticket list: it creates them, prices them, expires them
    and confirms delivery. Clients receive a read-only copy to display and to
    spawn the waiting customer ped.
]]

MN = MN or {}
MN.tickets = {}

local pending = {}   -- [id] = ticket
local nextId = 1
local nextSpawn = 0

---Time-of-day and weather multiplier. Clients report the world state; the worst
---a forged report can do is nudge a price by a fixed configured factor.
---@return number
local function multiplier()
    local hour = tonumber(GlobalState.mnHour) or 14
    local weather = GlobalState.mnWeather or 'CLEAR'
    local value = 1.0

    if hour >= 10 and hour < 20 then
        value = value * Config.Tickets.multipliers.day
    elseif hour >= 22 or hour < 6 then
        value = value * Config.Tickets.multipliers.night
    end

    if weather == 'EXTRASUNNY' or weather == 'CLEAR' then
        value = value * Config.Tickets.multipliers.hot
    end

    return value
end

---@return table|nil
local function create()
    local pick = MN.pick(Recipes.ticketPool)
    if not pick then return nil end

    local product = Products.get(pick.item)
    if not product or not product.price then return nil end

    local count = math.random(1, math.max(pick.maxCount or 1, 1))
    local unit = math.floor(product.price * multiplier())
    local now = os.time()

    local ticket = {
        id = nextId,
        item = pick.item,
        label = product.label,
        count = count,
        unit = unit,
        price = unit * count,
        created = now,
        expires = now + Config.Tickets.expiry,
    }
    nextId = nextId + 1
    return ticket
end

---@return table[]
function MN.tickets.list()
    local out = {}
    for _, ticket in pairs(pending) do out[#out + 1] = ticket end
    table.sort(out, function(a, b) return a.created < b.created end)
    return out
end

---@return number
function MN.tickets.count()
    return MN.count(pending)
end

local function sync()
    MN.broadcastToStaff('mangonazlet:client:tickets', MN.tickets.list())
end

if Config.Tickets.enabled then
    CreateThread(function()
        while true do
            Wait(1000)
            local now = os.time()

            local expired = 0
            for id, ticket in pairs(pending) do
                if ticket.expires <= now then
                    pending[id] = nil
                    expired = expired + 1
                    if Config.Tickets.expirePenalty > 0 then
                        MN.business.debit(Config.Tickets.expirePenalty)
                    end
                end
            end
            if expired > 0 then
                MN.broadcastToStaff('mangonazlet:client:notify', 'order_expired', 'error', {})
                sync()
            end

            local staff = #MN.onDutyList()
            if staff >= Config.Tickets.minStaffOnDuty then
                if nextSpawn == 0 then
                    nextSpawn = now + math.random(Config.Tickets.spawnDelay.min, Config.Tickets.spawnDelay.max)
                end

                if now >= nextSpawn and MN.tickets.count() < Config.Tickets.maxPending then
                    local ticket = create()
                    if ticket then
                        pending[ticket.id] = ticket
                        sync()
                        MN.broadcastToStaff('mangonazlet:client:notify', 'order_new', 'inform',
                            { ('%sx %s'):format(ticket.count, Products.label(ticket.item)) })
                    end
                    nextSpawn = now + math.random(Config.Tickets.spawnDelay.min, Config.Tickets.spawnDelay.max)
                end
            else
                nextSpawn = 0
            end
        end
    end)
end

lib.callback.register('mangonazlet:server:tickets', function(source)
    if not MN.rateLimit(source, 'tickets', 1000) then return {} end

    local player = MN.getPlayer(source)
    if not player or player.job.name ~= Permissions.job then return {} end
    return MN.tickets.list()
end)

lib.callback.register('mangonazlet:server:serveTicket', function(source, ticketId)
    local src = source

    if not MN.rateLimit(src, 'serve', 1000) then
        MN.notify(src, 'cooldown', 'error')
        return false
    end

    local player = MN.gate(src, MN.PERM.REGISTER, Locations.shop.register.coords, Config.Billing.maxDistance + 2.0)
    if not player then return false end

    local id = MN.int(ticketId, 1)
    local ticket = id and pending[id]
    if not ticket then
        MN.notify(src, 'order_expired', 'error')
        return false
    end

    if ticket.expires <= os.time() then
        pending[id] = nil
        sync()
        MN.notify(src, 'order_expired', 'error')
        return false
    end

    local ok, ratio = MN.crafting.takeProduct(src, ticket.item, ticket.count)
    if not ok then
        MN.notify(src, 'order_missing', 'error')
        return false
    end

    -- Remove before paying out, so one ticket can never be served twice.
    pending[id] = nil
    sync()

    local total = math.floor(ticket.price * ratio)
    local tip = MN.business.settle(src, player, total, ticket.item, ticket.count, MN.CHANNEL.ORDER)

    if ratio < 0.95 then MN.notify(src, 'melt_warning', 'warning') end
    MN.notify(src, 'order_done', 'success', MN.money(tip))
    return true
end)

-- World state report used only for the price multiplier above.
RegisterNetEvent('mangonazlet:server:world', function(hour, weather)
    local src = source
    if not MN.rateLimit(src, 'world', 30000) then return end

    local h = MN.int(hour, 0, 23)
    if h then GlobalState.mnHour = h end
    if type(weather) == 'string' and #weather <= 20 and weather:match('^%u+$') then
        GlobalState.mnWeather = weather
    end
end)
