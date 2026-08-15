const express = require('express');
const fs = require('fs');
const path = require('path');
const { db } = require('../db');
const { hashPin, requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');
const discord = require('../discord');
const { testRedirectUserId } = require('../testMode');

const router = express.Router();
const guard = [requireAuth, requireOwner];

const PIN_RE = /^[0-9]{4,32}$/;

router.get('/api/admins', guard, (req, res) => {
  const rows = db
    .prepare(
      `SELECT id, name, discord_user_id AS discordUserId, is_owner AS isOwner,
              must_change_pin AS mustChangePin, created_at AS createdAt, last_login_at AS lastLoginAt
         FROM admins ORDER BY created_at ASC`
    )
    .all()
    .map((r) => ({ ...r, isOwner: Boolean(r.isOwner), mustChangePin: Boolean(r.mustChangePin) }));
  res.json({ admins: rows });
});

// ── رسالة الترحيب/التعريف بالمنصة — نص افتراضي، Owner يقدر يعدّله ────
// نفس أسلوب templates.js: نص افتراضي بالكود + تعديل اختياري يُحفظ كملف
// JSON على الـ Volume (بدون ما نكرر جدول قاعدة بيانات لسطر نص وحيد).
const ONBOARDING_OVERRIDE_PATH = process.env.ONBOARDING_MESSAGE_PATH || '/data/onboarding-message.json';

const DEFAULT_ONBOARDING_MESSAGE = `🔐 **تم إنشاء حساب لك بمنصة إدارة Enclave RP**

مرحبًا {name}! صار عندك دخول لمنصة التحكم الخاصة بالسيرفر، تقدر منها:
• إرسال رسائل خاصة وإعلانات للأعضاء
• أدوات إشراف (طرد / حظر / تايم أوت / حذف رسائل...)
• إدارة قنوات ورولات السيرفر

**رابط الدخول:**
{platformUrl}

**رقمك السري المؤقت:**
{pin}

⚠️ لازم تغيّر هذا الرقم فور أول تسجيل دخول قبل ما تقدر تستخدم أي شي بالمنصة.

⚠️ **تحذير مهم:** هذا الرقم يعطيك صلاحيات شبه كاملة بالتحكم بالسيرفر. **ممنوع تشاركه مع أي أحد** — هو خاص فيك بس، ولو وصل لشخص ثاني بيقدر يتحكم بالسيرفر متنكّرًا باسمك. لو نسيته، تقدر تطلب رمز جديد من صفحة تسجيل الدخول.`;

function readOnboardingOverride() {
  try {
    return JSON.parse(fs.readFileSync(ONBOARDING_OVERRIDE_PATH, 'utf8')).message;
  } catch {
    return null;
  }
}

function fillTemplate(str, vars) {
  return String(str).replace(/\{(\w+)\}/g, (_, key) => (vars[key] !== undefined ? vars[key] : `{${key}}`));
}

router.get('/api/admins/onboarding-message', guard, (req, res) => {
  const custom = readOnboardingOverride();
  res.json({ message: custom ?? DEFAULT_ONBOARDING_MESSAGE, isCustom: custom !== null });
});

router.put('/api/admins/onboarding-message', guard, async (req, res) => {
  const { message } = req.body || {};
  if (!message || !String(message).trim()) {
    return res.status(400).json({ error: 'نص الرسالة فاضي' });
  }
  fs.mkdirSync(path.dirname(ONBOARDING_OVERRIDE_PATH), { recursive: true });
  fs.writeFileSync(ONBOARDING_OVERRIDE_PATH, JSON.stringify({ message }, null, 2));
  await logAction(req.admin, 'onboarding_message.update', 'عدّل رسالة الترحيب بالمنصة');
  res.json({ ok: true });
});

router.post('/api/admins/onboarding-message/reset', guard, async (req, res) => {
  try {
    fs.unlinkSync(ONBOARDING_OVERRIDE_PATH);
  } catch {
    // ما فيه تعديل محفوظ أصلًا — تجاهل
  }
  await logAction(req.admin, 'onboarding_message.update', 'رجّع رسالة الترحيب بالمنصة للافتراضية');
  res.json({ ok: true });
});

router.post('/api/admins', guard, async (req, res) => {
  const { name, pin, isOwner, discordUserId } = req.body || {};
  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'اسم العضو مطلوب' });
  }
  if (!PIN_RE.test(pin || '')) {
    return res.status(400).json({ error: 'الرقم السري لازم يكون أرقام فقط، من ٤ إلى ٣٢ رقم' });
  }

  const pinHash = await hashPin(pin);
  const info = db
    .prepare('INSERT INTO admins (name, pin_hash, is_owner, discord_user_id, must_change_pin) VALUES (?, ?, ?, ?, 1)')
    .run(name.trim(), pinHash, isOwner ? 1 : 0, discordUserId || null);
  const row = db
    .prepare('SELECT id, name, discord_user_id AS discordUserId, is_owner AS isOwner, created_at AS createdAt FROM admins WHERE id = ?')
    .get(info.lastInsertRowid);

  await logAction(req.admin, 'admin.create', `أنشأ حساب "${name.trim()}"${isOwner ? ' (Owner)' : ''}`);

  // لو فيه طلب دخول معلّق بنفس الـ ID، نعتبره انحل تلقائيًا
  if (discordUserId) {
    db.prepare(
      "UPDATE access_requests SET status = 'approved', resolved_at = datetime('now'), resolved_by_admin_id = ? WHERE discord_user_id = ? AND status = 'pending'"
    ).run(req.admin.id, discordUserId);
  }

  let dmSent = false;
  let dmError = null;
  if (discordUserId) {
    const test = testRedirectUserId();
    const target = test || discordUserId;
    // الدومين الخاص يمر عبر Cloudflare Worker يعيد كتابة الـ Host لدومين
    // الاستضافة، فـ req.get('host') يعطينا دومين الاستضافة الخام — وهذا آخر
    // شي نبي نرسله للأدمن الجديد. الترتيب: المتغيّر الصريح، ثم X-Forwarded-Host
    // اللي يضبطه الـ Worker (req.hostname يقرأه مع trust proxy)، وأخيرًا الطلب.
    const platformUrl =
      process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.hostname || req.get('host')}`;
    const messageTemplate = readOnboardingOverride() ?? DEFAULT_ONBOARDING_MESSAGE;
    try {
      await discord.sendDM(target, fillTemplate(messageTemplate, { name: name.trim(), pin, platformUrl }));
      dmSent = true;
      await logAction(
        req.admin,
        'admin.onboard_dm',
        test
          ? `(وضع تجربة) رسالة تعريف كانت بتروح للعضو ${discordUserId} — تحويل لعضو التجربة`
          : `أرسل رسالة تعريف وترحيب لحساب "${name.trim()}"`
      );
    } catch (err) {
      dmError = 'الحساب انسوى تمام، بس تعذّر إرسال رسالة التعريف (يمكن خصوصياته مقفلة) — سلّمه رقمه يدويًا.';
      console.error('admin onboarding DM failed:', err.message);
    }
  }

  res.json({ admin: { ...row, isOwner: Boolean(row.isOwner) }, dmSent, dmError });
});

router.delete('/api/admins/:id', guard, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const target = db.prepare('SELECT name, is_owner AS isOwner FROM admins WHERE id = ?').get(id);
  if (!target) return res.status(404).json({ error: 'الحساب غير موجود' });

  if (target.isOwner) {
    const { count } = db.prepare('SELECT COUNT(*) AS count FROM admins WHERE is_owner = 1').get();
    if (count <= 1) {
      return res.status(400).json({ error: 'ما تقدر تحذف آخر حساب Owner بالمنصة' });
    }
  }

  db.prepare('DELETE FROM admins WHERE id = ?').run(id);
  await logAction(req.admin, 'admin.revoke', `حذف حساب "${target.name}"`);
  res.json({ ok: true });
});

module.exports = router;
