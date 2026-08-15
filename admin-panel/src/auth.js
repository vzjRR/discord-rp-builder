// نظام الدخول بالرقم السري فقط (بدون يوزرنيم) + الجلسات + تحديد Owner.
//
// ما فيه يوزرنيم نبحث فيه، فعند تسجيل الدخول نقارن الرقم المُدخل مع كل
// الأرقام المخزّنة (bcrypt.compare) — عدد الأدمنز صغير فهذا رخيص وآمن.
// لتقليل خطر التخمين (brute force) بما إن ما فيه يوزرنيم يميّز المحاولات:
// معدّل محاولات محدود لكل IP (rateLimitLogin) + bcrypt نفسه بطيء بالتصميم.

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { db } = require('./db');
const permissions = require('./permissions');

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

// ── إنشاء جلسة ───────────────────────────────────────────────────
// مشترك بين الدخول العادي واسترجاع الرقم السري المنسي.
function createSessionFor(adminId, { viaRecovery = false } = {}) {
  const token = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + SESSION_TTL_MS);
  db.prepare('INSERT INTO sessions (token_hash, admin_id, expires_at, via_recovery) VALUES (?, ?, ?, ?)').run(
    hashToken(token),
    adminId,
    expiresAt.toISOString(),
    viaRecovery ? 1 : 0
  );
  return { token, expiresAt };
}

// ── استرجاع رقم المالك من متغيرات البيئة (مسار احتياطي أخير) ────────
// المسار المعتاد للاسترجاع رمز يصل في الخاص (src/pinReset.js)، وهو يكفي
// ما دام حساب المالك مرتبطًا بمعرّف ديسكورد. هذا البديل موجود للحالة
// التي ينكسر فيها ذلك — لا معرّف مرتبط، أو البوت لا يستطيع مراسلته —
// فلا يبقى طريق للدخول إطلاقًا.
//
// يُطبَّق مرة واحدة لكل قيمة (نحفظ بصمتها) حتى لا يعيد متغيّرٌ منسيٌّ في
// الإعدادات تعيينَ الرقم عند كل إقلاع، ويُلزم صاحبه بتغيير الرقم فور
// دخوله فلا تبقى قيمة المتغيّر صالحة للدخول.
async function applyOwnerPinReset() {
  const pin = String(process.env.OWNER_RESET_PIN || '').trim();
  if (!pin) return;

  if (!/^[0-9]{6,32}$/.test(pin)) {
    console.error('❌ OWNER_RESET_PIN لا بد أن يكون أرقامًا فقط، من ٦ إلى ٣٢ رقمًا — تم تجاهله.');
    return;
  }

  const fingerprint = crypto.createHash('sha256').update(pin).digest('hex');
  const applied = db.prepare("SELECT value FROM settings WHERE key = 'owner_reset_fingerprint'").get();
  if (applied?.value === fingerprint) {
    console.warn('⚠️  OWNER_RESET_PIN ما زال موجودًا في الإعدادات وقد استُعمل من قبل — احذفه.');
    return;
  }

  const owner = db.prepare('SELECT id, name FROM admins WHERE is_owner = 1 ORDER BY id ASC LIMIT 1').get();
  if (!owner) return; // لا يوجد مالك بعد — ensureOwnerSeed هو المسؤول عن ذلك

  const pinHash = await hashPin(pin);
  db.prepare('UPDATE admins SET pin_hash = ?, must_change_pin = 1 WHERE id = ?').run(pinHash, owner.id);
  db.prepare('DELETE FROM sessions WHERE admin_id = ?').run(owner.id);
  db.prepare(
    "INSERT INTO settings (key, value) VALUES ('owner_reset_fingerprint', ?) " +
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value'
  ).run(fingerprint);

  console.warn(
    `⚠️  أُعيد تعيين الرقم السري لحساب المالك "${owner.name}" من OWNER_RESET_PIN. ` +
      'سجّل الدخول به الآن وغيّره فورًا، ثم احذف المتغيّر من الإعدادات.'
  );
}

// ── تسجيل الدخول ─────────────────────────────────────────────────
async function login(pin, ip) {
  if (isRateLimited(ip)) {
    return { ok: false, error: 'محاولات كثيرة، أعد المحاولة بعد قليل' };
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
      const { token, expiresAt } = createSessionFor(row.id);
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
      `SELECT s.expires_at, s.via_recovery, a.id, a.name, a.is_owner, a.must_change_pin,
              a.discord_user_id, a.permissions
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
    viaRecovery: Boolean(row.via_recovery),
    permissions: permissions.parse(row.permissions),
  };
}

// ── تغيير الرقم السري (ذاتي — يحتاج الرقم الحالي) ───────────────────
// الاستثناء الوحيد: جلسة نشأت عن استرجاع رقم منسي. صاحبها أثبت هويته
// برمز وصله في الخاص، ولا يعرف رقمه الحالي أصلًا، فطلبه منه يعني ألا
// يستطيع الاسترجاع أحد. تلك الجلسة لا تصلح لغير هذا (بوابة
// mustChangePin تحجب كل ما عداه).
async function changePin(adminId, currentPin, newPin, { skipCurrentPin = false } = {}) {
  const row = db.prepare('SELECT pin_hash FROM admins WHERE id = ?').get(adminId);
  if (!row) return { ok: false, error: 'الحساب غير موجود' };

  if (!skipCurrentPin) {
    const match = await bcrypt.compare(String(currentPin || ''), row.pin_hash);
    if (!match) return { ok: false, error: 'رقمك السري الحالي غير صحيح' };
  }

  const newHash = await hashPin(newPin);
  db.prepare('UPDATE admins SET pin_hash = ?, must_change_pin = 0 WHERE id = ?').run(newHash, adminId);
  // امتياز الاسترجاع يُستهلك بمجرد وضع الرقم الجديد
  db.prepare('UPDATE sessions SET via_recovery = 0 WHERE admin_id = ?').run(adminId);
  return { ok: true };
}

function requireAuth(req, res, next) {
  if (!req.admin) {
    if (req.path.startsWith('/api/')) return res.status(401).json({ error: 'لم تسجّل الدخول' });
    return res.redirect('/login');
  }
  next();
}

function requireOwner(req, res, next) {
  if (!req.admin?.isOwner) {
    if (req.path.startsWith('/api/')) return res.status(403).json({ error: 'هذا الإجراء للمالك وحده' });
    return res.redirect('/');
  }
  next();
}

module.exports = {
  SESSION_COOKIE,
  SESSION_TTL_MS,
  hashPin,
  ensureOwnerSeed,
  applyOwnerPinReset,
  createSessionFor,
  login,
  logout,
  resolveSession,
  changePin,
  requireAuth,
  requireOwner,
};
