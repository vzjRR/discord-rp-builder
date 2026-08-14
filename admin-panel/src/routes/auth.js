const express = require('express');
const auth = require('../auth');
const { logAction } = require('../audit');
const { isTestMode } = require('../testMode');

const router = express.Router();

router.post('/api/login', async (req, res) => {
  const ip = req.ip;
  const result = await auth.login(req.body?.pin, ip);
  if (!result.ok) return res.status(401).json({ error: result.error });

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
  if (!req.admin) return res.status(401).json({ error: 'غير مسجل دخول' });
  res.json({ admin: req.admin, testMode: isTestMode() });
});

const PIN_RE = /^[0-9]{4,32}$/;

router.put('/api/me/pin', auth.requireAuth, async (req, res) => {
  const { currentPin, newPin } = req.body || {};
  if (!PIN_RE.test(newPin || '')) {
    return res.status(400).json({ error: 'الرقم السري الجديد لازم يكون أرقام فقط، من ٤ إلى ٣٢ رقم' });
  }
  if (newPin === currentPin) {
    return res.status(400).json({ error: 'اختر رقم مختلف عن الرقم الحالي' });
  }

  const result = await auth.changePin(req.admin.id, currentPin, newPin);
  if (!result.ok) return res.status(401).json({ error: result.error });

  await logAction(req.admin, 'admin.change_pin', 'غيّر رقمه السري');
  res.json({ ok: true });
});

module.exports = router;
