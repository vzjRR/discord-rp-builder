// حالة السيرفر — للاطّلاع فقط، لا يغيّر شيئًا.
//
// نتيجة الطلب تُخزَّن مؤقتًا لدقيقة: جلب كل الأعضاء من ديسكورد يستهلك عدة
// طلبات، وفتح الصفحة أو تحديثها مرارًا يكرّرها بلا فائدة — والأرقام لا
// تتغيّر خلال دقيقة تغيّرًا يُذكر.

const express = require('express');
const { requireAuth } = require('../auth');
const { requirePermission } = require('../permissions');
const serverStats = require('../serverStats');

const router = express.Router();

const CACHE_TTL_MS = 60 * 1000;
let cache = { at: 0, data: null };

router.get('/api/status', requireAuth, requirePermission('status.view'), async (req, res) => {
  if (cache.data && Date.now() - cache.at < CACHE_TTL_MS) {
    return res.json({ ...cache.data, cached: true });
  }
  try {
    const data = await serverStats.snapshot();
    cache = { at: Date.now(), data };
    res.json({ ...data, cached: false });
  } catch (err) {
    console.error('status snapshot:', err.message);
    res.status(502).json({ error: 'تعذّر جلب حالة السيرفر من ديسكورد' });
  }
});

module.exports = router;
