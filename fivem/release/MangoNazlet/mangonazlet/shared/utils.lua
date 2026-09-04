---@diagnostic disable: lowercase-global
--[[ MangoNazlet — Shared helpers. Pure functions, safe on both sides. ]]

MN = MN or {}

---@param name string
---@return boolean
function MN.hasResource(name)
    return GetResourceState(name):find('start') ~= nil
end

local function fmt(message, ...)
    if select('#', ...) == 0 then return message end
    local ok, out = pcall(string.format, message, ...)
    return ok and out or message
end

function MN.print(message, ...)
    print(('[%s] %s'):format(MN.RESOURCE, fmt(message, ...)))
end

function MN.warn(message, ...)
    print(('[%s] ^3WARN^7 %s'):format(MN.RESOURCE, fmt(message, ...)))
end

function MN.error(message, ...)
    print(('[%s] ^1ERROR^7 %s'):format(MN.RESOURCE, fmt(message, ...)))
end

function MN.debug(message, ...)
    if not (Config and Config.Debug) then return end
    print(('[%s] ^5DEBUG^7 %s'):format(MN.RESOURCE, fmt(message, ...)))
end

---Thousands-separated integer. Never returns nil.
---@param amount any
---@return string
function MN.money(amount)
    local n = math.floor(tonumber(amount) or 0)
    local sign = n < 0 and '-' or ''
    local digits = tostring(math.abs(n))
    local out = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    out = out:gsub('^,', '')
    return sign .. out
end

---Strict integer parse with bounds. Returns nil on anything unusable, which is
---how every value arriving from a client is filtered before use.
---@param value any
---@param min? number
---@param max? number
---@return number|nil
function MN.int(value, min, max)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    n = math.floor(n)
    if min and n < min then return nil end
    if max and n > max then return nil end
    return n
end

---Weighted random pick over a list whose entries carry a `weight` field.
---@param pool table
---@return table|nil
function MN.pick(pool)
    if not pool or #pool == 0 then return nil end
    local total = 0
    for i = 1, #pool do total = total + (pool[i].weight or 1) end
    if total <= 0 then return pool[1] end
    local roll, acc = math.random() * total, 0
    for i = 1, #pool do
        acc = acc + (pool[i].weight or 1)
        if roll <= acc then return pool[i] end
    end
    return pool[#pool]
end

---Shallow copy. Used where a config table must not be mutated by a caller.
---@param source table
---@return table
function MN.copy(source)
    local out = {}
    for k, v in pairs(source) do out[k] = v end
    return out
end

---Count entries of a non-sequential table.
---@param t table
---@return number
function MN.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

---Trim and cap a free-text string coming from a player.
---@param value any
---@param maxLength number
---@return string
function MN.text(value, maxLength)
    if type(value) ~= 'string' then return '' end
    return (value:gsub('^%s+', ''):gsub('%s+$', '')):sub(1, maxLength)
end
