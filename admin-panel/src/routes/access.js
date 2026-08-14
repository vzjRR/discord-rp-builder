// طلب رمز دخول — لأي عضو دخل المنصة وما عنده حساب (أو نسي رقمه). عام
// وبدون تسجيل دخول، فمحمي بحد محاولات صارم لكل IP عشان محد يقدر يفيض
// الخاص بتنبيهات وهمية على Owner.

const express = require('express');
const { db } = require('../db');
const discord = require('../discord');
const { requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');
const { clientIp } = require('../clientIp');

const router = express.Router();

const DISCORD_ID_RE = /^[0-9]{15,25}$/;

// ── تأمين الطلبات ────────────────────────────────────────────────
const attempts = new Map(); // ip -> [timestamps]
const MAX_ATTEMPTS = 3;
const WINDOW_MS = 60 * 60 * 1000; // ساعة

function isRateLimited(ip) {
  const now = Date.now();
  const list = (attempts.get(ip) || []).filter((t) => now - t < WINDOW_MS);
  attempts.set(ip, list);
  return list.length >= MAX_ATTEMPTS;
}

function recordAttempt(ip) {
  const list = attempts.get(ip) || [];
  list.push(Date.now());
  attempts.set(ip, list);
}

router.post('/api/access-requests', async (req, res) => {
  const ip = clientIp(req);
  if (isRateLimited(ip)) {
    return res.status(429).json({ error: 'طلبات كثيرة، حاول بعد شوي' });
  }
  recordAttempt(ip);

  const { discordUserId, note } = req.body || {};
  if (!DISCORD_ID_RE.test(String(discordUserId || ''))) {
    return res.status(400).json({ error: 'اكتب ID حساب ديسكورد صحيح' });
  }
  const cleanNote = note ? String(note).trim().slice(0, 300) : null;

  const existing = db
    .prepare("SELECT id FROM access_requests WHERE discord_user_id = ? AND status = 'pending'")
    .get(discordUserId);

  if (!existing) {
    db.prepare('INSERT INTO access_requests (discord_user_id, note) VALUES (?, ?)').run(discordUserId, cleanNote);

    const notifyId = process.env.OWNER_NOTIFY_USER_ID;
    if (notifyId) {
      const text =
        `🔔 **طلب دخول جديد لمنصة الإدارة**\n\n` +
        `ID العضو: ${discordUserId}\n` +
        (cleanNote ? `ملاحظة منه: ${cleanNote}\n\n` : '\n') +
        `راجع الطلب وسوّي له حساب من صفحة "إدارة الحسابات" بالمنصة.`;
      discord.sendDM(notifyId, text).catch((err) => console.error('access-request owner DM failed:', err.message));
    }
  }

  // نفس الرد سواء طلب جديد أو طلب معلّق أصلًا — ما نكشف للمستخدم فرق
  res.json({ ok: true });
});

router.get('/api/access-requests', requireAuth, requireOwner, (req, res) => {
  const rows = db
    .prepare(
      "SELECT id, discord_user_id AS discordUserId, note, created_at AS createdAt FROM access_requests WHERE status = 'pending' ORDER BY created_at ASC"
    )
    .all();
  res.json({ requests: rows });
});

router.post('/api/access-requests/:id/reject', requireAuth, requireOwner, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const info = db
    .prepare(
      "UPDATE access_requests SET status = 'rejected', resolved_at = datetime('now'), resolved_by_admin_id = ? WHERE id = ? AND status = 'pending'"
    )
    .run(req.admin.id, id);
  if (info.changes === 0) return res.status(404).json({ error: 'الطلب غير موجود أو انسوى فيه إجراء قبل كذا' });

  await logAction(req.admin, 'access_request.reject', `رفض طلب دخول (#${id})`);
  res.json({ ok: true });
});

module.exports = router;
