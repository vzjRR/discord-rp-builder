// طبقة قاعدة البيانات — SQLite محلي (better-sqlite3) على مسار DB_PATH.
// المنصة تشتغل الحين داخل نفس سيرفس welcome-bot على Railway، وتخزّن ملف
// قاعدة البيانات على الـ Volume المرفق بذاك السيرفس (افتراضيًا /data).
// ننشئ الجداول تلقائيًا أول ما السيرفر يشتغل (idempotent — آمن يتكرر).

const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');

const DB_PATH = process.env.SQLITE_PATH || '/data/admin.db';
fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

function migrate() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS admins (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      pin_hash TEXT NOT NULL,
      is_owner INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_login_at TEXT
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      admin_id INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      actor_admin_id INTEGER REFERENCES admins(id) ON DELETE SET NULL,
      actor_name TEXT NOT NULL,
      action TEXT NOT NULL,
      detail TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS access_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      discord_user_id TEXT NOT NULL,
      note TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      resolved_at TEXT,
      resolved_by_admin_id INTEGER REFERENCES admins(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS pin_resets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      admin_id INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
      code_hash TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL,
      used_at TEXT
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_admin ON sessions(admin_id);
    CREATE INDEX IF NOT EXISTS idx_pin_resets_admin ON pin_resets(admin_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_access_requests_status ON access_requests(status, created_at DESC);
  `);

  // SQLite ما فيه "ADD COLUMN IF NOT EXISTS" مضمونة بكل النسخ — نتأكد يدويًا
  const adminCols = db.prepare('PRAGMA table_info(admins)').all().map((c) => c.name);
  if (!adminCols.includes('discord_user_id')) {
    db.exec('ALTER TABLE admins ADD COLUMN discord_user_id TEXT');
  }
  if (!adminCols.includes('must_change_pin')) {
    db.exec('ALTER TABLE admins ADD COLUMN must_change_pin INTEGER NOT NULL DEFAULT 0');
  }

  // صلاحيات الحساب — JSON. NULL تعني حسابًا أُنشئ قبل الميزة، ويُعامل
  // على أنه كامل الصلاحيات (شرحه في src/permissions.js).
  if (!adminCols.includes('permissions')) {
    db.exec('ALTER TABLE admins ADD COLUMN permissions TEXT');
  }

  // جلسة نشأت عن استرجاع رقم سري منسي: صاحبها لا يعرف رقمه الحالي، فيُسمح
  // لها وحدها بوضع رقم جديد دون طلب القديم — ولا تفعل شيئًا سوى ذلك.
  const sessionCols = db.prepare('PRAGMA table_info(sessions)').all().map((c) => c.name);
  if (!sessionCols.includes('via_recovery')) {
    db.exec('ALTER TABLE sessions ADD COLUMN via_recovery INTEGER NOT NULL DEFAULT 0');
  }
}

module.exports = { db, migrate };
