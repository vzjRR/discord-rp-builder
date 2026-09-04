---@diagnostic disable: lowercase-global
--[[
    MangoNazlet — Persistence.

    Tables are created automatically on first start; the owner never runs SQL by
    hand. sql/install.sql exists only as a manual fallback for hosts whose DB
    user lacks CREATE rights.

    Every function degrades safely when no database is available: the resource
    keeps working in memory for the session and says so once on start.
]]

MN = MN or {}
MN.db = { ready = false }

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `mn_business` (
        `shop` VARCHAR(50) NOT NULL,
        `balance` BIGINT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `mn_staff` (
        `citizenid` VARCHAR(64) NOT NULL,
        `shop` VARCHAR(50) NOT NULL DEFAULT 'vespucci',
        `name` VARCHAR(100) NOT NULL DEFAULT '',
        `grade` INT NOT NULL DEFAULT 0,
        `sales` INT NOT NULL DEFAULT 0,
        `earnings` BIGINT NOT NULL DEFAULT 0,
        `hired_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`citizenid`),
        KEY `idx_shop` (`shop`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    -- Sellable stock behind the counter. Server-authoritative: the NUI can only
    -- ever ask to buy, never to change what is here.
    [[CREATE TABLE IF NOT EXISTS `mn_stock` (
        `shop` VARCHAR(50) NOT NULL,
        `item` VARCHAR(64) NOT NULL,
        `quantity` INT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`shop`, `item`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `mn_sales` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(50) NOT NULL,
        `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
        `item` VARCHAR(64) NOT NULL DEFAULT '',
        `quantity` INT NOT NULL DEFAULT 1,
        `amount` INT NOT NULL DEFAULT 0,
        `channel` VARCHAR(20) NOT NULL DEFAULT 'order',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_shop_date` (`shop`, `created_at`),
        KEY `idx_citizen` (`citizenid`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    [[CREATE TABLE IF NOT EXISTS `mn_logs` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `shop` VARCHAR(50) NOT NULL DEFAULT '',
        `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
        `action` VARCHAR(40) NOT NULL,
        `detail` TEXT,
        `amount` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_shop_date` (`shop`, `created_at`),
        KEY `idx_action` (`action`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    -- Placements saved by /mn:place, so relocating never means editing a file.
    [[CREATE TABLE IF NOT EXISTS `mn_locations` (
        `shop` VARCHAR(50) NOT NULL,
        `anchor` VARCHAR(40) NOT NULL,
        `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
        `w` DOUBLE NOT NULL DEFAULT 0,
        PRIMARY KEY (`shop`, `anchor`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],

    -- Standalone mode only: the resource stores employment itself.
    [[CREATE TABLE IF NOT EXISTS `mn_standalone_jobs` (
        `identifier` VARCHAR(100) NOT NULL,
        `grade` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;]],
}

---Create the schema. Safe to run on every start.
---@return boolean
function MN.db.migrate()
    if not MN.has.oxMysql then
        MN.warn('oxmysql is not running — MangoNazlet will keep state in memory only for this session.')
        return false
    end

    for i = 1, #SCHEMA do
        local ok, err = pcall(MySQL.query.await, SCHEMA[i])
        if not ok then
            MN.error('could not create tables: %s', tostring(err))
            MN.error('run sql/install.sql once against your database, then restart this resource.')
            return false
        end
    end

    MN.db.ready = true
    MN.debug('database schema verified')
    return true
end

-- ═══════════════════════════════════════════════════════════════
-- Business balance
-- ═══════════════════════════════════════════════════════════════

---@param shop string
---@return number|nil
function MN.db.loadBalance(shop)
    if not MN.db.ready then return nil end
    local row = MySQL.single.await('SELECT balance FROM mn_business WHERE shop = ?', { shop })
    if row then return tonumber(row.balance) or 0 end

    MySQL.insert.await(
        'INSERT INTO mn_business (shop, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = balance',
        { shop, Config.Economy.openingBalance })
    return Config.Economy.openingBalance
end

---@param shop string
---@param balance number
function MN.db.saveBalance(shop, balance)
    if not MN.db.ready then return end
    MySQL.update(
        'INSERT INTO mn_business (shop, balance) VALUES (?, ?) ON DUPLICATE KEY UPDATE balance = VALUES(balance)',
        { shop, math.floor(balance) })
end

-- ═══════════════════════════════════════════════════════════════
-- Shop stock (what walk-in customers can buy)
-- ═══════════════════════════════════════════════════════════════

---@param shop string
---@return table<string, number>
function MN.db.loadStock(shop)
    local stock = {}
    if not MN.db.ready then return stock end
    local rows = MySQL.query.await('SELECT item, quantity FROM mn_stock WHERE shop = ?', { shop }) or {}
    for i = 1, #rows do
        stock[rows[i].item] = tonumber(rows[i].quantity) or 0
    end
    return stock
end

---@param shop string
---@param item string
---@param quantity number
function MN.db.saveStock(shop, item, quantity)
    if not MN.db.ready then return end
    MySQL.update(
        'INSERT INTO mn_stock (shop, item, quantity) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE quantity = VALUES(quantity)',
        { shop, item, math.max(math.floor(quantity), 0) })
end

-- ═══════════════════════════════════════════════════════════════
-- Staff
-- ═══════════════════════════════════════════════════════════════

function MN.db.upsertStaff(citizenid, shop, name, grade)
    if not MN.db.ready or not citizenid then return end
    MySQL.update([[INSERT INTO mn_staff (citizenid, shop, name, grade) VALUES (?, ?, ?, ?)
                   ON DUPLICATE KEY UPDATE shop = VALUES(shop), name = VALUES(name), grade = VALUES(grade)]],
        { citizenid, shop, name or '', math.floor(grade or 0) })
end

function MN.db.removeStaff(citizenid)
    if not MN.db.ready or not citizenid then return end
    MySQL.update('DELETE FROM mn_staff WHERE citizenid = ?', { citizenid })
end

---@param shop string
---@return table[]
function MN.db.staff(shop)
    if not MN.db.ready then return {} end
    return MySQL.query.await([[SELECT citizenid, name, grade, sales, earnings, hired_at
        FROM mn_staff WHERE shop = ? ORDER BY grade DESC, name ASC]], { shop }) or {}
end

function MN.db.addStaffStats(citizenid, salesDelta, earningsDelta)
    if not MN.db.ready or not citizenid then return end
    MySQL.update('UPDATE mn_staff SET sales = sales + ?, earnings = earnings + ? WHERE citizenid = ?',
        { math.floor(salesDelta or 0), math.floor(earningsDelta or 0), citizenid })
end

function MN.db.setStaffGrade(citizenid, grade)
    if not MN.db.ready or not citizenid then return end
    MySQL.update('UPDATE mn_staff SET grade = ? WHERE citizenid = ?', { math.floor(grade), citizenid })
end

-- ═══════════════════════════════════════════════════════════════
-- Sales and statistics
-- ═══════════════════════════════════════════════════════════════

function MN.db.recordSale(shop, citizenid, item, quantity, amount, channel)
    if not MN.db.ready then return end
    MySQL.insert('INSERT INTO mn_sales (shop, citizenid, item, quantity, amount, channel) VALUES (?, ?, ?, ?, ?, ?)',
        { shop, citizenid or '', item or '', math.floor(quantity or 1), math.floor(amount or 0), channel or 'order' })
end

---@param shop string
---@return table
function MN.db.stats(shop)
    local empty = { today = 0, week = 0, orders = 0 }
    if not MN.db.ready then return empty end

    local today = MySQL.single.await([[SELECT COALESCE(SUM(amount),0) AS total, COUNT(*) AS cnt
        FROM mn_sales WHERE shop = ? AND created_at >= CURDATE()]], { shop })
    local week = MySQL.single.await([[SELECT COALESCE(SUM(amount),0) AS total
        FROM mn_sales WHERE shop = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)]], { shop })
    local topItem = MySQL.single.await([[SELECT item, SUM(quantity) AS qty FROM mn_sales
        WHERE shop = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND item <> ''
        GROUP BY item ORDER BY qty DESC LIMIT 1]], { shop })
    local topStaff = MySQL.single.await([[SELECT s.citizenid, COALESCE(e.name, s.citizenid) AS name,
        SUM(s.amount) AS total FROM mn_sales s
        LEFT JOIN mn_staff e ON e.citizenid = s.citizenid
        WHERE s.shop = ? AND s.created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY) AND s.citizenid <> ''
        GROUP BY s.citizenid, e.name ORDER BY total DESC LIMIT 1]], { shop })

    return {
        today = tonumber(today and today.total) or 0,
        orders = tonumber(today and today.cnt) or 0,
        week = tonumber(week and week.total) or 0,
        topItem = topItem and topItem.item or nil,
        topItemQty = tonumber(topItem and topItem.qty) or 0,
        topStaff = topStaff and topStaff.name or nil,
        topStaffTotal = tonumber(topStaff and topStaff.total) or 0,
    }
