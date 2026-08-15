// معاينة الرسائل — يرسل نسخة من كل نوع رسالة تصدر عن المنصة إلى حساب
// المالك، ليراها كما يستلمها العضو تمامًا (بالإطار وأيقونة السيرفر والتوقيع)
// قبل أن تُرسل إلى أي شخص فعليًا.
//
// محصور بالمالك: يرسل رسائل خاصة، ولا يصح أن يُتاح لأي حساب آخر.

const express = require('express');
const { requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');
const { sendBrandedDM } = require('../messageFormat');
const { publicBaseUrl } = require('../publicUrl');
const { readOnboardingTemplate, readRevocationTemplate, fillTemplate } = require('../templates');

const router = express.Router();
const guard = [requireAuth, requireOwner];

const DISCORD_ID_RE = /^[0-9]{15,25}$/;

function buildSamples(req) {
  const platformUrl = publicBaseUrl(req);
  const sampleName = req.admin?.name || 'العضو';

  return [
    {
      key: 'onboarding',
      label: 'رسالة إنشاء حساب جديد بالمنصة',
      title: '١) رسالة إنشاء حساب بالمنصة',
      content: fillTemplate(readOnboardingTemplate(), {
        name: sampleName,
        pin: '482913',
        platformUrl,
      }),
    },
    {
      key: 'revocation',
      label: 'رسالة سحب الصلاحية',
      title: '٢) رسالة سحب الصلاحية',
      content: fillTemplate(readRevocationTemplate(), { name: sampleName, platformUrl }),
    },
    {
      key: 'warning',
      label: 'رسالة تحذير من الإشراف',
      title: '٣) رسالة تحذير',
      content:
        '⚠️ **تحذير رسمي من إدارة السيرفر:**\n\nمخالفة قوانين النقاش داخل القنوات العامة.\n\n' +
        'يُرجى الالتزام بالقوانين، فتكرار المخالفة قد يؤدي إلى إجراء أشد.',
    },
    {
      key: 'broadcast',
      label: 'رسالة خاصة جماعية',
      title: '٤) رسالة خاصة جماعية',
      content:
        'مرحبًا بكم جميعًا 👋\n\nهذا نموذج للرسالة الجماعية التي تُرسل إلى كل الأعضاء ' +
        'أو إلى أصحاب رتبة محددة من المنصة.\n\nيدعم النص **التنسيق العريض** و*المائل* ' +
        'و__تحته خط__ و~~المشطوب~~ و`الكود` و||المخفي||.',
    },
    {
      key: 'announcement',
      label: 'إعلان داخل قناة',
      title: '٥) إعلان داخل قناة',
      content:
        '📢 **إعلان مهم**\n\nهذا نموذج للإعلان الذي يُنشر داخل قناة يختارها المسؤول.\n\n' +
        '> يظهر الاقتباس بهذا الشكل\n\n• عنصر أول\n• عنصر ثانٍ',
    },
    {
      key: 'access_request',
      label: 'إشعار طلب دخول جديد',
      title: '٦) إشعار طلب دخول جديد (يصلك أنت)',
      content:
        '🔔 **طلب دخول جديد لمنصة الإدارة**\n\n' +
        'مُعرّف العضو: 1234567890123456789\n' +
        'ملاحظته: أرغب في المساعدة بالإشراف\n\n' +
        'راجع الطلب وأنشئ له حسابًا من صفحة «إدارة الحسابات».',
    },
  ];
}

router.get('/api/preview/messages', guard, (req, res) => {
  res.json({ samples: buildSamples(req).map(({ key, label }) => ({ key, label })) });
});

router.post('/api/preview/messages', guard, async (req, res) => {
  const target = String(req.body?.targetUserId || '').trim();
  if (!DISCORD_ID_RE.test(target)) {
    return res.status(400).json({ error: 'مُعرّف حساب ديسكورد غير صحيح' });
  }

  const only = req.body?.only;
  let samples = buildSamples(req);
  if (Array.isArray(only) && only.length) samples = samples.filter((s) => only.includes(s.key));
  if (!samples.length) return res.status(400).json({ error: 'لم يُحدَّد أي نوع رسالة' });

  const sent = [];
  const failed = [];
  for (const sample of samples) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await sendBrandedDM(target, { content: sample.content, title: sample.title });
      sent.push(sample.key);
    } catch (err) {
      failed.push({ key: sample.key, reason: err.message });
    }
    // eslint-disable-next-line no-await-in-loop
    await new Promise((r) => setTimeout(r, 900)); // مباعدة بسيطة تجنبًا لحد المعدل
  }

  await logAction(
    req.admin,
    'preview.send',
    `أرسل معاينة الرسائل إلى ${target} — نجح ${sent.length} وفشل ${failed.length}`
  );
  res.json({ ok: true, sent, failed });
});

module.exports = router;
