-- ============================================================
--  enclave_icecream — جداول قاعدة البيانات
-- ------------------------------------------------------------
--  المورد ينشئ هذه الجداول تلقائيًا عند أول تشغيل.
--  نفّذ هذا الملف يدويًا فقط إذا ظهر تحذير "فشل إنشاء الجداول"
--  (عادةً بسبب صلاحيات ناقصة لمستخدم قاعدة البيانات).
-- ============================================================

-- حساب الشركة لكل فرع
CREATE TABLE IF NOT EXISTS `icecream_business` (
    `branch`     VARCHAR(50) NOT NULL,
    `balance`    BIGINT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`branch`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- سجل الموظفين وإحصائياتهم التراكمية
CREATE TABLE IF NOT EXISTS `icecream_employees` (
    `citizenid` VARCHAR(64) NOT NULL,
    `branch`    VARCHAR(50) NOT NULL DEFAULT 'vespucci',
    `name`      VARCHAR(100) NOT NULL DEFAULT '',
    `grade`     INT NOT NULL DEFAULT 0,
    `sales`     INT NOT NULL DEFAULT 0,
    `earnings`  BIGINT NOT NULL DEFAULT 0,
    `hired_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    KEY `idx_branch` (`branch`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- كل عملية بيع (طلب زبون / فاتورة لاعب / بيع متنقل)
CREATE TABLE IF NOT EXISTS `icecream_sales` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `branch`     VARCHAR(50) NOT NULL,
    `citizenid`  VARCHAR(64) NOT NULL DEFAULT '',
    `item`       VARCHAR(64) NOT NULL DEFAULT '',
    `qty`        INT NOT NULL DEFAULT 1,
    `amount`     INT NOT NULL DEFAULT 0,
    `kind`       VARCHAR(20) NOT NULL DEFAULT 'order',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_branch_date` (`branch`, `created_at`),
    KEY `idx_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- سجل العمليات المالية والإدارية (نسخة دائمة مستقلة عن ديسكورد)
CREATE TABLE IF NOT EXISTS `icecream_logs` (
    `id`         INT NOT NULL AUTO_INCREMENT,
    `branch`     VARCHAR(50) NOT NULL DEFAULT '',
    `citizenid`  VARCHAR(64) NOT NULL DEFAULT '',
    `action`     VARCHAR(40) NOT NULL,
    `detail`     TEXT,
    `amount`     INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_branch_date` (`branch`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- الوضع standalone فقط (بلا فريمويرك): تخزين الوظائف
CREATE TABLE IF NOT EXISTS `icecream_standalone_jobs` (
    `identifier` VARCHAR(100) NOT NULL,
    `grade`      INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- رصيد افتتاحي للفرع الافتراضي (عدّل المبلغ كما تشاء)
INSERT INTO `icecream_business` (`branch`, `balance`)
VALUES ('vespucci', 25000)
ON DUPLICATE KEY UPDATE `branch` = `branch`;
