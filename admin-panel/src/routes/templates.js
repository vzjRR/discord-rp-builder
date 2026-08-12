// تعديل نصوص الرسائل الثابتة (رسالة الترحيب / رسالة الخاص) من المنصة —
// نكتب التعديلات لملف JSON على نفس الـ Volume، وwelcome-bot يقرأه بكل
// حدث انضمام عضو جديد بدل القيم الافتراضية بـ config/welcome.js لو موجود.
//
// المشروعين (admin-panel وwelcome-bot) يشتغلون بنفس الحاوية على Railway
// (شوف start-merged.sh بجذر المستودع) فنقدر نقرأ القيم الافتراضية مباشرة
// من welcome-bot/config/welcome.js بدل ما نكررها هنا وتصير لها نسختين.

const express = require('express');
const fs = require('fs');
const path = require('path');
const { requireAuth } = require('../auth');
const { logAction } = require('../audit');

const router = express.Router();
const OVERRIDE_PATH = process.env.MESSAGE_TEMPLATES_PATH || '/data/message-templates.json';

let defaults = { contentTemplate: '', dmMessage: '' };
try {
  // eslint-disable-next-line import/no-unresolved, global-require
  defaults = require('../../../welcome-bot/config/welcome.js');
} catch (err) {
  console.warn('⚠️  ما قدرنا نجيب القيم الافتراضية من welcome-bot/config/welcome.js:', err.message);
}

function readOverrides() {
  try {
    return JSON.parse(fs.readFileSync(OVERRIDE_PATH, 'utf8'));
  } catch {
    return {};
  }
}

router.get('/api/templates', requireAuth, (req, res) => {
  const overrides = readOverrides();
  res.json({
    contentTemplate: overrides.contentTemplate ?? defaults.contentTemplate,
    dmMessage: overrides.dmMessage ?? defaults.dmMessage,
    isCustom: {
      contentTemplate: overrides.contentTemplate !== undefined,
      dmMessage: overrides.dmMessage !== undefined,
    },
  });
});

router.put('/api/templates', requireAuth, async (req, res) => {
  const { contentTemplate, dmMessage } = req.body || {};
  if (!contentTemplate || !String(contentTemplate).trim()) {
    return res.status(400).json({ error: 'نص رسالة الترحيب فاضي' });
  }
  if (!dmMessage || !String(dmMessage).trim()) {
    return res.status(400).json({ error: 'نص الرسالة الخاصة فاضي' });
  }

  fs.mkdirSync(path.dirname(OVERRIDE_PATH), { recursive: true });
  fs.writeFileSync(OVERRIDE_PATH, JSON.stringify({ contentTemplate, dmMessage }, null, 2));

  await logAction(req.admin, 'templates.update', 'عدّل نصوص الرسائل الثابتة (رسالة الترحيب / رسالة الخاص)');
  res.json({ ok: true });
});

router.post('/api/templates/reset', requireAuth, async (req, res) => {
  try {
    fs.unlinkSync(OVERRIDE_PATH);
  } catch {
    // أصلًا ما فيه تعديل محفوظ — تجاهل
  }
  await logAction(req.admin, 'templates.update', 'رجّع الرسائل الثابتة للقيم الافتراضية');
  res.json({ ok: true });
});

module.exports = router;
