const express = require('express');
const discord = require('../discord');
const { requireAuth } = require('../auth');
const { requirePermission } = require('../permissions');
const { logAction } = require('../audit');
const { testRedirectUserId } = require('../testMode');

const router = express.Router();

function reasonOf(req) {
  const r = req.body?.reason;
  return r && String(r).trim() ? String(r).trim() : `عبر منصة الإدارة — ${req.admin.name}`;
}

router.post('/api/moderation/kick', requireAuth, requirePermission('moderation.kick'), async (req, res) => {
  const { userId } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'اكتب معرّف العضو' });
  try {
    await discord.kickMember(userId, reasonOf(req));
    await logAction(req.admin, 'moderation.kick', `طرد العضو ${userId} — ${reasonOf(req)}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('moderation/kick:', err.message);
    res.status(502).json({ error: 'تعذّر طرد العضو' });
  }
});

router.post('/api/moderation/ban', requireAuth, requirePermission('moderation.ban'), async (req, res) => {
  const { userId, deleteMessageDays } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'اكتب معرّف العضو' });
  const days = Math.min(Math.max(Number(deleteMessageDays) || 0, 0), 7);
  try {
    await discord.banMember(userId, { reason: reasonOf(req), deleteMessageSeconds: days * 86400 });
    await logAction(req.admin, 'moderation.ban', `حظر العضو ${userId} — ${reasonOf(req)}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('moderation/ban:', err.message);
    res.status(502).json({ error: 'تعذّر حظر العضو' });
  }
});

router.post('/api/moderation/unban', requireAuth, requirePermission('moderation.ban'), async (req, res) => {
  const { userId } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'اكتب معرّف العضو' });
  try {
    await discord.unbanMember(userId, reasonOf(req));
    await logAction(req.admin, 'moderation.unban', `فك حظر العضو ${userId}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('moderation/unban:', err.message);
    res.status(502).json({ error: 'تعذّر رفع الحظر — تأكد من أن هذا المعرّف محظور فعلًا' });
  }
});

router.post('/api/moderation/timeout', requireAuth, requirePermission('moderation.timeout'), async (req, res) => {
  const { userId, minutes } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'اكتب معرّف العضو' });
  const mins = Number(minutes) || 0;
  try {
    await discord.timeoutMember(userId, mins, reasonOf(req));
    await logAction(
      req.admin,
      'moderation.timeout',
      mins > 0 ? `تايم أوت للعضو ${userId} لمدة ${mins} دقيقة — ${reasonOf(req)}` : `رفع التايم أوت عن العضو ${userId}`
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('moderation/timeout:', err.message);
    res.status(502).json({ error: 'تعذّر ضبط التايم أوت' });
  }
});

router.post('/api/moderation/warn', requireAuth, requirePermission('moderation.warn'), async (req, res) => {
  const { userId, reason } = req.body || {};
  if (!userId) return res.status(400).json({ error: 'اكتب معرّف العضو' });
  if (!reason || !String(reason).trim()) return res.status(400).json({ error: 'اكتب سبب التحذير' });

  const test = testRedirectUserId();
  const target = test || userId;
  const text = `⚠️ تحذير رسمي من إدارة السيرفر:\n${String(reason).trim()}`;
  try {
    await discord.sendDM(target, text);
    await logAction(
      req.admin,
      'moderation.warn',
      test ? `(وضع تجربة) تحذير كان بيروح للعضو ${userId} — ${reason}` : `حذّر العضو ${userId} — ${reason}`
    );
    res.json({ ok: true, testMode: Boolean(test) });
  } catch (err) {
    console.error('moderation/warn:', err.message);
    res.status(502).json({ error: 'تعذّر إرسال التحذير — قد تكون رسائله الخاصة مغلقة' });
  }
});

router.post('/api/moderation/purge', requireAuth, requirePermission('moderation.purge'), async (req, res) => {
  const { channelId, count } = req.body || {};
  if (!channelId) return res.status(400).json({ error: 'اختر قناة' });
  const n = Math.min(Math.max(Number(count) || 0, 1), 500);
  try {
    const deleted = await discord.purgeMessages(channelId, n);
    await logAction(req.admin, 'moderation.purge', `حذف ${deleted} رسالة بقناة ${channelId}`);
    res.json({ ok: true, deleted });
  } catch (err) {
    console.error('moderation/purge:', err.message);
    res.status(502).json({ error: 'تعذّر حذف الرسائل' });
  }
});

router.post('/api/moderation/lock', requireAuth, requirePermission('moderation.lock'), async (req, res) => {
  const { channelId } = req.body || {};
  if (!channelId) return res.status(400).json({ error: 'اختر قناة' });
  try {
    await discord.lockChannel(channelId);
    await logAction(req.admin, 'moderation.lock', `قفل قناة ${channelId}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('moderation/lock:', err.message);
    res.status(502).json({ error: 'تعذّر قفل القناة' });
  }
});

router.post('/api/moderation/unlock', requireAuth, requirePermission('moderation.lock'), async (req, res) => {
  const { channelId } = req.body || {};
  if (!channelId) return res.status(400).json({ error: 'اختر قناة' });
  try {
    await discord.unlockChannel(channelId);
    await logAction(req.admin, 'moderation.unlock', `فتح قناة ${channelId}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('moderation/unlock:', err.message);
    res.status(502).json({ error: 'تعذّر فتح القناة' });
  }
});

module.exports = router;
