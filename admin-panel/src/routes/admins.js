const express = require('express');
const { db } = require('../db');
const { hashPin, requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');
const { testRedirectUserId } = require('../testMode');
const { publicBaseUrl } = require('../publicUrl');
const { sendBrandedDM } = require('../messageFormat');
const tpl = require('../templates');
const perms = require('../permissions');

const router = express.Router();
const guard = [requireAuth, requireOwner];

const PIN_RE = /^[0-9]{4,32}$/;

// يُلحق برسالة التعريف: من يستلم حسابًا يحتاج أن يعرف حدوده، وإلا جرّب
// ما ليس له فظنّ المنصة معطلة.
function permissionsBlock(isOwner, serialized) {
  if (isOwner) return '\n\n**صلاحياتك:** كاملة، بما فيها إدارة حسابات المنصة.';
  const list = perms.parse(serialized) || [];
  if (!list.length) return '\n\n**صلاحياتك:** لم تُمنح أي صلاحية بعد. راجع المالك.';
  return `\n\n**صلاحياتك في المنصة:**\n${list.map((k) => `• ${perms.ALL[k]}`).join('\n')}`;
}

router.get('/api/admins', guard, (req, res) => {
  const rows = db
    .prepare(
      `SELECT id, name, discord_user_id AS discordUserId, is_owner AS isOwner,
              must_change_pin AS mustChangePin, created_at AS createdAt,
              last_login_at AS lastLoginAt, permissions
         FROM admins ORDER BY created_at ASC`
    )
    .all()
    .map((r) => {
      const parsed = perms.parse(r.permissions);
      return {
        ...r,
        isOwner: Boolean(r.isOwner),
        mustChangePin: Boolean(r.mustChangePin),
        permissions: perms.effective({ isOwner: Boolean(r.isOwner), permissions: parsed }),
        // حساب أُنشئ قبل الميزة: صلاحياته كاملة ضمنًا ولم يخترها أحد
        permissionsExplicit: parsed !== null,
      };
    });
  res.json({ admins: rows, available: perms.ALL });
});

// تعديل صلاحيات حساب — المالك وحده، ولا تُمَسّ صلاحيات حساب مالك
router.put('/api/admins/:id/permissions', guard, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const target = db.prepare('SELECT name, is_owner AS isOwner FROM admins WHERE id = ?').get(id);
  if (!target) return res.status(404).json({ error: 'الحساب غير موجود' });
  if (target.isOwner) {
    return res.status(400).json({ error: 'حساب المالك يملك كل الصلاحيات بطبيعته' });
  }

  const list = perms.normalize(req.body?.permissions);
  db.prepare('UPDATE admins SET permissions = ? WHERE id = ?').run(perms.serialize(list), id);

  await logAction(
    req.admin,
    'admin.permissions',
    `عدّل صلاحيات "${target.name}" — ${list.length ? list.map((k) => perms.ALL[k]).join('، ') : 'بلا صلاحيات'}`
  );
  res.json({ ok: true, permissions: list });
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
  const { name, pin, isOwner, discordUserId, permissions: requested } = req.body || {};
  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'اسم العضو مطلوب' });
  }
  if (!PIN_RE.test(pin || '')) {
    return res.status(400).json({ error: 'الرقم السري أرقام فقط، من ٤ إلى ٣٢ رقمًا' });
  }

  // المالك يملك كل شيء ضمنًا فلا نخزّن له قائمة. وغيره: ما اختاره المالك،
  // فإن لم يختر شيئًا فالحدّ الأدنى (اطّلاع فقط) لا صلاحيات كاملة.
  const granted = isOwner
    ? null
    : perms.serialize(Array.isArray(requested) ? requested : perms.DEFAULT_KEYS);

  const pinHash = await hashPin(pin);
  const info = db
    .prepare(
      'INSERT INTO admins (name, pin_hash, is_owner, discord_user_id, must_change_pin, permissions) VALUES (?, ?, ?, ?, 1, ?)'
    )
    .run(name.trim(), pinHash, isOwner ? 1 : 0, discordUserId || null, granted);
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
        content:
          tpl.fillTemplate(tpl.readOnboardingTemplate(), {
            name: name.trim(),
            pin,
            platformUrl: publicBaseUrl(req),
          }) + permissionsBlock(isOwner, granted),
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
