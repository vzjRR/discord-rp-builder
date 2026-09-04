// قاعدة نقاط الصور — يكتبها بوت points-bot (مراقبة القناة + الرولوفر)،
// وتقرأها هذي الوحدة لعرض لوحة الصدارة. الاستثناء الوحيد: التعديل اليدوي
// (إضافة/خصم/تصفير من صلاحية points.manage) يكتب هنا مباشرة أيضًا لأن
// المنصة REST-only ولا تتواصل مع عملية البوت بأي طريق آخر — نفس اضطرار
// موثّق بـ points-bot/lib/db.js. وضع WAL يجعل الكتابة من عمليتين مختلفتين
// (البوت هنا، والمنصة) آمنة على نفس الملف.
//
// نفس مخطط الجداول مكرّر هنا عمدًا (لا require عبر مجلد points-bot) — نفس
// أسلوب هذا المستودع: كل خدمة تحمل نسخة قراءتها الخاصة (قارن serverStats.js
// مع welcome-bot/lib/activityTracker.js) بدل اعتماد كودي بين خدمتين منفصلتي
// النشر.

const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { appendAuditFile } = require('./audit');

const DB_PATH =
  process.env.POINTS_DB_PATH ||
  (process.env.EVENTS_DB_PATH
    ? path.join(path.dirname(process.env.EVENTS_DB_PATH), 'points.db')
    : '/data/points.db');

let db = null;

// لو ملف قاعدة النقاط ما وُجد بعد (البوت ما اشتغل ولا مرة)، لا ننشئه من
// هنا بأنفسنا — عرض فاضٍ أوضح من قاعدة يتيمة لا يكتب فيها بوت أصلًا.
function getDb() {
  if (db) return db;
  if (!fs.existsSync(DB_PATH)) return null;
  try {
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    return db;
  } catch (err) {
    console.error('تعذّر فتح قاعدة نقاط الصور:', err.message);
    return null;
  }
}

function isAvailable() {
  return Boolean(getDb());
}

function compareRankable(a, b) {
  if (b.points !== a.points) return b.points - a.points;
  if (b.images !== a.images) return b.images - a.images;
  return a.firstAchievedAt - b.firstAchievedAt;
}

function pickPointsAndImages(user, scope) {
  if (scope === 'weekly') return { points: user.weekly_points, images: user.weekly_images };
  if (scope === 'monthly') return { points: user.monthly_points, images: user.monthly_images };
  return { points: user.total_points, images: user.total_images };
}

function getRankedUsers(scope) {
  const conn = getDb();
  if (!conn) return [];
  const allUsers = conn.prepare('SELECT * FROM users').all();
  const rankable = allUsers
    .map((user) => {
      const { points, images } = pickPointsAndImages(user, scope);
      return { points, images, firstAchievedAt: user.first_point_at ?? user.created_at, user };
    })
    .filter((entry) => entry.points > 0)
    .sort(compareRankable);

  return rankable.map((entry, index) => ({
    rank: index + 1,
    userId: entry.user.discord_user_id,
    username: entry.user.username,
    displayName: entry.user.display_name,
    points: entry.points,
    images: entry.images,
  }));
}

function getUser(userId) {
  const conn = getDb();
  if (!conn) return undefined;
  return conn.prepare('SELECT * FROM users WHERE discord_user_id = ?').get(userId);
}

function getUserAudit(userId, limit = 50) {
  const conn = getDb();
  if (!conn) return [];
  return conn
    .prepare('SELECT * FROM audit_log WHERE user_id = ? ORDER BY created_at DESC LIMIT ?')
    .all(userId, limit);
}

function listAudit({ page = 1, pageSize = 50 } = {}) {
  const conn = getDb();
  if (!conn) return { rows: [], total: 0, page, pageSize };
  const offset = (page - 1) * pageSize;
  const rows = conn
    .prepare('SELECT * FROM audit_log ORDER BY created_at DESC LIMIT ? OFFSET ?')
    .all(pageSize, offset);
  const { count } = conn.prepare('SELECT COUNT(*) AS count FROM audit_log').get();
  return { rows, total: count, page, pageSize };
}

function getHistoricalPeriodKeys(periodType, limit = 25) {
  const conn = getDb();
  if (!conn) return [];
  return conn
    .prepare('SELECT DISTINCT period_key FROM period_history WHERE period_type = ? ORDER BY period_key DESC LIMIT ?')
    .all(periodType, limit)
    .map((r) => r.period_key);
}

