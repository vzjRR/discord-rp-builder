---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — لوقات Discord Webhook
    -----------------------------------------
    يقرأ الرابط من convar `icecream_webhook` أولًا، ثم Config.Server.webhook.
    ⚠️ لا تضع رابط الويبهوك في الكود لو المستودع عام — استخدم الـ convar.
]]

IC = IC or {}
IC.logs = {}

local webhook = GetConvar('icecream_webhook', '')
if webhook == '' then webhook = Config.Server.webhook or '' end

local enabled = webhook ~= '' and webhook:find('^https://') ~= nil
if Config.Server.webhook ~= '' and not enabled then
    IC.warn('رابط الويبهوك غير صالح — لوقات ديسكورد معطّلة.')
end

-- طابور بسيط يمنع تجاوز حد Discord (5 طلبات / ثانيتين لكل ويبهوك)
local queue = {}
local sending = false

local function flush()
    if sending then return end
    sending = true
    CreateThread(function()
        while #queue > 0 do
            local payload = table.remove(queue, 1)
            PerformHttpRequest(webhook, function(status, _, _)
                if status ~= 200 and status ~= 204 then
                    IC.debug('ويبهوك رجّع %s', tostring(status))
                end
            end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
            Wait(700)
        end
        sending = false
    end)
end

---يرسل إيمبد لديسكورد
---@param opts { title: string, description?: string, color?: number, fields?: table, footer?: string }
function IC.logs.send(opts)
    if not enabled then return end

    local embed = {
        title = opts.title,
        description = opts.description,
        color = opts.color or Config.Server.colors.sale,
        fields = opts.fields,
        footer = { text = opts.footer or ('%s • %s'):format(Config.Server.webhookName, os.date('%Y-%m-%d %H:%M:%S')) },
    }

    queue[#queue + 1] = {
        username = Config.Server.webhookName,
        embeds = { embed },
    }
    flush()
end

---يبني حقل إيمبد
---@param name string
---@param value any
---@param inline? boolean
local function field(name, value, inline)
    return { name = name, value = tostring(value), inline = inline ~= false }
end

-- ────────────────────────────────────────────────────────────
-- اللوقات الجاهزة
-- ────────────────────────────────────────────────────────────

---@param player table
---@param branch string
---@param item string
---@param qty number
---@param amount number
---@param kind string
function IC.logs.sale(player, branch, item, qty, amount, kind)
    IC.db.log(branch, player and player.citizenid, 'sale',
        ('%s x%s (%s)'):format(item, qty, kind), amount)
    if not Config.Server.logEverySale then return end
    IC.logs.send({
        title = '🍦 عملية بيع',
        color = Config.Server.colors.sale,
        fields = {
            field('الموظف', player and player.name or 'غير معروف'),
            field('الفرع', branch),
            field('المنتج', ('%s x%s'):format(item, qty)),
            field('المبلغ', '$' .. IC.money(amount)),
            field('النوع', kind),
        },
    })
end

---@param player table|nil
---@param branch string
---@param action 'deposit'|'withdraw'|'supply'|'paycheck'|'truck_fee'
---@param amount number
---@param balance number
function IC.logs.money(player, branch, action, amount, balance)
    IC.db.log(branch, player and player.citizenid, action, ('رصيد بعدها: %s'):format(balance), amount)
    if not Config.Server.logMoney then return end

    local titles = {
        deposit = '💰 إيداع في حساب الشركة',
        withdraw = '💸 سحب من حساب الشركة',
        supply = '📦 شراء مواد خام',
        paycheck = '🧾 صرف رواتب',
        truck_fee = '🚚 رسوم عربة',
        supply_run = '🚛 جولة توريد',
    }

    IC.logs.send({
        title = titles[action] or ('عملية مالية: ' .. action),
        color = Config.Server.colors.money,
        fields = {
            field('الموظف', player and player.name or 'النظام'),
            field('المعرّف', player and player.citizenid or '—'),
            field('الفرع', branch),
            field('المبلغ', '$' .. IC.money(amount)),
            field('الرصيد بعدها', '$' .. IC.money(balance)),
        },
    })
end

---@param actor table
---@param target table|{ name: string, citizenid: string }
---@param branch string
---@param action 'hire'|'fire'|'promote'
---@param detail string
function IC.logs.employee(actor, target, branch, action, detail)
    IC.db.log(branch, actor and actor.citizenid, action,
        ('%s → %s'):format(target and target.name or '?', detail or ''), 0)
    if not Config.Server.logEmployees then return end

    local titles = { hire = '✅ توظيف', fire = '❌ فصل', promote = '⬆️ تغيير رتبة' }
    IC.logs.send({
        title = titles[action] or action,
        color = Config.Server.colors.employee,
        fields = {
            field('نفّذها', actor and actor.name or 'النظام'),
            field('الموظف', target and target.name or '?'),
            field('المعرّف', target and target.citizenid or '—'),
            field('الفرع', branch),
            field('التفاصيل', detail or '—', false),
        },
    })
end

---محاولة غش مكتشفة
---@param src number
---@param reason string
---@param detail? string
function IC.logs.exploit(src, reason, detail)
    local name = GetPlayerName(src) or ('ID %s'):format(src)
    IC.warn('محاولة مشبوهة من %s (%s): %s %s', name, src, reason, detail or '')
    IC.db.log('', IC.getIdentifier(src) or '', 'exploit', ('%s | %s'):format(reason, detail or ''), 0)
    if not Config.Server.logExploits then return end

    IC.logs.send({
        title = '🚨 محاولة مشبوهة',
        color = Config.Server.colors.warning,
        fields = {
            field('اللاعب', ('%s (ID %s)'):format(name, src)),
            field('المعرّف', IC.getIdentifier(src) or '—'),
            field('السبب', reason),
            field('التفاصيل', detail or '—', false),
        },
    })
end
