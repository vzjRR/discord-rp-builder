// تسجيل الدخول عبر ديسكورد (OAuth2) — يستبدل الحاجة للرقم السري لمن
// حسابه مربوط بمعرّف ديسكورد. ونفس المسار يُستعمل لمن لا حساب له بعد:
// نتحقق من هويته الحقيقية عبر ديسكورد، ثم نعرض عليه طلب صلاحية بدل
// رفضه بصمت — الطلب يحمل رتبته الفعلية بالسيرفر (لا رتبة يكتبها هو).

const crypto = require('crypto');
const express = require('express');
const { db } = require('../db');
const auth = require('../auth');
const discord = require('../discord');
const oauth = require('../discordOAuth');
const { publicBaseUrl } = require('../publicUrl');

const router = express.Router();

const STATE_COOKIE = 'enclave_oauth_state';
const PENDING_COOKIE = 'enclave_pending_discord';
const STATE_TTL_MS = 10 * 60 * 1000;
const PENDING_TTL_MS = 15 * 60 * 1000;

function redirectUriFor(req) {
  return `${publicBaseUrl(req)}/api/auth/discord/callback`;
}

function cookieOpts(req, maxAge) {
  return {
    httpOnly: true,
    signed: true,
    sameSite: 'lax',
    secure: req.secure || req.headers['x-forwarded-proto'] === 'https',
    maxAge,
    path: '/',
  };
}

// ── بدء تسجيل الدخول ─────────────────────────────────────────────
router.get('/api/auth/discord/start', (req, res) => {
  if (!oauth.isConfigured()) {
    return res.status(503).send('تسجيل الدخول عبر ديسكورد غير مفعّل على هذا الخادم بعد.');
  }
  const state = crypto.randomBytes(24).toString('hex');
  res.cookie(STATE_COOKIE, JSON.stringify({ state, intent: 'login' }), cookieOpts(req, STATE_TTL_MS));
  res.redirect(oauth.authorizeUrl({ redirectUri: redirectUriFor(req), state }));
});

// ── ربط حساب ديسكورد بحساب حالي مسجَّل دخوله (self-service) ─────────
router.get('/api/auth/discord/link/start', auth.requireAuth, (req, res) => {
  if (!oauth.isConfigured()) {
    return res.status(503).send('تسجيل الدخول عبر ديسكورد غير مفعّل على هذا الخادم بعد.');
  }
  const state = crypto.randomBytes(24).toString('hex');
  res.cookie(STATE_COOKIE, JSON.stringify({ state, intent: 'link', adminId: req.admin.id }), cookieOpts(req, STATE_TTL_MS));
  res.redirect(oauth.authorizeUrl({ redirectUri: redirectUriFor(req), state }));
});

// ── العودة من ديسكورد ────────────────────────────────────────────
router.get('/api/auth/discord/callback', async (req, res) => {
  const fail = (msg) => res.redirect(`/login?oauthError=${encodeURIComponent(msg)}`);

  if (!oauth.isConfigured()) return fail('تسجيل الدخول عبر ديسكورد غير مفعّل');

  let saved;
  try {
    saved = JSON.parse(req.signedCookies?.[STATE_COOKIE] || 'null');
  } catch {
    saved = null;
  }
  res.clearCookie(STATE_COOKIE, { path: '/' });

  const { code, state } = req.query;
  if (!code || !state || !saved || saved.state !== state) {
    return fail('انتهت صلاحية الجلسة، أعد المحاولة');
  }

  let identity;
  try {
    const token = await oauth.exchangeCode(code, redirectUriFor(req));
    identity = await oauth.fetchIdentity(token.access_token);
  } catch (err) {
    console.error('discord oauth callback:', err.message);
    return fail('تعذّر التحقق من حسابك بديسكورد');
  }

  // ── نية: ربط حساب حالي ─────────────────────────────────────────
  if (saved.intent === 'link') {
    const conflict = db
      .prepare('SELECT id FROM admins WHERE discord_user_id = ? AND id != ?')
      .get(identity.id, saved.adminId);
    if (conflict) return res.redirect('/?linkError=taken');

    db.prepare('UPDATE admins SET discord_user_id = ? WHERE id = ?').run(identity.id, saved.adminId);
    return res.redirect('/?linked=1');
  }

  // ── نية: تسجيل دخول ─────────────────────────────────────────────
  const admin = db
    .prepare('SELECT id, must_change_pin AS mustChangePin FROM admins WHERE discord_user_id = ?')
    .get(identity.id);

  if (admin) {
    const { token, expiresAt } = auth.createSessionFor(admin.id);
    db.prepare("UPDATE admins SET last_login_at = datetime('now') WHERE id = ?").run(admin.id);
    res.cookie(auth.SESSION_COOKIE, token, {
      httpOnly: true,
      secure: req.secure || req.headers['x-forwarded-proto'] === 'https',
      sameSite: 'lax',
      expires: expiresAt,
      path: '/',
    });
    return res.redirect(admin.mustChangePin ? '/change-pin' : '/');
  }

  // ما له حساب — نتحقق من رتبته الفعلية بالسيرفر (لا نصدّق ما قد يكتبه)
  // ونحفظ هوية موقَّعة مؤقتة يقرأها /request-access، فلا يستطيع أحد
  // انتحال معرّف غيره بمجرد كتابته بحقل نصي.
  let rank = null;
  try {
    const member = await discord.getMember(identity.id);
    rank = member ? await discord.highestRoleName(member) : null;
  } catch (err) {
    console.error('discord oauth rank lookup:', err.message);
  }

  const pending = {
    id: identity.id,
    username: identity.username,
    displayName: identity.global_name || identity.username,
    avatar: discord.avatarUrl(identity, 128),
    rank,
  };
  res.cookie(PENDING_COOKIE, JSON.stringify(pending), cookieOpts(req, PENDING_TTL_MS));
  res.redirect('/request-access');
});

router.get('/api/access-requests/pending-identity', (req, res) => {
  let pending;
  try {
    pending = JSON.parse(req.signedCookies?.[PENDING_COOKIE] || 'null');
  } catch {
    pending = null;
  }
  if (!pending) return res.status(404).json({ error: 'سجّل الدخول عبر ديسكورد أولًا' });
  res.json({ identity: pending });
});

module.exports = router;
module.exports.PENDING_COOKIE = PENDING_COOKIE;
