// طبقة قاعدة البيانات — SQLite محلي (better-sqlite3)، نفس فكرة
// admin-panel/src/db.js: نُنشئ الجداول تلقائيًا أول ما البوت يشتغل
// (idempotent — آمن يتكرر).
//
// قاعدة منفصلة عمدًا عن admin.db (قاعدة المنصة) — نفس فلسفة
// activityTracker.js: البوت هو الكاتب الوحيد لمعظم الجداول هنا (المنصة
// تقرأ)، فخلل في كتابة البوت لا يمسّ حسابات المنصة ولا جلساتها. الاستثناء
// الوحيد: التعديل اليدوي للنقاط من المنصة (إضافة/خصم/تصفير) يكتب هنا
// مباشرة أيضًا — لا مفر منه، فالمنصة REST-only ولا تتحدث مع عملية البوت
// بأي طريق آخر. WAL يجعل هذا آمنًا بين عمليتين مختلفتين.

const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

// نفس أسلوب zeroTolerance.js: نشتق المسار من EVENTS_DB_PATH (يبقى بنفس
// مجلد بيانات welcome-bot/المنصة تلقائيًا) بدل افتراض /data دايمًا.
const DB_PATH =
  process.env.POINTS_DB_PATH ||
  (process.env.EVENTS_DB_PATH
    ? path.join(path.dirname(process.env.EVENTS_DB_PATH), 'points.db')
    : '/data/points.db');

fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

function migrate() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      discord_user_id TEXT PRIMARY KEY,
      username TEXT NOT NULL,
      display_name TEXT NOT NULL,
      total_points INTEGER NOT NULL DEFAULT 0,
      weekly_points INTEGER NOT NULL DEFAULT 0,
      monthly_points INTEGER NOT NULL DEFAULT 0,
      total_images INTEGER NOT NULL DEFAULT 0,
      weekly_images INTEGER NOT NULL DEFAULT 0,
      monthly_images INTEGER NOT NULL DEFAULT 0,
      first_point_at INTEGER,
      last_point_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );

    -- سجل كل رسالة تمت معالجتها — هذا ما يمنع احتساب نفس الرسالة مرتين
    -- (إعادة تشغيل، duplicate event، إعادة تشغيل مسح الأرشيف).
    CREATE TABLE IF NOT EXISTS processed_messages (
      message_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      channel_id TEXT NOT NULL,
      image_count INTEGER NOT NULL,
      points_awarded INTEGER NOT NULL,
      week_key TEXT NOT NULL,
      month_key TEXT NOT NULL,
      source TEXT NOT NULL DEFAULT 'live',
      message_created_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_processed_messages_user ON processed_messages(user_id);
    CREATE INDEX IF NOT EXISTS idx_processed_messages_week ON processed_messages(week_key);
    CREATE INDEX IF NOT EXISTS idx_processed_messages_month ON processed_messages(month_key);

    -- أرشيف كل فترة أسبوعية/شهرية بعد انتهائها (rollover) — يبقى للأبد
    -- حتى بعد تصفير weekly_points/monthly_points بجدول users.
    CREATE TABLE IF NOT EXISTS period_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      period_type TEXT NOT NULL,
      period_key TEXT NOT NULL,
      user_id TEXT NOT NULL,
      username TEXT NOT NULL,
      display_name TEXT NOT NULL,
      points INTEGER NOT NULL,
      images INTEGER NOT NULL,
      rank_position INTEGER NOT NULL,
      period_start INTEGER NOT NULL,
      period_end INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      UNIQUE(period_type, period_key, user_id)
    );
    CREATE INDEX IF NOT EXISTS idx_period_history_lookup ON period_history(period_type, period_key);

    -- الفترة الحالية (أسبوع/شهر) — يقرأها rollover.js عند كل إقلاع ليكتشف
    -- هل فاتته فترة كامل وهو مطفي، بدل الاعتماد على setTimeout الذي ينسى
    -- كل شيء عند إعادة التشغيل.
    CREATE TABLE IF NOT EXISTS bot_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      action_type TEXT NOT NULL,
      user_id TEXT,
      actor_id TEXT,
      message_id TEXT,
      channel_id TEXT,
      points_delta INTEGER,
      details TEXT,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log(user_id);
  `);
}

module.exports = { db, migrate, DB_PATH };