end

---@param shop string
---@param citizenid string
---@return number
function MN.db.staffToday(shop, citizenid)
    if not MN.db.ready or not citizenid then return 0 end
    local row = MySQL.single.await([[SELECT COALESCE(SUM(amount),0) AS total FROM mn_sales
        WHERE shop = ? AND citizenid = ? AND created_at >= CURDATE()]], { shop, citizenid })
    return tonumber(row and row.total) or 0
end

-- ═══════════════════════════════════════════════════════════════
-- Audit log
-- ═══════════════════════════════════════════════════════════════

function MN.db.log(shop, citizenid, action, detail, amount)
    if not MN.db.ready then return end
    MySQL.insert('INSERT INTO mn_logs (shop, citizenid, action, detail, amount) VALUES (?, ?, ?, ?, ?)',
        { shop or '', citizenid or '', action, detail or '', math.floor(amount or 0) })
end

-- ═══════════════════════════════════════════════════════════════
-- Saved placements
-- ═══════════════════════════════════════════════════════════════

---@param shop string
---@return table
function MN.db.loadPlacements(shop)
    local out = {}
    if not MN.db.ready then return out end
    local rows = MySQL.query.await('SELECT anchor, x, y, z, w FROM mn_locations WHERE shop = ?', { shop }) or {}
    for i = 1, #rows do
        out[rows[i].anchor] = { x = rows[i].x + 0.0, y = rows[i].y + 0.0, z = rows[i].z + 0.0, w = rows[i].w + 0.0 }
    end
    return out
