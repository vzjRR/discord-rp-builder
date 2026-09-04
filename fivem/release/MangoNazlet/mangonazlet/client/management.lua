---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Management menu: money, staff, statistics.
]]

MN = MN or {}

local function reopen()
    SetTimeout(150, MN.openManagement)
end

---@param mode 'deposit'|'withdraw'
---@param balance number
local function moneyDialog(mode, balance)
    local deposit = mode == 'deposit'

    local input = lib.inputDialog(deposit and T('boss_deposit') or T('boss_withdraw'), { {
        type = 'number',
        label = T('boss_amount'),
        required = true,
        min = 1,
        max = deposit and 10000000 or math.max(balance, 1),
        icon = 'dollar-sign',
    } })
    if not input or not input[1] then return end

    local result = lib.callback.await(
        deposit and 'mangonazlet:server:deposit' or 'mangonazlet:server:withdraw',
        false, math.floor(input[1]))

    if result then reopen() end
end

---@param member table
---@param data table
local function staffActions(member, data)
    local grades = {}
    for i = 1, #data.grades do
        grades[#grades + 1] = { value = data.grades[i].level, label = data.grades[i].label }
    end

    lib.registerContext({
        id = 'mn_staff_member',
        title = member.name ~= '' and member.name or member.citizenid,
        menu = 'mn_staff',
        position = Config.UI.contextPosition,
        options = {
            {
                title = T('boss_rank'),
                description = member.gradeLabel,
                icon = 'arrow-up-right-dots',
                disabled = #grades == 0 or member.isOwner,
                onSelect = function()
                    local input = lib.inputDialog(T('boss_rank'), { {
                        type = 'select', label = T('boss_rank_sel'),
                        required = true, default = member.grade, options = grades,
                    } })
                    if not input or input[1] == nil then return end

                    local ok = lib.callback.await('mangonazlet:server:setGrade', false,
                        member.citizenid, math.floor(input[1]))
                    if ok then reopen() end
                end,
            },
            {
                title = T('boss_fire'),
                icon = 'user-minus',
                iconColor = '#c0392b',
                disabled = member.isOwner,
                onSelect = function()
                    local answer = lib.alertDialog({
                        header = T('boss_fire'),
                        content = ('%s — %s'):format(member.name, member.gradeLabel),
                        centered = true, cancel = true,
                    })
                    if answer ~= 'confirm' then return end

                    local ok = lib.callback.await('mangonazlet:server:fire', false, member.citizenid)
                    if ok then reopen() end
                end,
            },
        },
    })
    lib.showContext('mn_staff_member')
end

---@param data table
local function staffList(data)
    local options = {}

    for i = 1, #(data.staff or {}) do
        local member = data.staff[i]

        options[#options + 1] = {
            title = member.name ~= '' and member.name or member.citizenid,
            description = member.gradeLabel,
            icon = member.online and (member.onduty and 'circle-check' or 'circle-user') or 'circle-minus',
            iconColor = member.online
                and (member.onduty and Config.UI.theme.leaf or Config.UI.theme.mango)
                or '#6b7280',
            arrow = true,
            metadata = {
                { label = T('stats_orders'), value = tostring(member.sales or 0) },
                { label = T('stats_you'), value = ('%s%s'):format(T('currency'), MN.money(member.earnings or 0)) },
            },
            onSelect = function() staffActions(member, data) end,
        }
    end

    if #options == 0 then
        options[1] = { title = T('stats_none'), icon = 'user-slash', readOnly = true }
    end

    lib.registerContext({
        id = 'mn_staff',
        title = T('boss_staff'),
        menu = 'mn_management',
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('mn_staff')
end

---@return number|nil
local function nearestPlayer()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDistance

    for _, playerId in ipairs(GetActivePlayers()) do
        local other = GetPlayerPed(playerId)
        if other ~= ped and DoesEntityExist(other) then
            local distance = #(coords - GetEntityCoords(other))
            if distance <= 8.0 and (not closestDistance or distance < closestDistance) then
                closest, closestDistance = GetPlayerServerId(playerId), distance
            end
        end
    end
    return closest
end

local function hireDialog()
    local input = lib.inputDialog(T('boss_hire'), { {
        type = 'number', label = T('boss_player'), default = nearestPlayer(),
        required = true, min = 1, icon = 'user-plus',
    } })
    if not input or not input[1] then return end

    local ok = lib.callback.await('mangonazlet:server:hire', false, math.floor(input[1]))
    if ok then reopen() end
end

function MN.openManagement()
    if not MN.checkAccess(MN.PERM.MANAGE) then return end

    local data = lib.callback.await('mangonazlet:server:management', false)
    if type(data) ~= 'table' then
        MN.notify(T('error_generic'), 'error')
        return
    end

    local currency = T('currency')

    lib.registerContext({
        id = 'mn_management',
        title = T('boss_title'),
        description = ('%s: %s%s'):format(T('boss_balance'), currency, MN.money(data.balance)),
        position = Config.UI.contextPosition,
        options = {
            {
                title = T('boss_balance'),
                description = currency .. MN.money(data.balance),
                icon = 'sack-dollar',
                readOnly = true,
            },
            {
                title = T('boss_deposit'),
                icon = 'arrow-down-to-line',
                iconColor = Config.UI.theme.leaf,
                onSelect = function() moneyDialog('deposit', data.balance) end,
            },
            {
                title = T('boss_withdraw'),
                icon = 'arrow-up-from-line',
                iconColor = Config.UI.theme.mango,
                onSelect = function() moneyDialog('withdraw', data.balance) end,
            },
            {
                title = T('boss_staff'),
                description = T('boss_staff_d', #(data.staff or {})),
                icon = 'users',
                arrow = true,
                onSelect = function() staffList(data) end,
            },
            {
                title = T('boss_hire'),
                icon = 'user-plus',
                onSelect = hireDialog,
            },
            {
                title = T('boss_stats'),
                icon = 'chart-line',
                arrow = true,
                onSelect = function() MN.openStats('mn_management') end,
            },
        },
    })
    lib.showContext('mn_management')
end
