const express = require('express');
const { db } = require('../db');
const { hashPin, requireAuth, requireOwner } = require('../auth');
const { logAction } = require('../audit');

const router = express.Router();
const guard = [requireAuth, requireOwner];

const PIN_RE = /^[0-9]{4,32}$/;

router.get('/api/admins', guard, (req, res) => {
  const rows = db
    .prepare(
      'SELECT id, name, is_owner AS isOwner, created_at AS createdAt, last_login_at AS lastLoginAt FROM admins ORDER BY created_at ASC'
    )
    .all()
    .map((r) => ({ ...r, isOwner: Boolean(r.isOwner) }));
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
  const info = db
    .prepare('INSERT INTO admins (name, pin_hash, is_owner) VALUES (?, ?, ?)')
    .run(name.trim(), pinHash, isOwner ? 1 : 0);
  const row = db
    .prepare('SELECT id, name, is_owner AS isOwner, created_at AS createdAt FROM admins WHERE id = ?')
    .get(info.lastInsertRowid);

  await logAction(req.admin, 'admin.create', `أنشأ حساب "${name.trim()}"${isOwner ? ' (Owner)' : ''}`);
  res.json({ admin: { ...row, isOwner: Boolean(row.isOwner) } });
});

router.delete('/api/admins/:id', guard, async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: 'معرّف غير صالح' });

  const target = db.prepare('SELECT name, is_owner AS isOwner FROM admins WHERE id = ?').get(id);
  if (!target) return res.status(404).json({ error: 'الحساب غير موجود' });

  if (target.isOwner) {
    const { count } = db.prepare('SELECT COUNT(*) AS count FROM admins WHERE is_owner = 1').get();
    if (count <= 1) {
      return res.status(400).json({ error: 'ما تقدر تحذف آخر حساب Owner بالمنصة' });
    }
  }

  db.prepare('DELETE FROM admins WHERE id = ?').run(id);
  await logAction(req.admin, 'admin.revoke', `حذف حساب "${target.name}"`);
  res.json({ ok: true });
});

module.exports = router;
