// قراءة حالة السيرفر من مصدرين:
//
//   • ديسكورد مباشرة — العدد الكلي والمتصلون الآن وأحدث المنضمّين. هذه
//     يعرفها ديسكورد في اللحظة نفسها فلا معنى لتخزينها عندنا.
//   • قاعدة الأحداث التي يكتبها البوت — المغادرون وترتيب النشاط. ديسكورد
//     لا يحفظ تاريخ المغادرات ولا عدّاد رسائل لكل عضو، فما لم يُسجَّل لحظة
//     وقوعه لا يمكن استرجاعه لاحقًا بأي وسيلة.
//
// ولذلك: أرقام المغادرين والنشاط تبدأ من لحظة تشغيل هذه الميزة، لا من
// تاريخ السيرفر. الواجهة تقول ذلك صراحة كي لا تُقرأ الأرقام على غير وجهها.

const fs = require('fs');
const Database = require('better-sqlite3');
const discord = require('./discord');

const DB_PATH = process.env.EVENTS_DB_PATH || '/data/server-events.db';

let events = null;

// نفتح للقراءة فقط: البوت هو المالك الوحيد للكتابة هنا.
function eventsDb() {
  if (events) return events;
  if (!fs.existsSync(DB_PATH)) return null;
  try {
    events = new Database(DB_PATH, { readonly: true, fileMustExist: true });
    return events;
  } catch (err) {
    console.error('تعذّر فتح قاعدة أحداث السيرفر:', err.message);
    return null;
  }
}

function query(sql, params = []) {
  const conn = eventsDb();
  if (!conn) return [];
  try {
    return conn.prepare(sql).all(...params);
  } catch (err) {
    console.error('استعلام أحداث السيرفر:', err.message);
    return [];
  }
}

/** هل بدأ التسجيل فعلًا؟ تحتاجه الواجهة لتشرح فراغ الجداول. */
function trackingSince() {
  const rows = query('SELECT MIN(created_at) AS since FROM member_events');
  const activity = query('SELECT MIN(day) AS since FROM message_activity');
  return rows[0]?.since || activity[0]?.since || null;
}

function recentLeavers(limit = 10) {
  return query(
    `SELECT user_id AS userId, username, display_name AS displayName, avatar, created_at AS at
       FROM member_events WHERE kind = 'leave' ORDER BY created_at DESC LIMIT ?`,
    [limit]
  );
}

function activityRanking({ days = 30, limit = 10 } = {}) {
  const rows = query(
    `SELECT user_id AS userId,
            MAX(username) AS username,
            MAX(display_name) AS displayName,
            SUM(count) AS messages
       FROM message_activity
      WHERE day >= date('now', ?)
      GROUP BY user_id
      ORDER BY messages DESC`,
    [`-${Number(days) || 30} days`]
  );
  return {
    days,
    most: rows.slice(0, limit),
    // الأقل تفاعلًا من بين من تكلّم فعلًا: من لم يكتب حرفًا لا يظهر هنا
    // لأننا لا نملك عنه بيانًا أصلًا، وعرضه صفرًا ادّعاء لا دليل عليه.
    least: rows.slice(-limit).reverse(),
    totalTracked: rows.length,
  };
}

/** حالة السيرفر كاملة. */
async function snapshot() {
  // getGuild تطلب with_counts، فتأتي معها أعداد الأعضاء والمتصلين الآن
  const [guild, members] = await Promise.all([
    discord.getGuild().catch(() => null),
    discord.listAllMembers().catch(() => []),
  ]);

  const humans = members.filter((m) => !m.user?.bot);
  const newest = [...humans]
    .sort((a, b) => new Date(b.joined_at) - new Date(a.joined_at))
    .slice(0, 10)
    .map((m) => ({
      userId: m.user.id,
      username: m.user.username,
      displayName: m.nick || m.user.global_name || m.user.username,
      avatar: discord.avatarUrl(m.user, 64),
      joinedAt: m.joined_at,
    }));

  return {
    guildName: guild?.name || null,
    memberCount: guild?.approximate_member_count ?? members.length,
    onlineCount: guild?.approximate_presence_count ?? null,
    humanCount: humans.length,
    botCount: members.length - humans.length,
    newestMembers: newest,
    recentLeavers: recentLeavers(10),
    activity: activityRanking({ days: 30, limit: 10 }),
    trackingSince: trackingSince(),
  };
}

module.exports = { snapshot, trackingSince, recentLeavers, activityRanking };
