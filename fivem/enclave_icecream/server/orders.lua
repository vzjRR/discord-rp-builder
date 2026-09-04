---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — طلبات الزبائن (NPC)
    ---------------------------------------
    السيرفر هو من يولّد الطلبات ويحسب أسعارها ويؤكد تسليمها.
    العميل يستقبل قائمة الطلبات فقط ليعرضها ويشغّل الزبون NPC محليًا.
]]

IC = IC or {}
IC.orders = {}

-- [branchId] = { [orderId] = order }
local pending = {}
local nextId = 1

---شكل الطلب:
---  { id, branch, item, count, price, createdAt, expiresAt, label }

-- ────────────────────────────────────────────────────────────
-- أدوات
-- ────────────────────────────────────────────────────────────

---مضاعف السعر حسب الوقت والطقس داخل اللعبة
---@return number
local function priceMultiplier()
    local mult = 1.0
    local hour = tonumber(GetConvar('icecream_forced_hour', '')) or nil

    -- ساعة اللعبة تُقرأ من متغير حالة عام يضبطه العميل الأول (fallback: النهار)
    hour = hour or GlobalState.icecreamHour or 14
    local weather = GlobalState.icecreamWeather or 'CLEAR'

    if hour >= 10 and hour < 20 then
        mult = mult * Config.Orders.multipliers.dayTime
    elseif hour >= 22 or hour < 6 then
        mult = mult * Config.Orders.multipliers.night
    end

    if weather == 'EXTRASUNNY' or weather == 'CLEAR' then
        mult = mult * Config.Orders.multipliers.hotWeather
    end

    return mult
end

---يولّد طلبًا جديدًا لفرع
---@param branchId string
---@return table|nil
local function createOrder(branchId)
    local pick = IC.weightedPick(Recipes.OrderPool)
    if not pick then return nil end

    local recipe = Recipes.byResult[pick.item]
    if not recipe then return nil end

    local count = math.random(1, math.max(pick.maxCount or 1, 1))
    local unitPrice = math.floor(recipe.sellPrice * priceMultiplier())
    local now = os.time()

    local order = {
        id = nextId,
        branch = branchId,
        item = pick.item,
        label = recipe.label,
        count = count,
        unitPrice = unitPrice,
        price = unitPrice * count,
        createdAt = now,
        expiresAt = now + Config.Orders.expiry,
    }
    nextId = nextId + 1
    return order
end

