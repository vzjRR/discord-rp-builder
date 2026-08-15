// نظام الدخول بالرقم السري فقط (بدون يوزرنيم) + الجلسات + تحديد Owner.
//
// ما فيه يوزرنيم نبحث فيه، فعند تسجيل الدخول نقارن الرقم المُدخل مع كل
// الأرقام المخزّنة (bcrypt.compare) — عدد الأدمنز صغير فهذا رخيص وآمن.
// لتقليل خطر التخمين (brute force) بما إن ما فيه يوزرنيم يميّز المحاولات:
// معدّل محاولات محدود لكل IP (rateLimitLogin) + bcrypt نفسه بطيء بالتصميم.

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { db } = require('./db');

const SESSION_COOKIE = 'enclave_admin_session';
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 يوم

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

async function hashPin(pin) {
  return bcrypt.hash(pin, 12);
}

// ── تأمين محاولات الدخول ────────────────────────────────────────────
const attempts = new Map(); // ip -> [timestamps]
const MAX_ATTEMPTS = 8;
const WINDOW_MS = 5 * 60 * 1000;

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

// ── إنشاء أول حساب Owner تلقائيًا لو ما فيه ولا حساب بعد ───────────
async function ensureOwnerSeed() {
  const { count } = db.prepare('SELECT COUNT(*) AS count FROM admins WHERE is_owner = 1').get();
  if (count > 0) return;

  const pin = process.env.OWNER_SETUP_PIN;
  if (!pin) {
    console.warn(
      '⚠️  ما فيه حساب Owner بعد وما فيه OWNER_SETUP_PIN بمتغيرات البيئة — ' +
        'ما راح تقدر تسجل دخول للمنصة إطلاقًا. ضيف OWNER_SETUP_PIN وأعد التشغيل.'
    );
    return;
  }

  const name = process.env.OWNER_SETUP_NAME || 'Owner';
  const pinHash = await hashPin(pin);
  db.prepare('INSERT INTO admins (name, pin_hash, is_owner, must_change_pin) VALUES (?, ?, 1, 1)').run(name, pinHash);
  console.log(`✅ تم إنشاء حساب Owner باسم "${name}" من OWNER_SETUP_PIN — سجل دخول فيه وغيّر رقمك السري فورًا.`);
}

// ── تسجيل الدخول ─────────────────────────────────────────────────
async function login(pin, ip) {
  if (isRateLimited(ip)) {
    return { ok: false, error: 'محاولات كثيرة، حاول بعد شوي' };
  }
  recordAttempt(ip);

  if (!pin || typeof pin !== 'string' || pin.length < 4 || pin.length > 32) {
    return { ok: false, error: 'الرقم السري غير صحيح' };
  }

  const rows = db.prepare('SELECT id, name, pin_hash, is_owner, must_change_pin FROM admins').all();
  for (const row of rows) {
    // eslint-disable-next-line no-await-in-loop
    const match = await bcrypt.compare(pin, row.pin_hash);
    if (match) {
      const token = crypto.randomBytes(32).toString('hex');
      const expiresAt = new Date(Date.now() + SESSION_TTL_MS);
      db.prepare('INSERT INTO sessions (token_hash, admin_id, expires_at) VALUES (?, ?, ?)').run(
        hashToken(token),
        row.id,
        expiresAt.toISOString()
      );
      db.prepare("UPDATE admins SET last_login_at = datetime('now') WHERE id = ?").run(row.id);
      return {
        ok: true,
        token,
        expiresAt,
        admin: {
          id: row.id,
          name: row.name,
          isOwner: Boolean(row.is_owner),
          mustChangePin: Boolean(row.must_change_pin),
        },
      };
    }
  }
  return { ok: false, error: 'الرقم السري غير صحيح' };
}

async function logout(token) {
  if (!token) return;
  db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(hashToken(token));
}

async function resolveSession(token) {
  if (!token) return null;
  const row = db
    .prepare(
      `SELECT s.expires_at, a.id, a.name, a.is_owner, a.must_change_pin, a.discord_user_id
         FROM sessions s JOIN admins a ON a.id = s.admin_id
        WHERE s.token_hash = ?`
    )
    .get(hashToken(token));
  if (!row) return null;
  if (new Date(row.expires_at).getTime() < Date.now()) {
    db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(hashToken(token));
    return null;
  }
  return {
    id: row.id,
    name: row.name,
    isOwner: Boolean(row.is_owner),
    mustChangePin: Boolean(row.must_change_pin),
    discordUserId: row.discord_user_id || null,
  };
}

// ── تغيير الرقم السري (ذاتي — يحتاج الرقم الحالي) ───────────────────
async function changePin(adminId, currentPin, newPin) {
  const row = db.prepare('SELECT pin_hash FROM admins WHERE id = ?').get(adminId);
  if (!row) return { ok: false, error: 'الحساب غير موجود' };

  const match = await bcrypt.compare(String(currentPin || ''), row.pin_hash);
  if (!match) return { ok: false, error: 'رقمك السري الحالي غير صحيح' };

  const newHash = await hashPin(newPin);
  db.prepare('UPDATE admins SET pin_hash = ?, must_change_pin = 0 WHERE id = ?').run(newHash, adminId);
  return { ok: true };
}

function requireAuth(req, res, next) {
  if (!req.admin) {
    if (req.path.startsWith('/api/')) return res.status(401).json({ error: 'غير مسجل دخول' });
    return res.redirect('/login');
  }
  next();
}

function requireOwner(req, res, next) {
  if (!req.admin?.isOwner) {
    if (req.path.startsWith('/api/')) return res.status(403).json({ error: 'صلاحية Owner فقط' });
    return res.redirect('/');
  }
  next();
}

module.exports = {
  SESSION_COOKIE,
  SESSION_TTL_MS,
  hashPin,
  ensureOwnerSeed,
  login,
  logout,
  resolveSession,
  changePin,
  requireAuth,
  requireOwner,
};
