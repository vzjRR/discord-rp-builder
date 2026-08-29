// صفر تسامح: راجع config/zeroTolerance.js للتفاصيل والتحذير عن ترتيب
// الرولات. عدّاد المخالفات يُخزَّن في قاعدة SQLite منفصلة صغيرة (نفس فكرة
// activityTracker.js) فيبقى محفوظًا عبر إعادة التشغيل ورجوع العضو للسيرفر.

const fs = require('fs');
const path = require('path');
const cfg = require('../config/zeroTolerance');

const DB_PATH = process.env.ZERO_TOLERANCE_DB_PATH || '/data/zero-tolerance.db';

let db = null;

function init() {
  if (db) return db;
  try {
    const Database = require('better-sqlite3');
    fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    db.exec(`
      CREATE TABLE IF NOT EXISTS violations (
        user_id TEXT PRIMARY KEY,
        count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    `);
    return db;
  } catch (err) {
    console.error('⚠️  تعذّر فتح قاعدة صفر التسامح:', err.message);
    db = null;
    return null;
  }
}

// لو تعذّر فتح القاعدة، نعامل كل رسالة كأنها أول مخالفة (طرد لا حظر) بدل ما
// نوقف الميزة كاملة أو نحظر أحدًا بالخطأ اعتمادًا على عدّاد ضائع.
function recordViolation(userId) {
  const conn = init();
  if (!conn) return 1;

  conn
    .prepare(
      `INSERT INTO violations (user_id, count) VALUES (?, 1)
       ON CONFLICT(user_id) DO UPDATE SET count = count + 1, updated_at = datetime('now')`
    )
    .run(userId);

  return conn.prepare('SELECT count FROM violations WHERE user_id = ?').get(userId).count;
}

async function dmSafely(user, content) {
  try {
    await user.send({ content });
    return true;
  } catch (err) {
    // العضو مقفّل الخاص أو حاظر البوت — لا يجب أن يوقف الطرد/الحظر
    console.error(`⚠️  تعذّر إرسال إشعار صفر التسامح لـ ${user.id}:`, err.message);
    return false;
  }
}

async function enforce(message) {
  const guild = message.guild;
  const user = message.author;

  await message.delete().catch(() => {});

  const count = recordViolation(user.id);
  const willBan = count >= cfg.banAfter;

  // يُرسَل قبل الطرد/الحظر: بعد إزالته قد لا يبقى للبوت سيرفر مشترك معه،
  // فتفشل محاولة فتح المحادثة الخاصة بصمت.
  await dmSafely(user, willBan ? cfg.banMessage(guild, count, cfg.banAfter) : cfg.kickMessage(guild, count, cfg.banAfter));

  const reason = `صفر تسامح: مخالفة ${count}/${cfg.banAfter}`;

  try {
    if (willBan) {
      await guild.members.ban(user.id, { reason });
    } else {
      const member = message.member || (await guild.members.fetch(user.id).catch(() => null));
      if (!member) {
        console.warn(`صفر تسامح: العضو ${user.id} غادر قبل أن يُطرد.`);
        return;
      }
      await member.kick(reason);
    }
    console.log(`صفر تسامح: تم ${willBan ? 'حظر' : 'طرد'} ${user.tag} (مخالفة ${count}).`);
  } catch (err) {
    console.error(`⚠️  فشل إجراء صفر التسامح لـ ${user.id}:`, err.message);
  }
}

/** يربط الميزة بأحداث البوت. لا شيء يحدث لو channelId غير معرّف بالإعدادات. */
function register(client, guildId) {
  if (!cfg.channelId) return;

  client.on('messageCreate', (message) => {
    if (!message.guild || (guildId && message.guild.id !== guildId)) return;
    if (message.author?.bot) return;
    if (message.channel.id !== cfg.channelId) return;

    enforce(message).catch((err) => {
      console.error('⚠️  فشل تنفيذ صفر التسامح:', err.message);
    });
  });
}

module.exports = { register };
