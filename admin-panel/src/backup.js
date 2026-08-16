// نسخة احتياطية كاملة من حالة المنصة — كل ما لا يمكن إعادة توليده من الكود.
//
// كل ما تملكه المنصة يعيش على قرص المضيف: قاعدة الحسابات والجلسات وسجل
// النشاط، وقاعدة أحداث السيرفر التي يكتبها البوت، ونصوص الرسائل المعدّلة.
// الكود يُستنسخ من المستودع في أي وقت، وهذه لا. فمن غير نسخة احتياطية
// يعني إغلاقُ الاستضافة أو تلفُ القرص ضياعَ الحسابات والسجل بلا رجعة.
//
// قواعد SQLite لا تُنسخ بنسخ الملف نسخًا ساذجًا وهي قيد الاستعمال: قد
// تُلتقط في منتصف كتابة، أو يبقى جزء منها في ملف الـ WAL. لذلك نستعمل
// واجهة النسخ التي يوفّرها المحرّك نفسه (backup)، وهي تُخرج ملفًا متماسكًا
// ولو جرت كتابة أثناءها.

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const Database = require('better-sqlite3');
const { db } = require('./db');

const ADMIN_DB_PATH = process.env.SQLITE_PATH || '/data/admin.db';
const EVENTS_DB_PATH = process.env.EVENTS_DB_PATH || '/data/server-events.db';

const JSON_FILES = {
  'onboarding-message.json': process.env.ONBOARDING_MESSAGE_PATH || '/data/onboarding-message.json',
  'revocation-message.json': process.env.REVOCATION_MESSAGE_PATH || '/data/revocation-message.json',
  'message-templates.json': process.env.MESSAGE_TEMPLATES_PATH || '/data/message-templates.json',
};

/** ينسخ قاعدة SQLite نسخة متماسكة ويرجعها كبايتات. */
async function snapshotSqlite(sourcePath, liveHandle) {
  if (!fs.existsSync(sourcePath)) return null;
  const tmp = path.join(os.tmpdir(), `backup-${crypto.randomBytes(8).toString('hex')}.db`);
  try {
    if (liveHandle) {
      // القاعدة مفتوحة عندنا: نستعمل مقبضها فتخرج النسخة متماسكة
      await liveHandle.backup(tmp);
    } else {
      // قاعدة يكتبها البوت لا نحن: نفتحها للقراءة وننسخها بنفس الواجهة
      const handle = new Database(sourcePath, { readonly: true, fileMustExist: true });
      try {
        await handle.backup(tmp);
      } finally {
        handle.close();
      }
    }
    return fs.readFileSync(tmp);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

/**
 * يبني حزمة النسخ الاحتياطي كاملة.
 * الشكل JSON بمحتوى مُرمَّز base64 — يمرّ عبر HTTPS بلا عناء، ويُستعاد
 * بسكربت واحد على المضيف الجديد (scripts/restore-backup.js).
 */
async function buildBackup() {
  const files = {};
  const warnings = [];

  const adminDb = await snapshotSqlite(ADMIN_DB_PATH, db);
  if (adminDb) files['admin.db'] = adminDb.toString('base64');
  else warnings.push('لم تُوجد قاعدة المنصة — وهذا لا يقع في تشغيل سليم');

  try {
    const eventsDb = await snapshotSqlite(EVENTS_DB_PATH, null);
    if (eventsDb) files['server-events.db'] = eventsDb.toString('base64');
    else warnings.push('لم تُوجد قاعدة أحداث السيرفر بعد (تُنشأ عند أول حدث)');
  } catch (err) {
    warnings.push(`تعذّرت نسخة قاعدة الأحداث: ${err.message}`);
  }

  for (const [name, filePath] of Object.entries(JSON_FILES)) {
    if (!fs.existsSync(filePath)) continue; // غير معدّل، فالنص الافتراضي في الكود
    files[name] = fs.readFileSync(filePath).toString('base64');
  }

  // بصمة لكل ملف: تتيح التأكد أن ما وصل هو ما خرج، وأن الاستعادة تامّة
  const checksums = {};
  for (const [name, b64] of Object.entries(files)) {
    checksums[name] = crypto.createHash('sha256').update(Buffer.from(b64, 'base64')).digest('hex');
  }

  const counts = {};
  try {
    for (const t of ['admins', 'sessions', 'audit_log', 'access_requests']) {
      counts[t] = db.prepare(`SELECT COUNT(*) AS c FROM ${t}`).get().c;
    }
  } catch { /* إحصاء إرشادي فقط */ }

  return {
    version: 1,
    createdAt: new Date().toISOString(),
    counts,
    checksums,
    warnings,
    files,
  };
}

module.exports = { buildBackup, ADMIN_DB_PATH, EVENTS_DB_PATH, JSON_FILES };
