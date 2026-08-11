const express = require('express');
const { requireAuth } = require('../auth');
const { listActions } = require('../audit');

const router = express.Router();

router.get('/api/logs', requireAuth, async (req, res) => {
  const page = Math.max(Number(req.query.page) || 1, 1);
  const result = await listActions({ page, pageSize: 50 });
  res.json(result);
});

module.exports = router;
