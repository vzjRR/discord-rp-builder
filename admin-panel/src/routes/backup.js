// تنزيل نسخة احتياطية كاملة — للمالك وحده.
//
// الحزمة تحوي كل حسابات المنصة وسجل نشاطها، فمن يملكها يملك معرفة من
// يدير السيرفر ومتى فعل ماذا (وإن كانت الأرقام السرية مُجزّأة لا صريحة).
// لذلك: المالك وحده، ويُسجَّل كل تنزيل في السجل — نسخة تخرج دون أثر
// تعني تسريبًا لا يعرف صاحب المنصة أنه وقع.

const express = require('express');
const { requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');
const { buildBackup } = require('../backup');

const router = express.Router();

router.get('/api/backup', requireAuth, requireOwner, async (req, res) => {
  try {
    const bundle = await buildBackup();
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');

    await logAction(
      req.admin,
      'backup.download',
      `نزّل نسخة احتياطية (${Object.keys(bundle.files).length} ملفًا)`
    );

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="enclave-backup-${stamp}.json"`);
    // لا تُخزَّن في أي وسيط: محتواها حسّاس ولا معنى لتكراره
    res.setHeader('Cache-Control', 'no-store');
    res.send(JSON.stringify(bundle));
  } catch (err) {
    console.error('backup failed:', err);
    res.status(500).json({ error: 'تعذّر إنشاء النسخة الاحتياطية' });
  }
});

module.exports = router;
