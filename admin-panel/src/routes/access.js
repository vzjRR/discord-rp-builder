// طلب صلاحية دخول — لعضو تحقّقنا من هويته الحقيقية عبر تسجيل الدخول
// بديسكورد (src/routes/discordAuth.js) واتضح أنه ليس له حساب على المنصة.
// هويته (ID، اسمه، رتبته الفعلية بالسيرفر) تصل من كوكي موقَّع لا من حقل
// نصي يكتبه هو، فلا يمكنه انتحال معرّف غيره أو تلفيق رتبة أعلى من رتبته.

const crypto = require('crypto');
const express = require('express');
const { db } = require('../db');
const discord = require('../discord');
const auth = require('../auth');
const { requireAuth, requireOwner } = auth;
const { logAction } = require('../audit');
const { clientIp } = require('../clientIp');
const { sendBrandedDM } = require('../messageFormat');
const { testRedirectUserId } = require('../testMode');
const perms = require('../permissions');
const discordAuthRoutes = require('./discordAuth');

const router = express.Router();
const PENDING_COOKIE = discordAuthRoutes.PENDING_COOKIE;

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

function readPendingIdentity(req) {
  try {
    return JSON.parse(req.signedCookies?.[PENDING_COOKIE] || 'null');
  } catch {
    return null;
  }
}

router.post('/api/access-requests', async (req, res) => {
  const ip = clientIp(req);
  if (isRateLimited(ip)) {
    return res.status(429).json({ error: 'طلبات كثيرة، أعد المحاولة بعد قليل' });
  }

  const identity = readPendingIdentity(req);
  if (!identity) {
    return res.status(401).json({ error: 'سجّل الدخول عبر ديسكورد أولًا من صفحة تسجيل الدخول' });
  }
  recordAttempt(ip);

  const note = req.body?.note ? String(req.body.note).trim().slice(0, 300) : null;

  const existing = db
    .prepare("SELECT id FROM access_requests WHERE discord_user_id = ? AND status = 'pending'")
    .get(identity.id);

  if (!existing) {
    db.prepare(
      `INSERT INTO access_requests (discord_user_id, discord_username, discord_avatar, discord_rank, note)
       VALUES (?, ?, ?, ?, ?)`
    ).run(identity.id, identity.displayName || identity.username, identity.avatar, identity.rank, note);

    const notifyId = process.env.OWNER_NOTIFY_USER_ID;
    if (notifyId) {
      const text =
        `🔔 **طلب دخول جديد لمنصة الإدارة**\n\n` +
        `العضو: ${identity.displayName || identity.username} (<@${identity.id}>)\n` +
        `الرتبة بالسيرفر: ${identity.rank || 'بلا رتبة مميّزة'}\n` +
        (note ? `السبب: ${note}\n\n` : '\n') +
        `راجع الطلب من صفحة "إدارة الحسابات" بالمنصة.`;
      discord.sendDM(notifyId, text).catch((err) => console.error('access-request owner DM failed:', err.message));
    }
  }

  // كوكي هوية استعمال واحد — انتهى غرضه بمجرد تقديم الطلب
  res.clearCookie(PENDING_COOKIE, { path: '/' });

  // نفس الرد سواء طلب جديد أو طلب معلّق أصلًا — ما نكشف للمستخدم فرق
  res.json({ ok: true });
});

router.get('/api/access-requests', requireAuth, requireOwner, (req, res) => {
  const rows = db
    .prepare(
      `SELECT id, discord_user_id AS discordUserId, discord_username AS discordUsername,
              discord_avatar AS discordAvatar, discord_rank AS discordRank,
              note, created_at AS createdAt
         FROM access_requests WHERE status = 'pending' ORDER BY created_at ASC`
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
  if (info.changes === 0) return res.status(404).json({ error: 'الطلب غير موجود، أو نُفِّذ فيه إجراء من قبل' });

  await logAction(req.admin, 'access_request.reject', `رفض طلب دخول (#${id})`);
  res.json({ ok: true });
});

// قبول الطلب: ينشئ حسابًا مربوطًا بمعرّف ديسكورد المُتحقَّق منه — بلا رقم
// سري يُسلَّم له، لأنه سيدخل دائمًا بزر "الدخول عبر ديسكورد". الرقم
// الداخلي المخزَّن عشوائي طويل غير قابل للتخمين ولا يُكشف لأحد؛ هو فقط
// حشو لعمود NOT NULL قديم من عهد الدخول بالرقم السري وحده.
router.post('/api/access-requests/:id/approve', requireAuth, requireOwner, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const request = db.prepare("SELECT * FROM access_requests WHERE id = ? AND status = 'pending'").get(id);
  if (!request) return res.status(404).json({ error: 'الطلب غير موجود، أو نُفِّذ فيه إجراء من قبل' });

  const already = db.prepare('SELECT id FROM admins WHERE discord_user_id = ?').get(request.discord_user_id);
  if (already) return res.status(400).json({ error: 'هذا العضو له حساب على المنصة أصلًا' });

  const name = request.discord_username || request.discord_user_id;
  const unusablePin = crypto.randomBytes(32).toString('hex');
  const pinHash = await auth.hashPin(unusablePin);

  const granted = perms.serialize(perms.DEFAULT_KEYS);
  const info = db
    .prepare(
      `INSERT INTO admins (name, pin_hash, is_owner, discord_user_id, must_change_pin, permissions)
       VALUES (?, ?, 0, ?, 0, ?)`
    )
    .run(name, pinHash, request.discord_user_id, granted);

  db.prepare(
    "UPDATE access_requests SET status = 'approved', resolved_at = datetime('now'), resolved_by_admin_id = ? WHERE id = ?"
  ).run(req.admin.id, id);

  await logAction(req.admin, 'admin.create', `قبِل طلب دخول وأنشأ حساب "${name}" عبر ديسكورد`);

  let dmSent = false;
  let dmError = null;
  const test = testRedirectUserId();
  const target = test || request.discord_user_id;
  try {
    await sendBrandedDM(target, {
      title: '✅ تم قبول طلبك',
      content:
        `مرحبًا ${name}، صار عندك وصول لمنصة إدارة Enclave RP BOT.\n\n` +
        `سجّل الدخول بزر **"الدخول عبر ديسكورد"** من صفحة تسجيل الدخول — بلا حاجة لرقم سري.`,
    });
    dmSent = true;
  } catch (err) {
    dmError = 'أُنشئ الحساب بنجاح، لكن تعذّر إبلاغ العضو (قد تكون خصوصياته مغلقة).';
    console.error('access approval DM failed:', err.message);
  }

  res.json({ ok: true, admin: { id: info.lastInsertRowid, name }, dmSent, dmError });
});

module.exports = router;
