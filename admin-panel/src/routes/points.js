// نقاط الصور — قراءة (points.view) وتعديل يدوي (points.manage). البيانات
// نفسها يكتبها بوت points-bot تلقائيًا بالكامل؛ لا يوجد هنا ولا أي أمر
// ديسكورد لهذا الموضوع — فقط ما يظهر بهذي الصفحة.

const express = require('express');
const { requireAuth } = require('../auth');
const { requirePermission } = require('../permissions');
const { logAction } = require('../audit');
const pointsDb = require('../pointsDb');

const router = express.Router();
const SCOPES = new Set(['weekly', 'monthly', 'alltime']);
const PERIOD_TYPES = new Set(['WEEK', 'MONTH']);

function unavailable(res) {
  return res.status(503).json({
    error: 'قاعدة نقاط الصور غير متاحة بعد — تأكد إن بوت points-bot اشتغل مرة واحدة على الأقل',
  });
}

router.get('/api/points/leaderboard', requireAuth, requirePermission('points.view'), (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const scope = SCOPES.has(req.query.scope) ? req.query.scope : 'alltime';
  res.json({ scope, entries: pointsDb.getRankedUsers(scope) });
});

router.get('/api/points/user/:userId', requireAuth, requirePermission('points.view'), (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const user = pointsDb.getUser(req.params.userId);
  if (!user) return res.status(404).json({ error: 'العضو لا يملك أي نقاط مسجّلة' });
  res.json({
    userId: user.discord_user_id,
    username: user.username,
    displayName: user.display_name,
    totalPoints: user.total_points,
    weeklyPoints: user.weekly_points,
    monthlyPoints: user.monthly_points,
    totalImages: user.total_images,
    weeklyImages: user.weekly_images,
    monthlyImages: user.monthly_images,
    firstPointAt: user.first_point_at,
    lastPointAt: user.last_point_at,
    audit: pointsDb.getUserAudit(req.params.userId, 50),
  });
});

router.get('/api/points/audit', requireAuth, requirePermission('points.view'), (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const page = Math.max(1, Number(req.query.page) || 1);
  const pageSize = Math.min(100, Math.max(1, Number(req.query.pageSize) || 50));
  res.json(pointsDb.listAudit({ page, pageSize }));
});

router.get('/api/points/history/:type', requireAuth, requirePermission('points.view'), (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const type = req.params.type.toUpperCase();
  if (!PERIOD_TYPES.has(type)) return res.status(400).json({ error: 'نوع فترة غير معروف' });
  res.json({ type, keys: pointsDb.getHistoricalPeriodKeys(type, 25) });
});

router.get('/api/points/history/:type/:key', requireAuth, requirePermission('points.view'), (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const type = req.params.type.toUpperCase();
  if (!PERIOD_TYPES.has(type)) return res.status(400).json({ error: 'نوع فترة غير معروف' });
  res.json({ type, key: req.params.key, entries: pointsDb.getHistoricalLeaderboard(type, req.params.key) });
});

router.post('/api/points/adjust', requireAuth, requirePermission('points.manage'), async (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const { userId, username, displayName, delta, reason } = req.body || {};
  if (!userId || typeof userId !== 'string') return res.status(400).json({ error: 'معرّف العضو مطلوب' });
  const pointsDelta = Number(delta);
  if (!Number.isInteger(pointsDelta) || pointsDelta === 0) {
    return res.status(400).json({ error: 'قيمة التعديل يجب أن تكون رقمًا صحيحًا مختلفًا عن صفر' });
  }

  try {
    const user = pointsDb.adjustPointsManually(
      userId,
      username || userId,
      displayName || username || userId,
      pointsDelta,
      req.admin.id,
      reason
    );
    await logAction(
      req.admin,
      'points.adjust',
      `${pointsDelta > 0 ? 'أضاف' : 'خصم'} ${Math.abs(pointsDelta)} نقطة ${pointsDelta > 0 ? 'لـ' : 'من'} "${displayName || username || userId}"${reason ? ` — ${reason}` : ''}`
    );
    res.json({ ok: true, user });
  } catch (err) {
    console.error('points/adjust:', err.message);
    res.status(503).json({ error: err.message });
  }
});

router.post('/api/points/reset', requireAuth, requirePermission('points.manage'), async (req, res) => {
  if (!pointsDb.isAvailable()) return unavailable(res);
  const { userId, displayName } = req.body || {};
  if (!userId || typeof userId !== 'string') return res.status(400).json({ error: 'معرّف العضو مطلوب' });

  try {
    const user = pointsDb.resetUserPoints(userId, req.admin.id);
    if (!user) return res.status(404).json({ error: 'العضو لا يملك أي نقاط مسجّلة' });
    await logAction(req.admin, 'points.reset', `صفّر نقاط "${displayName || userId}"`);
    res.json({ ok: true, user });
  } catch (err) {
    console.error('points/reset:', err.message);
    res.status(503).json({ error: err.message });
  }
});

module.exports = router;
