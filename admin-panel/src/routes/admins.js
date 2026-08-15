const express = require('express');
const { db } = require('../db');
const { hashPin, requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');
const { testRedirectUserId } = require('../testMode');
const { publicBaseUrl } = require('../publicUrl');
const { sendBrandedDM } = require('../messageFormat');
const tpl = require('../templates');

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

// ── نصوص رسائل الحسابات (الترحيب وسحب الصلاحية) ────────────────────
// النصوص وقراءتها وحفظها في src/templates.js، وهنا نعرضها للتعديل فقط.
const TEMPLATE_KINDS = {
  onboarding: {
    read: tpl.readOnboardingTemplate,
    isCustom: tpl.isOnboardingCustom,
    write: tpl.writeOnboarding,
    reset: tpl.resetOnboarding,
    label: 'رسالة إنشاء الحساب',
  },
  revocation: {
    read: tpl.readRevocationTemplate,
    isCustom: tpl.isRevocationCustom,
    write: tpl.writeRevocation,
    reset: tpl.resetRevocation,
    label: 'رسالة سحب الصلاحية',
  },
};

router.get('/api/admins/templates/:kind', guard, (req, res) => {
  const kind = TEMPLATE_KINDS[req.params.kind];
  if (!kind) return res.status(404).json({ error: 'نوع رسالة غير معروف' });
  res.json({ message: kind.read(), isCustom: kind.isCustom() });
});

router.put('/api/admins/templates/:kind', guard, async (req, res) => {
  const kind = TEMPLATE_KINDS[req.params.kind];
  if (!kind) return res.status(404).json({ error: 'نوع رسالة غير معروف' });
  const { message } = req.body || {};
  if (!message || !String(message).trim()) {
    return res.status(400).json({ error: 'نص الرسالة فارغ' });
  }
  kind.write(message);
  await logAction(req.admin, 'template.update', `عدّل ${kind.label}`);
  res.json({ ok: true });
});

router.post('/api/admins/templates/:kind/reset', guard, async (req, res) => {
  const kind = TEMPLATE_KINDS[req.params.kind];
  if (!kind) return res.status(404).json({ error: 'نوع رسالة غير معروف' });
  kind.reset();
  await logAction(req.admin, 'template.update', `أعاد ${kind.label} إلى النص الافتراضي`);
  res.json({ ok: true });
});

// المسارات القديمة لرسالة الترحيب — مُبقاة كي لا تنكسر الواجهة الحالية
router.get('/api/admins/onboarding-message', guard, (req, res) =>
  res.json({ message: tpl.readOnboardingTemplate(), isCustom: tpl.isOnboardingCustom() })
);

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
    try {
      await sendBrandedDM(target, {
        title: 'حساب جديد في منصة الإدارة',
        content: tpl.fillTemplate(tpl.readOnboardingTemplate(), {
          name: name.trim(),
          pin,
          platformUrl: publicBaseUrl(req),
        }),
      });
      dmSent = true;
      await logAction(
        req.admin,
        'admin.onboard_dm',
        test
          ? `(وضع تجربة) رسالة التعريف كانت ستُرسل إلى العضو ${discordUserId} — حُوّلت إلى عضو التجربة`
          : `أرسل رسالة التعريف بالمنصة إلى حساب "${name.trim()}"`
      );
    } catch (err) {
      dmError = 'أُنشئ الحساب بنجاح، لكن تعذّر إرسال رسالة التعريف (قد تكون خصوصياته مغلقة) — سلّمه رقمه السري يدويًا.';
      console.error('admin onboarding DM failed:', err.message);
    }
  }

  res.json({ admin: { ...row, isOwner: Boolean(row.isOwner) }, dmSent, dmError });
});

router.delete('/api/admins/:id', guard, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const target = db
    .prepare('SELECT name, is_owner AS isOwner, discord_user_id AS discordUserId FROM admins WHERE id = ?')
    .get(id);
  if (!target) return res.status(404).json({ error: 'الحساب غير موجود' });

  if (target.isOwner) {
    const { count } = db.prepare('SELECT COUNT(*) AS count FROM admins WHERE is_owner = 1').get();
    if (count <= 1) {
      return res.status(400).json({ error: 'لا يمكن حذف آخر حساب مالك في المنصة' });
    }
  }

  // حذف الحساب يحذف جلساته تلقائيًا (ON DELETE CASCADE) فيخرج فورًا
  db.prepare('DELETE FROM admins WHERE id = ?').run(id);
  await logAction(req.admin, 'admin.revoke', `حذف حساب "${target.name}"`);

  // نُعلم العضو بسحب صلاحيته — بعد الحذف، فلا يُبقيه فشل الإرسال بصلاحية
  let dmSent = false;
  let dmError = null;
  if (target.discordUserId) {
    const test = testRedirectUserId();
    const notifyTarget = test || target.discordUserId;
    try {
      await sendBrandedDM(notifyTarget, {
        title: 'سحب صلاحية الدخول',
        content: tpl.fillTemplate(tpl.readRevocationTemplate(), {
          name: target.name,
          platformUrl: publicBaseUrl(req),
        }),
      });
      dmSent = true;
      await logAction(
        req.admin,
        'admin.revoke_dm',
        test
          ? `(وضع تجربة) إشعار سحب الصلاحية كان سيُرسل إلى ${target.discordUserId} — حُوّل إلى عضو التجربة`
          : `أرسل إشعار سحب الصلاحية إلى "${target.name}"`
      );
    } catch (err) {
      dmError = 'أُلغي الحساب بنجاح، لكن تعذّر إبلاغ العضو (قد تكون خصوصياته مغلقة).';
      console.error('admin revocation DM failed:', err.message);
    }
  }

  res.json({ ok: true, dmSent, dmError });
});

module.exports = router;
