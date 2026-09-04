---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — منيو البوس (عميل)
    -------------------------------------
    الرصيد، الإيداع/السحب، إدارة الموظفين، والإحصائيات.
    كل إجراء يُنفَّذ عبر callback ويُعاد التحقق منه سيرفريًا.
]]

IC = IC or {}
IC.client = IC.client or {}

local function reopen(branch)
    -- إعادة الفتح بعد أي إجراء لتحديث الأرقام
    SetTimeout(150, function() IC.client.openBossMenu(branch) end)
end

-- ────────────────────────────────────────────────────────────
-- إيداع وسحب
-- ────────────────────────────────────────────────────────────

local function moneyDialog(branch, mode, balance)
    local isDeposit = mode == 'deposit'

    local input = lib.inputDialog(isDeposit and L('boss_deposit') or L('boss_withdraw'), {
        {
            type = 'number',
            label = L('boss_amount_input'),
            required = true,
            min = 1,
            max = isDeposit and 10000000 or math.max(balance, 1),
            icon = 'dollar-sign',
        },
    })

    if not input or not input[1] then return end

    local amount = math.floor(input[1])
    local event = isDeposit and 'icecream:server:bossDeposit' or 'icecream:server:bossWithdraw'
    local result = lib.callback.await(event, false, branch.id, amount)

    if result then reopen(branch) end
end

-- ────────────────────────────────────────────────────────────
-- الموظفون
-- ────────────────────────────────────────────────────────────

local function employeeActions(branch, employee, data)
    local gradeOptions = {}
    for grade = 0, math.min(data.maxPromoteGrade or 0, IC.maxGrade()) do
        local info = Config.Job.grades[grade]
        if info then
            gradeOptions[#gradeOptions + 1] = { value = grade, label = info.label }
        end
    end

    lib.registerContext({
        id = 'icecream_employee',
        title = employee.name,
        menu = 'icecream_employees',
        position = Config.UI.contextPosition,
        options = {
            {
                title = L('boss_promote'),
                description = employee.gradeLabel,
                icon = 'arrow-up-right-dots',
                disabled = #gradeOptions == 0,
                onSelect = function()
                    local input = lib.inputDialog(L('boss_promote'), {
                        {
                            type = 'select',
                            label = L('boss_grade_input'),
                            required = true,
                            default = employee.grade,
                            options = gradeOptions,
                        },
                    })
                    if not input or input[1] == nil then return end
                    local ok = lib.callback.await('icecream:server:bossPromote', false,
                        branch.id, employee.citizenid, math.floor(input[1]))
                    if ok then reopen(branch) end
                end,
            },
            {
                title = L('boss_fire'),
                icon = 'user-minus',
                iconColor = '#f87171',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = L('boss_fire'),
                        content = ('%s — %s'):format(employee.name, employee.gradeLabel),
                        centered = true,
                        cancel = true,
                    })
                    if confirm ~= 'confirm' then return end
                    local ok = lib.callback.await('icecream:server:bossFire', false,
                        branch.id, employee.citizenid)
                    if ok then reopen(branch) end
                end,
            },
        },
    })
    lib.showContext('icecream_employee')
end

local function openEmployees(branch, data)
    local options = {}

    for i = 1, #(data.employees or {}) do
        local employee = data.employees[i]
        options[#options + 1] = {
            title = employee.name ~= '' and employee.name or employee.citizenid,
            description = employee.gradeLabel,
            icon = employee.online and (employee.onduty and 'circle-check' or 'circle-user') or 'circle-minus',
            iconColor = employee.online and (employee.onduty and '#4ade80' or '#facc15') or '#6b7280',
            arrow = true,
            metadata = {
                { label = L('stats_orders'), value = tostring(employee.sales or 0) },
                { label = L('stats_your_sales'), value = ('$%s'):format(IC.money(employee.earnings or 0)) },
            },
            onSelect = function() employeeActions(branch, employee, data) end,
        }
    end

    if #options == 0 then
        options[1] = { title = L('stats_none'), readOnly = true, icon = 'user-slash' }
    end

    lib.registerContext({
        id = 'icecream_employees',
        title = L('boss_employees'),
        menu = 'icecream_boss',
        position = Config.UI.contextPosition,
        options = options,
    })
    lib.showContext('icecream_employees')
end

-- ────────────────────────────────────────────────────────────
-- التوظيف
-- ────────────────────────────────────────────────────────────

local function hireDialog(branch)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDist

    for _, playerId in ipairs(GetActivePlayers()) do
        local target = GetPlayerPed(playerId)
        if target ~= ped and DoesEntityExist(target) then
            local dist = #(coords - GetEntityCoords(target))
            if dist <= 8.0 and (not closestDist or dist < closestDist) then
                closest, closestDist = GetPlayerServerId(playerId), dist
            end
        end
    end

    local input = lib.inputDialog(L('boss_hire'), {
        {
            type = 'number',
            label = L('boss_player_input'),
            default = closest,
            required = true,
            min = 1,
            icon = 'user-plus',
        },
    })

    if not input or not input[1] then return end

    local ok = lib.callback.await('icecream:server:bossHire', false, branch.id, math.floor(input[1]))
    if ok then reopen(branch) end
end

-- ────────────────────────────────────────────────────────────
-- القائمة الرئيسية
-- ────────────────────────────────────────────────────────────

---@param branch table
function IC.client.openBossMenu(branch)
    if not IC.checkAccess('isBoss') then return end

    local data = lib.callback.await('icecream:server:getBossData', false, branch.id)
    if not data then
        IC.notify(L('error_generic'), 'error')
        return
    end

    lib.registerContext({
        id = 'icecream_boss',
        title = L('boss_menu_title'),
        description = ('%s: $%s'):format(L('boss_balance'), IC.money(data.balance)),
        position = Config.UI.contextPosition,
        options = {
            {
                title = L('boss_balance'),
                description = L('boss_balance_desc', IC.money(data.balance)),
                icon = 'sack-dollar',
                readOnly = true,
            },
            {
                title = L('boss_deposit'),
                icon = 'arrow-down-to-line',
                iconColor = '#4ade80',
                onSelect = function() moneyDialog(branch, 'deposit', data.balance) end,
            },
            {
                title = L('boss_withdraw'),
                icon = 'arrow-up-from-line',
                iconColor = '#facc15',
                onSelect = function() moneyDialog(branch, 'withdraw', data.balance) end,
            },
            {
                title = L('boss_employees'),
                description = L('boss_employees_desc', #(data.employees or {})),
                icon = 'users',
                arrow = true,
                onSelect = function() openEmployees(branch, data) end,
            },
            {
                title = L('boss_hire'),
                icon = 'user-plus',
                onSelect = function() hireDialog(branch) end,
            },
            {
                title = L('boss_stats'),
                icon = 'chart-line',
                arrow = true,
                onSelect = function() IC.client.openStats(branch, 'icecream_boss') end,
            },
        },
    })
    lib.showContext('icecream_boss')
end
