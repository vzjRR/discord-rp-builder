// تسجيل حركة الأعضاء في السيرفر لصفحة "حالة السيرفر" في منصة الإدارة.
//
// ديسكورد لا يحتفظ بتاريخ المغادرات ولا بعدّاد رسائل لكل عضو، فما لا نسجّله
// لحظة وقوعه يضيع. والبوت وحده هو المتصل ببوابة ديسكورد (Gateway)، فهو
// الموضع الوحيد الذي تصله هذه الأحداث.
//
// قاعدة بيانات منفصلة عن قاعدة المنصة عمدًا: البوت يكتب هنا والمنصة تقرأ،
// فخلل في التسجيل لا يمسّ الحسابات ولا الجلسات ولا سجل النشاط.
//
// النشاط يُخزَّن مجمّعًا (عضو + يوم + عدد) لا رسالة رسالة: العدّ وحده هو
// المطلوب، وحفظ صفّ لكل رسالة يُضخّم الملف بلا فائدة. ولا نخزّن أي نص.

const fs = require('fs');
const path = require('path');

const DB_PATH = process.env.EVENTS_DB_PATH || '/data/server-events.db';

let db = null;

function init() {
  if (db) return db;
  try {
    const Database = require('better-sqlite3');
    fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL'); // المنصة تقرأ بالتوازي مع كتابتنا
    db.exec(`
      CREATE TABLE IF NOT EXISTS member_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        username TEXT,
        display_name TEXT,
        avatar TEXT,
        kind TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );

      CREATE TABLE IF NOT EXISTS message_activity (
        user_id TEXT NOT NULL,
        day TEXT NOT NULL,
        username TEXT,
        display_name TEXT,
        count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (user_id, day)
      );

      CREATE INDEX IF NOT EXISTS idx_member_events_kind ON member_events(kind, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_message_activity_day ON message_activity(day);
    `);
    return db;
  } catch (err) {
    // التتبّع ميزة إضافية: فشلها يجب ألا يمنع الترحيب بالأعضاء
    console.error('⚠️  تعذّر فتح قاعدة أحداث السيرفر:', err.message);
    db = null;
    return null;
  }
}

function recordMemberEvent(member, kind) {
  const conn = init();
  if (!conn) return;
  try {
    conn
      .prepare('INSERT INTO member_events (user_id, username, display_name, avatar, kind) VALUES (?, ?, ?, ?, ?)')
      .run(
        member.id,
        member.user?.username || null,
        member.displayName || member.user?.globalName || null,
        member.user?.displayAvatarURL?.({ extension: 'png', size: 64 }) || null,
        kind
      );
  } catch (err) {
    console.error('⚠️  تعذّر تسجيل حدث عضو:', err.message);
  }
}

function recordMessage(message) {
  const conn = init();
  if (!conn) return;
  try {
    const day = new Date().toISOString().slice(0, 10);
    conn
      .prepare(
        `INSERT INTO message_activity (user_id, day, username, display_name, count)
              VALUES (?, ?, ?, ?, 1)
         ON CONFLICT(user_id, day) DO UPDATE SET
              count = count + 1,
              username = excluded.username,
              display_name = excluded.display_name`
      )
      .run(
        message.author.id,
        day,
        message.author.username || null,
        message.member?.displayName || message.author.globalName || null
      );
  } catch (err) {
    console.error('⚠️  تعذّر تسجيل نشاط رسالة:', err.message);
  }
}

// ننظّف ما تجاوز تسعين يومًا: الصفحة لا تعرض أبعد من ذلك، وبقاؤه يُنمّي
// الملف بلا داعٍ على قرص محدود.
function prune() {
  const conn = init();
  if (!conn) return;
  try {
    conn.prepare("DELETE FROM member_events WHERE created_at < datetime('now', '-90 days')").run();
    conn.prepare("DELETE FROM message_activity WHERE day < date('now', '-90 days')").run();
  } catch (err) {
    console.error('⚠️  تعذّر تنظيف أحداث السيرفر:', err.message);
  }
}

/** يربط التتبّع بأحداث البوت. آمن الاستدعاء ولو تعذّر فتح القاعدة. */
function register(client, guildId) {
  const sameGuild = (g) => !guildId || g?.id === guildId;

  client.on('guildMemberAdd', (member) => {
    if (sameGuild(member.guild)) recordMemberEvent(member, 'join');
  });

  client.on('guildMemberRemove', (member) => {
    if (sameGuild(member.guild)) recordMemberEvent(member, 'leave');
  });

  client.on('messageCreate', (message) => {
    if (!message.guild || !sameGuild(message.guild)) return;
    if (message.author?.bot) return;
    recordMessage(message);
  });

  client.once('ready', () => {
    prune();
    setInterval(prune, 24 * 60 * 60 * 1000).unref();
  });
}

module.exports = { register, init, DB_PATH };
