const express = require('express');
const { pool } = require('../db');
const { hashPin, requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');

const router = express.Router();
const guard = [requireAuth, requireOwner];

const PIN_RE = /^[0-9]{4,32}$/;

router.get('/api/admins', guard, async (req, res) => {
  const { rows } = await pool.query(
    'SELECT id, name, is_owner AS "isOwner", created_at AS "createdAt", last_login_at AS "lastLoginAt" FROM admins ORDER BY created_at ASC'
  );
  res.json({ admins: rows });
});

router.post('/api/admins', guard, async (req, res) => {
  const { name, pin, isOwner } = req.body || {};
  if (!name || typeof name !== 'string' || !name.trim()) {
    return res.status(400).json({ error: 'اسم العضو مطلوب' });
  }
  if (!PIN_RE.test(pin || '')) {
    return res.status(400).json({ error: 'الرقم السري لازم يكون أرقام فقط، من ٤ إلى ٣٢ رقم' });
  }

  const pinHash = await hashPin(pin);
  const { rows } = await pool.query(
    'INSERT INTO admins (name, pin_hash, is_owner) VALUES ($1, $2, $3) RETURNING id, name, is_owner AS "isOwner", created_at AS "createdAt"',
    [name.trim(), pinHash, Boolean(isOwner)]
  );
  await logAction(req.admin, 'admin.create', `أنشأ حساب "${name.trim()}"${isOwner ? ' (Owner)' : ''}`);
  res.json({ admin: rows[0] });
});

router.delete('/api/admins/:id', guard, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const { rows } = await pool.query('SELECT name, is_owner AS "isOwner" FROM admins WHERE id = $1', [id]);
  const target = rows[0];
  if (!target) return res.status(404).json({ error: 'الحساب غير موجود' });

  if (target.isOwner) {
    const { rows: ownerCount } = await pool.query('SELECT COUNT(*)::int AS count FROM admins WHERE is_owner = TRUE');
    if (ownerCount[0].count <= 1) {
      return res.status(400).json({ error: 'ما تقدر تحذف آخر حساب Owner بالمنصة' });
    }
  }

  await pool.query('DELETE FROM admins WHERE id = $1', [id]);
  await logAction(req.admin, 'admin.revoke', `حذف حساب "${target.name}"`);
  res.json({ ok: true });
});

module.exports = router;
