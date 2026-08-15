const express = require('express');
const { requirePermission } = require('../permissions');
const { requireAuth, requireOwner } = require('../auth');
const { listActions, clearActions } = require('../audit');

const router = express.Router();

router.get('/api/logs', requireAuth, requirePermission('logs.view'), async (req, res) => {
  const page = Math.max(Number(req.query.page) || 1, 1);
  const result = await listActions({ page, pageSize: 50 });
  res.json(result);
});

// مسح السجل — للمالك وحده: السجل هو أداة المحاسبة على ما يجري في المنصة،
// فلا يصح أن يتمكن أي مشرف من محو أثر أفعاله.
router.delete('/api/logs', requireAuth, requireOwner, async (req, res) => {
  const removed = clearActions(req.admin);
  res.json({ ok: true, removed });
});

module.exports = router;
