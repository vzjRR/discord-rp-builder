// مسارات استرجاع الرقم السري المنسي — عامة بطبيعتها (من نسي رقمه لا
// يستطيع تسجيل الدخول)، فهي محميّة بحدّ محاولات صارم لكل عنوان IP فوق
// الحدود الموضوعة لكل حساب في src/pinReset.js.

const express = require('express');
const auth = require('../auth');
const pinReset = require('../pinReset');
const { clientIp } = require('../clientIp');

const router = express.Router();

const DISCORD_ID_RE = /^[0-9]{15,25}$/;
const CODE_RE = /^[0-9]{6}$/;

function limiter(max, windowMs) {
  const hits = new Map(); // ip -> [timestamps]
  return (req, res, next) => {
    const ip = clientIp(req);
    const now = Date.now();
    const list = (hits.get(ip) || []).filter((t) => now - t < windowMs);
    if (list.length >= max) {
      return res.status(429).json({ error: 'محاولات كثيرة، انتظر قليلًا ثم أعد المحاولة' });
    }
    list.push(now);
    hits.set(ip, list);
    next();
  };
}

// طلب الرمز: أوسع قليلًا لأن الرسالة قد لا تصل من أول مرة
router.post('/api/pin-reset/request', limiter(5, 60 * 60 * 1000), async (req, res) => {
  const discordUserId = String(req.body?.discordUserId || '').trim();
  if (!DISCORD_ID_RE.test(discordUserId)) {
    return res.status(400).json({ error: 'اكتب معرّف حساب ديسكورد صحيح (أرقام فقط)' });
  }

  const result = await pinReset.requestCode(discordUserId);
  if (!result.ok) return res.status(429).json({ error: result.error });

  // الرد نفسه سواء كان المعرّف مسجّلًا أو لا
  res.json({ ok: true });
});

// إدخال الرمز: ضيّق، لأن كل محاولة هنا تخمين لرمز من ستة أرقام
router.post('/api/pin-reset/verify', limiter(10, 15 * 60 * 1000), async (req, res) => {
  const discordUserId = String(req.body?.discordUserId || '').trim();
  const code = String(req.body?.code || '').trim();

  if (!DISCORD_ID_RE.test(discordUserId) || !CODE_RE.test(code)) {
    return res.status(400).json({ error: 'الرمز غير صحيح أو انتهت صلاحيته' });
  }

  const result = await pinReset.verifyCode(discordUserId, code);
  if (!result.ok) return res.status(401).json({ error: result.error });

  res.cookie(auth.SESSION_COOKIE, result.token, {
    httpOnly: true,
    secure: req.secure || req.headers['x-forwarded-proto'] === 'https',
    sameSite: 'lax',
    expires: result.expiresAt,
    path: '/',
  });
  res.json({ ok: true });
});

module.exports = router;
