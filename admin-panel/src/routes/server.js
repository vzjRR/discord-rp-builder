// إدارة قنوات/كاتجوريز/رولات السيرفر — لازم يكون عند البوت صلاحية
// "Manage Channels" و"Manage Roles" بالسيرفر، ورول البوت لازم يكون أعلى
// بالترتيب من أي رول يحاول يعدّله (قيد أصلي من ديسكورد، مو من الكود).

const express = require('express');
const discord = require('../discord');
const { requireAuth } = require('../auth');
const { logAction } = require('../audit');

const router = express.Router();

// ── قنوات / كاتجوريز ──────────────────────────────────────────────
router.post('/api/server/channels', requireAuth, async (req, res) => {
  const { name, type, parentId, topic } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'اسم القناة مطلوب' });
  const channelType = [0, 2, 4, 5].includes(Number(type)) ? Number(type) : 0;

  try {
    const channel = await discord.createChannel({ name: String(name).trim(), type: channelType, parentId, topic });
    await logAction(req.admin, 'server.channel_create', `أنشأ قناة "${channel.name}"`);
    res.json({ channel });
  } catch (err) {
    console.error('server/channels create:', err.message);
    res.status(502).json({ error: 'تعذّر إنشاء القناة (تأكد إن البوت عنده صلاحية Manage Channels)' });
  }
});

router.patch('/api/server/channels/:id', requireAuth, async (req, res) => {
  const { name, topic, parentId, position } = req.body || {};
  try {
    const channel = await discord.updateChannel(req.params.id, { name, topic, parentId, position });
    await logAction(req.admin, 'server.channel_update', `عدّل قناة "${channel.name}"`);
    res.json({ channel });
  } catch (err) {
    console.error('server/channels update:', err.message);
    res.status(502).json({ error: 'تعذّر تعديل القناة' });
  }
});

router.delete('/api/server/channels/:id', requireAuth, async (req, res) => {
  try {
    await discord.deleteChannel(req.params.id);
    await logAction(req.admin, 'server.channel_delete', `حذف قناة ${req.params.id}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('server/channels delete:', err.message);
    res.status(502).json({ error: 'تعذّر حذف القناة' });
  }
});

// ── رولات ──────────────────────────────────────────────────────
router.get('/api/server/permission-options', requireAuth, (req, res) => {
  res.json({ permissions: Object.keys(discord.PERMISSION_BITS) });
});

router.post('/api/server/roles', requireAuth, async (req, res) => {
  const { name, color, permissions, hoist, mentionable } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'اسم الرول مطلوب' });

  try {
    const role = await discord.createRole({ name: String(name).trim(), color, permissions, hoist, mentionable });
    await logAction(req.admin, 'server.role_create', `أنشأ رول "${role.name}"`);
    res.json({ role });
  } catch (err) {
    console.error('server/roles create:', err.message);
    res.status(502).json({ error: 'تعذّر إنشاء الرول (تأكد إن البوت عنده صلاحية Manage Roles)' });
  }
});

router.patch('/api/server/roles/:id', requireAuth, async (req, res) => {
  const { name, color, permissions, hoist, mentionable } = req.body || {};
  try {
    const role = await discord.updateRole(req.params.id, { name, color, permissions, hoist, mentionable });
    await logAction(req.admin, 'server.role_update', `عدّل رول "${role.name}"`);
    res.json({ role });
  } catch (err) {
    console.error('server/roles update:', err.message);
    res.status(502).json({ error: 'تعذّر تعديل الرول (تأكد إن رول البوت أعلى من هذا الرول بالترتيب)' });
  }
});

router.delete('/api/server/roles/:id', requireAuth, async (req, res) => {
  try {
    await discord.deleteRole(req.params.id);
    await logAction(req.admin, 'server.role_delete', `حذف رول ${req.params.id}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('server/roles delete:', err.message);
    res.status(502).json({ error: 'تعذّر حذف الرول' });
  }
});

module.exports = router;