function getHistoricalLeaderboard(periodType, periodKey) {
  const conn = getDb();
  if (!conn) return [];
  return conn
    .prepare('SELECT * FROM period_history WHERE period_type = ? AND period_key = ? ORDER BY rank_position')
    .all(periodType, periodKey)
    .map((row) => ({
      rank: row.rank_position,
      userId: row.user_id,
      username: row.username,
      displayName: row.display_name,
      points: row.points,
      images: row.images,
    }));
}

function recordAudit(conn, entry) {
  const now = Date.now();
  conn
    .prepare(
      `INSERT INTO audit_log (action_type, user_id, actor_id, message_id, channel_id, points_delta, details, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(
      entry.actionType,
      entry.userId ?? null,
      entry.actorId ?? null,
      entry.messageId ?? null,
      entry.channelId ?? null,
      entry.pointsDelta ?? null,
      entry.details ? JSON.stringify(entry.details) : null,
      now
    );
  appendAuditFile({ ts: new Date(now).toISOString(), type: 'points', ...entry });
}

function upsertUserProfile(conn, userId, username, displayName) {
  const now = Date.now();
  const existing = conn.prepare('SELECT 1 FROM users WHERE discord_user_id = ?').get(userId);
  if (existing) {
    conn
      .prepare('UPDATE users SET username = ?, display_name = ?, updated_at = ? WHERE discord_user_id = ?')
      .run(username, displayName, now, userId);
    return;
  }
  conn
    .prepare(
      `INSERT INTO users (discord_user_id, username, display_name, total_points, weekly_points, monthly_points,
                           total_images, weekly_images, monthly_images, first_point_at, last_point_at, created_at, updated_at)
       VALUES (?, ?, ?, 0, 0, 0, 0, 0, 0, NULL, NULL, ?, ?)`
    )
    .run(userId, username, displayName, now, now);
}

/** تعديل يدوي من المنصة (owner/points.manage) — يؤثر دايمًا على الفترة الحالية. */
function adjustPointsManually(userId, username, displayName, pointsDelta, actorId, reason) {
  const conn = getDb();
  if (!conn) throw new Error('قاعدة نقاط الصور غير متاحة — تأكد إن البوت اشتغل مرة واحدة على الأقل');

  return conn.transaction(() => {
    upsertUserProfile(conn, userId, username, displayName);
    const now = Date.now();
    const clamp = (n) => Math.max(0, n);
    const current = conn.prepare('SELECT * FROM users WHERE discord_user_id = ?').get(userId);
    conn
      .prepare(
        `UPDATE users SET total_points = ?, weekly_points = ?, monthly_points = ?,
                           first_point_at = ?, last_point_at = ?, updated_at = ?
         WHERE discord_user_id = ?`
      )
      .run(
        clamp(current.total_points + pointsDelta),
        clamp(current.weekly_points + pointsDelta),
        clamp(current.monthly_points + pointsDelta),
        current.first_point_at ?? (pointsDelta > 0 ? now : current.first_point_at),
        pointsDelta > 0 ? now : current.last_point_at,
        now,
        userId
      );
    recordAudit(conn, {
      actionType: 'MANUAL_ADJUSTMENT',
      userId,
      actorId,
      pointsDelta,
      details: reason ? { reason } : null,
    });
    return conn.prepare('SELECT * FROM users WHERE discord_user_id = ?').get(userId);
  })();
}

function resetUserPoints(userId, actorId) {
  const conn = getDb();
  if (!conn) throw new Error('قاعدة نقاط الصور غير متاحة — تأكد إن البوت اشتغل مرة واحدة على الأقل');

  return conn.transaction(() => {
    const existing = conn.prepare('SELECT * FROM users WHERE discord_user_id = ?').get(userId);
    if (!existing) return undefined;
    const now = Date.now();
    conn
      .prepare(
        `UPDATE users SET total_points = 0, weekly_points = 0, monthly_points = 0,
                           total_images = 0, weekly_images = 0, monthly_images = 0, updated_at = ?
         WHERE discord_user_id = ?`
      )
      .run(now, userId);
    recordAudit(conn, {
      actionType: 'MANUAL_ADJUSTMENT',
      userId,
      actorId,
      pointsDelta: -existing.total_points,
      details: { reason: 'reset', previousTotal: existing.total_points },
    });
    return conn.prepare('SELECT * FROM users WHERE discord_user_id = ?').get(userId);
  })();
}

module.exports = {
  DB_PATH,
  isAvailable,
  getRankedUsers,
  getUser,
  getUserAudit,
  listAudit,
  getHistoricalPeriodKeys,
  getHistoricalLeaderboard,
  adjustPointsManually,
  resetUserPoints,
};
