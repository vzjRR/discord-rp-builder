---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Discord logging.

    Reads the webhook from the `mangonazlet_webhook` convar first so the URL
    never has to live in a file. Everything logged here is ALSO written to the
    mn_logs table, so an owner with no webhook still has a full audit trail.
]]

MN = MN or {}
MN.logs = {}

local webhook = GetConvar('mangonazlet_webhook', '')
if webhook == '' then webhook = Config.Server.webhook or '' end

local enabled = webhook ~= '' and webhook:find('^https://') ~= nil
if webhook ~= '' and not enabled then
    MN.warn('the configured Discord webhook is not a valid https URL — Discord logging is off.')
end

-- Discord allows roughly 5 requests per 2 seconds per webhook; this queue keeps
-- a busy shop from ever hitting that ceiling.
local queue, draining = {}, false

local function drain()
    if draining then return end
    draining = true

    CreateThread(function()
        while #queue > 0 do
            local payload = table.remove(queue, 1)
            PerformHttpRequest(webhook, function(status)
                if status ~= 200 and status ~= 204 then
                    MN.debug('webhook responded %s', tostring(status))
                end
            end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
            Wait(700)
        end
        draining = false
    end)
end

---@param name string
---@param value any
---@param inline? boolean
local function field(name, value, inline)
    return { name = name, value = tostring(value), inline = inline ~= false }
end

---@param opts { title: string, description?: string, colour?: number, fields?: table }
function MN.logs.send(opts)
    if not enabled then return end

    queue[#queue + 1] = {
        username = Config.Server.webhookName,
        embeds = { {
            title = opts.title,
            description = opts.description,
            color = opts.colour or Config.Server.colours.sale,
            fields = opts.fields,
            footer = { text = ('%s • %s'):format(MN.BRAND, os.date('%Y-%m-%d %H:%M:%S')) },
        } },
    }
    drain()
end

---A completed sale through any channel.
function MN.logs.sale(player, shop, item, quantity, amount, channel)
    MN.db.log(shop, player and player.citizenid, 'sale',
        ('%s x%s via %s'):format(item, quantity, channel), amount)

    if not Config.Server.logSales then return end
    MN.logs.send({
        title = 'Sale',
        colour = Config.Server.colours.sale,
        fields = {
            field('Staff', player and player.name or 'counter'),
            field('Item', ('%s x%s'):format(item, quantity)),
            field('Amount', '$' .. MN.money(amount)),
            field('Channel', channel),
        },
    })
end

---Any movement of business money.
function MN.logs.money(player, shop, action, amount, balance)
    MN.db.log(shop, player and player.citizenid, action,
        ('balance after: %s'):format(balance), amount)

    if not Config.Server.logMoney then return end

    local titles = {
        deposit = 'Deposit', withdraw = 'Withdrawal', supply = 'Ingredient purchase',
        payroll = 'Payroll', truck_fee = 'Truck fee', supply_run = 'Supply run payout',
    }

    MN.logs.send({
        title = titles[action] or action,
        colour = Config.Server.colours.money,
        fields = {
            field('Staff', player and player.name or 'system'),
            field('Citizen ID', player and player.citizenid or '—'),
            field('Amount', '$' .. MN.money(amount)),
            field('Balance after', '$' .. MN.money(balance)),
        },
    })
end

---Hiring, firing, rank changes.
function MN.logs.staff(actor, target, shop, action, detail)
    MN.db.log(shop, actor and actor.citizenid, action,
        ('%s → %s'):format(target and target.name or '?', detail or ''), 0)

    if not Config.Server.logStaff then return end

    local titles = { hire = 'Hired', fire = 'Fired', rank = 'Rank changed' }
    MN.logs.send({
        title = titles[action] or action,
        colour = Config.Server.colours.staff,
        fields = {
            field('By', actor and actor.name or 'system'),
            field('Employee', target and target.name or '?'),
            field('Citizen ID', target and target.citizenid or '—'),
            field('Detail', detail or '—', false),
        },
    })
end

---A rejected request. Called from MN.reject.
function MN.logs.security(src, reason, detail)
    MN.logs.send({
        title = 'Rejected request',
        colour = Config.Server.colours.warning,
        fields = {
            field('Player', ('%s (%s)'):format(GetPlayerName(src) or '?', tostring(src))),
            field('Identifier', MN.identifier(src) or '—'),
            field('Reason', reason),
            field('Detail', detail or '—', false),
        },
    })
end

---Installation summary, posted once per start so the owner can see it worked.
function MN.logs.install(lines)
    if not enabled then return end
    MN.logs.send({
        title = 'MangoNazlet started',
        colour = Config.Server.colours.money,
        description = table.concat(lines, '\n'),
    })
end
