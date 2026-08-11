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

    CREATE INDEX IF NOT EXISTS idx_sessions_admin ON sessions(admin_id);
    CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC);
  `);
}

module.exports = { db, migrate };
