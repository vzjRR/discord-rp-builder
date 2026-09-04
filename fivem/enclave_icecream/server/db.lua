---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — طبقة قاعدة البيانات
    ---------------------------------------
    تُنشئ الجداول تلقائيًا عند أول تشغيل (migration).
    لو Config.UseDatabase = false، كل شيء يشتغل من الذاكرة والدوال ترجّع فورًا.
]]

IC = IC or {}
IC.db = {}

local enabled = Config.UseDatabase and IC.hasResource('oxmysql')
IC.db.enabled = enabled

if Config.UseDatabase and not IC.hasResource('oxmysql') then
    IC.warn('Config.UseDatabase = true لكن oxmysql غير مشتغل — سنعمل من الذاكرة فقط.')
end

-- ────────────────────────────────────────────────────────────
-- إنشاء الجداول
-- ────────────────────────────────────────────────────────────
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `icecream_business` (
        `branch` VARCHAR(50) NOT NULL,
        `balance` BIGINT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`branch`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `icecream_employees` (
        `citizenid` VARCHAR(64) NOT NULL,
        `branch` VARCHAR(50) NOT NULL DEFAULT 'vespucci',
        `name` VARCHAR(100) NOT NULL DEFAULT '',
        `grade` INT NOT NULL DEFAULT 0,
        `sales` INT NOT NULL DEFAULT 0,
        `earnings` BIGINT NOT NULL DEFAULT 0,
        `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`citizenid`),
        KEY `idx_branch` (`branch`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `icecream_sales` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `branch` VARCHAR(50) NOT NULL,
        `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
        `item` VARCHAR(64) NOT NULL DEFAULT '',
        `qty` INT NOT NULL DEFAULT 1,
        `amount` INT NOT NULL DEFAULT 0,
        `kind` VARCHAR(20) NOT NULL DEFAULT 'order',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_branch_date` (`branch`, `created_at`),
        KEY `idx_citizen` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    [[CREATE TABLE IF NOT EXISTS `icecream_logs` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `branch` VARCHAR(50) NOT NULL DEFAULT '',
        `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
        `action` VARCHAR(40) NOT NULL,
        `detail` TEXT,
        `amount` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_branch_date` (`branch`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],

    -- الوضع standalone فقط: تخزين الوظائف لأن ما في فريمويرك يخزنها
    [[CREATE TABLE IF NOT EXISTS `icecream_standalone_jobs` (
        `identifier` VARCHAR(100) NOT NULL,
        `grade` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
}

---ينشئ الجداول ويرجّع true عند النجاح
---@return boolean
function IC.db.migrate()
    if not enabled then return false end
    for i = 1, #SCHEMA do
        local ok, err = pcall(MySQL.query.await, SCHEMA[i])
        if not ok then
            IC.warn('فشل إنشاء الجداول: %s', tostring(err))
            IC.warn('نفّذ sql/install.sql يدويًا ثم أعد تشغيل المورد.')
            enabled = false
            IC.db.enabled = false
            return false
        end
    end
    IC.debug('تم التحقق من جداول قاعدة البيانات.')
    return true
end

-- ────────────────────────────────────────────────────────────
-- حساب الشركة
-- ────────────────────────────────────────────────────────────

---@param branch string
---@return number|nil balance
function IC.db.loadBalance(branch)
    if not enabled then return nil end
    local row = MySQL.single.await('SELECT balance FROM icecream_business WHERE branch = ?', { branch })
    if row then return tonumber(row.balance) or 0 end
    MySQL.insert.await(
        'INSERT INTO icecream_business (branch, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = balance',
        { branch, Config.Economy.startingBalance }
    )
    return Config.Economy.startingBalance
end

---@param branch string
---@param balance number
function IC.db.saveBalance(branch, balance)
    if not enabled then return end
    MySQL.update('INSERT INTO icecream_business (branch, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = VALUES(balance)',
        { branch, math.floor(balance) })
end

-- ────────────────────────────────────────────────────────────
-- الموظفون
-- ────────────────────────────────────────────────────────────

---@param citizenid string
---@param branch string
---@param name string
---@param grade number
function IC.db.upsertEmployee(citizenid, branch, name, grade)
    if not enabled or not citizenid then return end
    MySQL.update([[INSERT INTO icecream_employees (citizenid, branch, name, grade)
                   VALUES (?, ?, ?, ?)
                   ON DUPLICATE KEY UPDATE branch = VALUES(branch), name = VALUES(name), grade = VALUES(grade)]],
        { citizenid, branch, name or '', math.floor(grade or 0) })
end

---@param citizenid string
function IC.db.removeEmployee(citizenid)
    if not enabled or not citizenid then return end
    MySQL.update('DELETE FROM icecream_employees WHERE citizenid = ?', { citizenid })
end

---@param branch string
---@return table[]
function IC.db.getEmployees(branch)
    if not enabled then return {} end
    return MySQL.query.await(
        'SELECT citizenid, name, grade, sales, earnings, hired_at FROM icecream_employees WHERE branch = ? ORDER BY grade DESC, name ASC',
        { branch }) or {}
end

---@param citizenid string
---@param salesDelta number
---@param earningsDelta number
function IC.db.addEmployeeStats(citizenid, salesDelta, earningsDelta)
    if not enabled or not citizenid then return end
    MySQL.update('UPDATE icecream_employees SET sales = sales + ?, earnings = earnings + ? WHERE citizenid = ?',
        { math.floor(salesDelta or 0), math.floor(earningsDelta or 0), citizenid })
end

-- ────────────────────────────────────────────────────────────
-- المبيعات والإحصائيات
-- ────────────────────────────────────────────────────────────

---@param branch string
---@param citizenid string
---@param item string
---@param qty number
---@param amount number
---@param kind string  'order' | 'bill' | 'truck'
function IC.db.recordSale(branch, citizenid, item, qty, amount, kind)
    if not enabled then return end
    MySQL.insert('INSERT INTO icecream_sales (branch, citizenid, item, qty, amount, kind) VALUES (?, ?, ?, ?, ?, ?)',
        { branch, citizenid or '', item or '', math.floor(qty or 1), math.floor(amount or 0), kind or 'order' })
end

---إحصائيات الفرع
---@param branch string
---@return table
function IC.db.getStats(branch)
    local empty = { today = 0, week = 0, orders = 0, topItem = nil, topEmployee = nil }
    if not enabled then return empty end

    local today = MySQL.single.await([[SELECT COALESCE(SUM(amount),0) AS total, COUNT(*) AS cnt
        FROM icecream_sales WHERE branch = ? AND created_at >= CURDATE()]], { branch })
    local week = MySQL.single.await([[SELECT COALESCE(SUM(amount),0) AS total
        FROM icecream_sales WHERE branch = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)]], { branch })
    local topItem = MySQL.single.await([[SELECT item, SUM(qty) AS qty FROM icecream_sales
        WHERE branch = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND item <> ''
        GROUP BY item ORDER BY qty DESC LIMIT 1]], { branch })
    local topEmployee = MySQL.single.await([[SELECT s.citizenid, COALESCE(e.name, s.citizenid) AS name,
        SUM(s.amount) AS total FROM icecream_sales s
        LEFT JOIN icecream_employees e ON e.citizenid = s.citizenid
        WHERE s.branch = ? AND s.created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND s.citizenid <> ''
        GROUP BY s.citizenid, e.name ORDER BY total DESC LIMIT 1]], { branch })

    return {
        today = tonumber(today and today.total) or 0,
        orders = tonumber(today and today.cnt) or 0,
        week = tonumber(week and week.total) or 0,
        topItem = topItem and topItem.item or nil,
        topItemQty = tonumber(topItem and topItem.qty) or 0,
        topEmployee = topEmployee and topEmployee.name or nil,
        topEmployeeTotal = tonumber(topEmployee and topEmployee.total) or 0,
    }
end

---مبيعات موظف واحد اليوم
---@param branch string
---@param citizenid string
---@return number
function IC.db.getEmployeeToday(branch, citizenid)
    if not enabled or not citizenid then return 0 end
    local row = MySQL.single.await([[SELECT COALESCE(SUM(amount),0) AS total FROM icecream_sales
        WHERE branch = ? AND citizenid = ? AND created_at >= CURDATE()]], { branch, citizenid })
    return tonumber(row and row.total) or 0
end

-- ────────────────────────────────────────────────────────────
-- اللوقات (نسخة قاعدة البيانات — مستقلة عن ويبهوك ديسكورد)
-- ────────────────────────────────────────────────────────────

---@param branch string
---@param citizenid string
---@param action string
---@param detail string
---@param amount? number
function IC.db.log(branch, citizenid, action, detail, amount)
    if not enabled then return end
    MySQL.insert('INSERT INTO icecream_logs (branch, citizenid, action, detail, amount) VALUES (?, ?, ?, ?, ?)',
        { branch or '', citizenid or '', action, detail or '', math.floor(amount or 0) })
end

-- ────────────────────────────────────────────────────────────
-- الوضع standalone
-- ────────────────────────────────────────────────────────────

function IC.db.loadStandaloneJobs()
    if not enabled or IC.framework ~= 'standalone' then return end
    local rows = MySQL.query.await('SELECT identifier, grade FROM icecream_standalone_jobs') or {}
    for i = 1, #rows do
        IC.standaloneJobs[rows[i].identifier] = { grade = tonumber(rows[i].grade) or 0 }
    end
    IC.debug('حمّلت %s وظيفة (standalone)', #rows)
end

---@param identifier string
---@param grade number|nil  -- nil = فصل
function IC.db.saveStandaloneJob(identifier, grade)
    if not enabled or IC.framework ~= 'standalone' or not identifier then return end
    if grade == nil then
        MySQL.update('DELETE FROM icecream_standalone_jobs WHERE identifier = ?', { identifier })
    else
        MySQL.update('INSERT INTO icecream_standalone_jobs (identifier, grade) VALUES (?, ?) ON DUPLICATE KEY UPDATE grade = VALUES(grade)',
            { identifier, math.floor(grade) })
    end
end
