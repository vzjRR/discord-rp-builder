-- ═══════════════════════════════════════════════════════════════
--  MangoNazlet — database schema
--  ---------------------------------------------------------------
--  You normally do NOT need to run this. The resource creates every
--  table itself on first start.
--
--  Run it by hand only if the console printed:
--      [mangonazlet] ERROR could not create tables: ...
--  which means the MySQL user the server connects with lacks CREATE
--  rights. Nothing here drops or alters existing data.
-- ═══════════════════════════════════════════════════════════════

-- Business account, one row per shop.
CREATE TABLE IF NOT EXISTS `mn_business` (
    `shop`       VARCHAR(50) NOT NULL,
    `balance`    BIGINT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`shop`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Employees and their lifetime figures.
CREATE TABLE IF NOT EXISTS `mn_staff` (
    `citizenid` VARCHAR(64) NOT NULL,
    `shop`      VARCHAR(50) NOT NULL DEFAULT 'vespucci',
    `name`      VARCHAR(100) NOT NULL DEFAULT '',
    `grade`     INT NOT NULL DEFAULT 0,
    `sales`     INT NOT NULL DEFAULT 0,
    `earnings`  BIGINT NOT NULL DEFAULT 0,
    `hired_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    KEY `idx_shop` (`shop`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- What is actually on the shelf for walk-in customers to buy.
CREATE TABLE IF NOT EXISTS `mn_stock` (
    `shop`       VARCHAR(50) NOT NULL,
    `item`       VARCHAR(64) NOT NULL,
    `quantity`   INT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`shop`, `item`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Every completed sale, for statistics and reporting.
CREATE TABLE IF NOT EXISTS `mn_sales` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `shop`       VARCHAR(50) NOT NULL,
    `citizenid`  VARCHAR(64) NOT NULL DEFAULT '',
    `item`       VARCHAR(64) NOT NULL DEFAULT '',
    `quantity`   INT NOT NULL DEFAULT 1,
    `amount`     INT NOT NULL DEFAULT 0,
    `channel`    VARCHAR(20) NOT NULL DEFAULT 'order',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_shop_date` (`shop`, `created_at`),
    KEY `idx_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Audit trail: money movements, staff changes and rejected requests.
CREATE TABLE IF NOT EXISTS `mn_logs` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `shop`       VARCHAR(50) NOT NULL DEFAULT '',
    `citizenid`  VARCHAR(64) NOT NULL DEFAULT '',
    `action`     VARCHAR(40) NOT NULL,
    `detail`     TEXT,
    `amount`     INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_shop_date` (`shop`, `created_at`),
    KEY `idx_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Placements saved with /mn:place, so moving the shop never edits a file.
CREATE TABLE IF NOT EXISTS `mn_locations` (
    `shop`   VARCHAR(50) NOT NULL,
    `anchor` VARCHAR(40) NOT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `w` DOUBLE NOT NULL DEFAULT 0,
    PRIMARY KEY (`shop`, `anchor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Only used when no framework is installed.
CREATE TABLE IF NOT EXISTS `mn_standalone_jobs` (
    `identifier` VARCHAR(100) NOT NULL,
    `grade`      INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Opening balance. Harmless to re-run: it will not overwrite a live balance.
INSERT INTO `mn_business` (`shop`, `balance`) VALUES ('vespucci', 25000)
ON DUPLICATE KEY UPDATE `shop` = `shop`;