end

function MN.db.savePlacement(shop, anchor, x, y, z, w)
    if not MN.db.ready then return false end
    MySQL.update([[INSERT INTO mn_locations (shop, anchor, x, y, z, w) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), w = VALUES(w)]],
        { shop, anchor, x, y, z, w or 0.0 })
    return true
end

function MN.db.clearPlacements(shop)
    if not MN.db.ready then return end
    MySQL.update('DELETE FROM mn_locations WHERE shop = ?', { shop })
end

-- ═══════════════════════════════════════════════════════════════
-- Standalone employment
-- ═══════════════════════════════════════════════════════════════

---@return table<string, number>
function MN.db.loadStandaloneJobs()
    local out = {}
    if not MN.db.ready then return out end
    local rows = MySQL.query.await('SELECT identifier, grade FROM mn_standalone_jobs') or {}
    for i = 1, #rows do out[rows[i].identifier] = tonumber(rows[i].grade) or 0 end
    return out
end

---@param identifier string
---@param grade number|nil  -- nil removes employment
function MN.db.saveStandaloneJob(identifier, grade)
    if not MN.db.ready or not identifier then return end
    if grade == nil then
        MySQL.update('DELETE FROM mn_standalone_jobs WHERE identifier = ?', { identifier })
    else
        MySQL.update([[INSERT INTO mn_standalone_jobs (identifier, grade) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE grade = VALUES(grade)]], { identifier, math.floor(grade) })
    end
end