---يرجّع الطلبات المعلّقة لفرع كقائمة مرتّبة
---@param branchId string
---@return table[]
function IC.orders.list(branchId)
    local out = {}
    for _, order in pairs(pending[branchId] or {}) do
        out[#out + 1] = order
    end
    table.sort(out, function(a, b) return a.createdAt < b.createdAt end)
    return out
end

---@param branchId string
---@return number
function IC.orders.countPending(branchId)
    local count = 0
    for _ in pairs(pending[branchId] or {}) do count = count + 1 end
    return count
end

---يبثّ قائمة الطلبات المحدّثة لكل من على الدوام
---@param branchId string
local function syncOrders(branchId)
    IC.server.broadcast(branchId, 'icecream:client:syncOrders', branchId, IC.orders.list(branchId))
end

-- ────────────────────────────────────────────────────────────
-- حلقة التوليد وانتهاء الصلاحية
-- ────────────────────────────────────────────────────────────

if Config.Orders.enabled then
    CreateThread(function()
        -- عدّاد الانتظار لكل فرع على حدة
        local nextSpawn = {}

        while true do
            Wait(1000)
            local now = os.time()

            for i = 1, #Locations.Branches do
                local branchId = Locations.Branches[i].id
                pending[branchId] = pending[branchId] or {}

                -- حذف المنتهية
                local expiredCount = 0
                for id, order in pairs(pending[branchId]) do
                    if order.expiresAt <= now then
                        pending[branchId][id] = nil
                        expiredCount = expiredCount + 1
                        if Config.Orders.expirePenalty > 0 then
                            IC.society.take(branchId, Config.Orders.expirePenalty)
                        end
                    end
                end
                if expiredCount > 0 then
                    IC.server.broadcast(branchId, 'icecream:client:notify', 'order_expired', 'error', {})
                    syncOrders(branchId)
                end

                -- توليد طلب جديد
                local onDuty = IC.server.countOnDuty(branchId)
                if onDuty >= Config.Orders.minEmployeesOnDuty then
                    if not nextSpawn[branchId] then
                        nextSpawn[branchId] = now + math.random(Config.Orders.spawnDelay.min, Config.Orders.spawnDelay.max)
                    end

                    if now >= nextSpawn[branchId]
                        and IC.orders.countPending(branchId) < Config.Orders.maxPending then
                        local order = createOrder(branchId)
                        if order then
                            pending[branchId][order.id] = order
                            syncOrders(branchId)
                            IC.server.broadcast(branchId, 'icecream:client:notify', 'order_new', 'inform',
                                { ('%sx %s'):format(order.count, order.label) })
                        end
                        nextSpawn[branchId] = now + math.random(Config.Orders.spawnDelay.min, Config.Orders.spawnDelay.max)
                    end
                else
                    nextSpawn[branchId] = nil
                end
            end
        end
    end)
end

-- ────────────────────────────────────────────────────────────
-- التسليم
-- ────────────────────────────────────────────────────────────

lib.callback.register('icecream:server:deliverOrder', function(source, branchId, orderId)
    local src = source

    if not IC.rateLimit(src, 'deliver', 1000) then
        IC.server.notify(src, 'cooldown', 'error')
        return false
    end

    local branch = IC.server.resolveBranch(branchId)
    if not branch then
        IC.logs.exploit(src, 'invalid_branch', tostring(branchId))
        return false
    end

    local player = IC.server.gate(src, 'canRegister', branch.register.coords, Config.Register.maxDistance + 2.0)
    if not player then return false end

    local id = IC.toInt(orderId, 1)
    local order = id and pending[branchId] and pending[branchId][id]
    if not order then
        IC.server.notify(src, 'order_expired', 'error')
        return false
    end

    if order.expiresAt <= os.time() then
        pending[branchId][id] = nil
        syncOrders(branchId)
        IC.server.notify(src, 'order_expired', 'error')
        return false
    end

    -- سحب المنتج مع حساب الذوبان
    local ok, ratio = IC.server.takeProduct(src, order.item, order.count)
    if not ok then
        IC.server.notify(src, 'order_missing', 'error')
        return false
    end

    -- الطلب صار مستلمًا — احذفه قبل الدفع حتى لا يُسلَّم مرتين
    pending[branchId][id] = nil
    syncOrders(branchId)

    local total = math.floor(order.price * ratio)
    local tip = IC.society.settleSale(branchId, src, player, total, order.item, order.count, 'order')

    if ratio < 0.95 then
        IC.server.notify(src, 'melt_warning', 'warning')
    end
    IC.server.notify(src, 'order_delivered', 'success', IC.money(tip))

    return true
end)

-- العميل يطلب مزامنة يدوية (عند فتح القائمة أو تسجيل الدوام)
lib.callback.register('icecream:server:getOrders', function(source, branchId)
    local player = IC.getPlayer(source)
    if not player or player.job.name ~= Config.Job.name then return {} end
    if not IC.server.resolveBranch(branchId) then return {} end
    return IC.orders.list(branchId)
end)

-- العميل يبلّغ السيرفر بساعة/طقس اللعبة (لحساب المضاعف) — تأثيره تجميلي فقط
RegisterNetEvent('icecream:server:reportWorld', function(hour, weather)
    local src = source
    if not IC.rateLimit(src, 'world', 30000) then return end
    local h = IC.toInt(hour, 0, 23)
    if h then GlobalState.icecreamHour = h end
    if type(weather) == 'string' and #weather <= 20 then
        GlobalState.icecreamWeather = weather
    end
end)
