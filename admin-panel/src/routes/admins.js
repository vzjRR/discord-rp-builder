const express = require('express');
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
      'SELECT id, name, discord_user_id AS discordUserId, is_owner AS isOwner, created_at AS createdAt, last_login_at AS lastLoginAt FROM admins ORDER BY created_at ASC'
    )
    .all()
    .map((r) => ({ ...r, isOwner: Boolean(r.isOwner) }));
  res.json({ admins: rows });
});

function buildOnboardingMessage({ name, pin, platformUrl }) {
  return `🔐 **تم إنشاء حساب لك بمنصة إدارة Enclave RP**

مرحبًا ${name}! صار عندك دخول لمنصة التحكم الخاصة بالسيرفر، تقدر منها:
• إرسال رسائل خاصة وإعلانات للأعضاء
• أدوات إشراف (طرد / حظر / تايم أوت / حذف رسائل...)
• إدارة قنوات ورولات السيرفر

**رابط الدخول:**
${platformUrl}

**رقمك السري:**
${pin}

⚠️ **تحذير مهم:** هذا الرقم يعطيك صلاحيات شبه كاملة بالتحكم بالسيرفر. **ممنوع تشاركه مع أي أحد** — هو خاص فيك بس، ولو وصل لشخص ثاني بيقدر يتحكم بالسيرفر متنكّرًا باسمك.`;
}

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
    .prepare('INSERT INTO admins (name, pin_hash, is_owner, discord_user_id) VALUES (?, ?, ?, ?)')
    .run(name.trim(), pinHash, isOwner ? 1 : 0, discordUserId || null);
  const row = db
    .prepare('SELECT id, name, discord_user_id AS discordUserId, is_owner AS isOwner, created_at AS createdAt FROM admins WHERE id = ?')
    .get(info.lastInsertRowid);

  await logAction(req.admin, 'admin.create', `أنشأ حساب "${name.trim()}"${isOwner ? ' (Owner)' : ''}`);

  let dmSent = false;
  let dmError = null;
  if (discordUserId) {
    const test = testRedirectUserId();
    const target = test || discordUserId;
    const platformUrl = `${req.protocol}://${req.get('host')}`;
    try {
      await discord.sendDM(target, buildOnboardingMessage({ name: name.trim(), pin, platformUrl }));
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
