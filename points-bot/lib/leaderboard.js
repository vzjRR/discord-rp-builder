// استعلامات الترتيب - قراءة فقط. السيرفر الكامل غالبًا مئات لآلاف قليلة
// من الأعضاء المؤهَّلين، فالترتيب بكود التطبيق (بدل SQL معقّد) أبسط
// وسريع بما يكفي - تُستدعى فقط عند طلب فعلي من المنصة، لا لكل رسالة.

const { db } = require('./db');
const { rank } = require('./ranking');

function pickPointsAndImages(user, scope) {
  if (scope === 'weekly') return { points: user.weekly_points, images: user.weekly_images };
  if (scope === 'monthly') return { points: user.monthly_points, images: user.monthly_images };
  return { points: user.total_points, images: user.total_images };
}

function getRankedUsers(scope) {
  const allUsers = db.prepare('SELECT * FROM users').all();
  const rankable = allUsers
    .map((user) => {
      const { points, images } = pickPointsAndImages(user, scope);
      return { points, images, firstAchievedAt: user.first_point_at ?? user.created_at, user };
    })
    .filter((entry) => entry.points > 0);

  return rank(rankable).map(({ rank: position, entry }) => ({
    rank: position,
    userId: entry.user.discord_user_id,
    username: entry.user.username,
    displayName: entry.user.display_name,
    points: entry.points,
    images: entry.images,
  }));
}

function getTopN(scope, limit) {
  return getRankedUsers(scope).slice(0, limit);
}

function getUserLeaderboardEntry(userId, scope) {
  return getRankedUsers(scope).find((e) => e.userId === userId);
}

function getHistoricalPeriodKeys(periodType, limit = 25) {
  const rows = db
    .prepare('SELECT DISTINCT period_key FROM period_history WHERE period_type = ? ORDER BY period_key DESC LIMIT ?')
    .all(periodType, limit);
  return rows.map((r) => r.period_key);
}

function getHistoricalLeaderboard(periodType, periodKey) {
  const rows = db
    .prepare('SELECT * FROM period_history WHERE period_type = ? AND period_key = ? ORDER BY rank_position')
    .all(periodType, periodKey);
  return rows.map((row) => ({
    rank: row.rank_position,
    userId: row.user_id,
    username: row.username,
    displayName: row.display_name,
    points: row.points,
    images: row.images,
  }));
}

module.exports = { getRankedUsers, getTopN, getUserLeaderboardEntry, getHistoricalPeriodKeys, getHistoricalLeaderboard };
