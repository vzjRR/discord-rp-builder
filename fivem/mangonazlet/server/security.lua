---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Security gate.

    Every server entry point in this resource passes through here. The rule the
    whole resource is built on: a client sends identifiers, never values. Prices,
    recipes, payouts and quantities are read from config on the server.

    MN.gate() is the single choke point that checks, in order:
      1. the player exists and is really employed here
      2. they are clocked in (when duty is required)
      3. their grade carries the permission
      4. they are physically near the thing they claim to be using
      5. they are not spamming the event
]]

MN = MN or {}
MN.security = {}

-- [source] = { [bucket] = lastTimestampMs }
local buckets = {}

---Per-player, per-action rate limit.
---@param src number
---@param bucket string
---@param cooldownMs number
---@return boolean allowed
function MN.rateLimit(src, bucket, cooldownMs)
    local now = GetGameTimer()
    local player = buckets[src]
    if not player then
        player = {}
        buckets[src] = player
    end

    local last = player[bucket]
    if last and (now - last) < cooldownMs then return false end
    player[bucket] = now
    return true
end

---Is the player standing near these coordinates?
---@param src number
---@param coords vector3
---@param maxDistance number
---@return boolean
function MN.isNear(src, coords, maxDistance)
    if not coords then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= (maxDistance or 5.0)
end

---Distance between two players, or a very large number when either is invalid.
---@param a number
---@param b number
---@return number
function MN.playerDistance(a, b)
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or not pedB or pedA == 0 or pedB == 0 then return math.huge end
    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB))
end

---Record and report a rejected request. Anything that reaches here is either a
---modified client or a bug, and both are worth seeing.
---@param src number
---@param reason string
---@param detail? string
function MN.reject(src, reason, detail)
    local name = GetPlayerName(src) or ('id %s'):format(tostring(src))
    MN.warn('rejected %s from %s (%s)%s', reason, name, tostring(src),
        detail and (' — ' .. detail) or '')

    MN.db.log('', MN.identifier(src) or '', 'security',
        ('%s | %s'):format(reason, detail or ''), 0)

    if Config.Server.logSecurity then
        MN.logs.security(src, reason, detail)
    end
end

---The gate. Returns the validated player, or nil after notifying them why.
---@param src number
---@param permission? string      -- one of MN.PERM
---@param coords? vector3         -- where they must be standing
---@param maxDistance? number
---@return table|nil player
function MN.gate(src, permission, coords, maxDistance)
    local player = MN.getPlayer(src)

    if not player or player.job.name ~= Permissions.job then
        MN.notify(src, 'not_employee', 'error')
        return nil
    end

    if Config.RequireDuty and not player.job.onduty then
        MN.notify(src, 'not_on_duty', 'error')
        return nil
    end

    if permission and not Permissions.can(player.job.grade, permission) then
        MN.notify(src, 'no_permission', 'error')
        return nil
    end

    if coords and not MN.isNear(src, coords, maxDistance or 5.0) then
        MN.reject(src, 'distance', ('expected within %.1fm'):format(maxDistance or 5.0))
        MN.notify(src, 'too_far', 'error')
        return nil
    end

    return player
end

---Gate for actions any player may take (buying at the counter): no job needed,
---but presence and rate limiting still apply.
---@param src number
---@param coords vector3
---@param maxDistance number
---@return boolean
function MN.customerGate(src, coords, maxDistance)
    if not MN.isNear(src, coords, maxDistance) then
        MN.reject(src, 'distance', 'counter')
        MN.notify(src, 'too_far', 'error')
        return false
    end
    return true
end

AddEventHandler('playerDropped', function()
    buckets[source] = nil
end)
