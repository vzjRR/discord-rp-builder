// حالة سيرفر FiveM — للاطّلاع فقط. مُتاحة لأي حساب مسجّل دخول بلا صلاحية
// خاصة (نفس مستوى بيانات ديسكورد العامة بلوحة discordMeta)، وتُخزَّن
// مؤقتًا لتفادي إغراق قائمة سيرفرات FiveM بطلبات عند كل فتح للصفحة الرئيسية.

const express = require('express');
const { requireAuth } = require('../auth');
const fivem = require('../fivem');

const router = express.Router();

const CACHE_TTL_MS = 30 * 1000;
let cache = { at: 0, data: null };

router.get('/api/fivem/status', requireAuth, async (req, res) => {
  if (!fivem.isConfigured()) return res.json({ configured: false });

  if (cache.data && Date.now() - cache.at < CACHE_TTL_MS) {
    return res.json({ configured: true, ...cache.data, cached: true });
  }
  const data = await fivem.getStatus();
  cache = { at: Date.now(), data };
  res.json({ configured: true, ...data, cached: false });
});

module.exports = router;
