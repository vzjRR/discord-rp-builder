const express = require('express');
const auth = require('../auth');
const { logAction } = require('../audit');
const { isTestMode } = require('../testMode');
const { clientIp } = require('../clientIp');
const permissions = require('../permissions');

const router = express.Router();

// محاولة تخمين ناجحة لا تترك أثرًا يميّزها عن دخول عادي، فالأثر الوحيد
// المتاح للمالك هو رؤية المحاولات الفاشلة. لا نسجّل كل فشل (تخمين موزّع
// يملأ السجل بملايين القيود على قرص محدود)، بل نسجّل الإشارة المفيدة:
// عنوانًا استنفد حدّه، أو موجة فشل عامة — ومرة واحدة لكل نافذة.
const reported = new Map(); // مفتاح -> آخر وقت تسجيل
const REPORT_EVERY_MS = 5 * 60 * 1000;

function reportOnce(key, action, detail) {
  const now = Date.now();
  if (now - (reported.get(key) || 0) < REPORT_EVERY_MS) return;
  reported.set(key, now);
  if (reported.size > 1000) {
    for (const [k, t] of reported) if (now - t > REPORT_EVERY_MS) reported.delete(k);
  }
  logAction(null, action, detail);
}

router.post('/api/login', async (req, res) => {
  const ip = clientIp(req);
  const result = await auth.login(req.body?.pin, ip);

  if (!result.ok) {
    if (result.rateLimited) {
      reportOnce(`ip:${ip}`, 'login.blocked', `مُنعت محاولات دخول متكررة من ${ip}`);
    } else if (result.globalFailures >= 30) {
      reportOnce('surge', 'login.surge', `موجة محاولات دخول فاشلة (${result.globalFailures} خلال خمس دقائق)`);
    }
    return res.status(401).json({ error: result.error });
  }

  res.cookie(auth.SESSION_COOKIE, result.token, {
    httpOnly: true,
    secure: req.secure || req.headers['x-forwarded-proto'] === 'https',
    sameSite: 'lax',
    expires: result.expiresAt,
    path: '/',
  });

  await logAction(result.admin, 'login', null);
  res.json({ ok: true, admin: result.admin });
});

router.post('/api/logout', async (req, res) => {
  const token = req.cookies?.[auth.SESSION_COOKIE];
  if (req.admin) await logAction(req.admin, 'logout', null);
  await auth.logout(token);
  res.clearCookie(auth.SESSION_COOKIE, { path: '/' });
  res.json({ ok: true });
});

router.get('/api/me', (req, res) => {
  if (!req.admin) return res.status(401).json({ error: 'لم تسجّل الدخول' });
  // نرسل الصلاحيات الفعلية (لا المخزّنة) كي تعرف الواجهة ما تعرضه
  res.json({
    admin: { ...req.admin, permissions: permissions.effective(req.admin) },
    testMode: isTestMode(),
  });
});

// الحدّ الأدنى مرفوع إلى ست خانات — الدخول بلا اسم مستخدم، فالرقم وحده
// هو كل ما يقف بين الغريب والمنصة. شرحه في src/auth.js.
const PIN_RE = new RegExp(`^[0-9]{${auth.MIN_PIN_LENGTH},${auth.MAX_PIN_LENGTH}}$`);

router.put('/api/me/pin', auth.requireAuth, async (req, res) => {
  const { currentPin, newPin } = req.body || {};
  if (!PIN_RE.test(newPin || '')) {
    return res.status(400).json({
      error: `الرقم السري الجديد أرقام فقط، من ${auth.arabicDigits(auth.MIN_PIN_LENGTH)} إلى ${auth.arabicDigits(auth.MAX_PIN_LENGTH)} رقمًا`,
    });
  }
  // جلسة الاسترجاع وحدها تُعفى من الرقم الحالي: صاحبها لا يعرفه أصلًا،
  // وقد أثبت هويته برمز وصله في الخاص، والجلسة محجوزة لهذه الخطوة وحدها.
  const recovering = Boolean(req.admin.viaRecovery && req.admin.mustChangePin);
  if (!recovering && newPin === currentPin) {
    return res.status(400).json({ error: 'اختر رقمًا مختلفًا عن رقمك الحالي' });
  }

  const result = await auth.changePin(req.admin.id, currentPin, newPin, { skipCurrentPin: recovering });
  if (!result.ok) return res.status(401).json({ error: result.error });

  await logAction(
    req.admin,
    'admin.change_pin',
    recovering ? 'وضع رقمًا سريًا جديدًا بعد استرجاع منسي' : 'غيّر رقمه السري'
  );
  res.json({ ok: true });
});

module.exports = router;
