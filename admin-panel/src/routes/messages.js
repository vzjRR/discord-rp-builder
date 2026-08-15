const express = require('express');
const discord = require('../discord');
const { requireAuth } = require('../auth');
const { requirePermission } = require('../permissions');
const { logAction } = require('../audit');
const { testRedirectUserId } = require('../testMode');
const { upload, toDiscordFiles, limitRequestSize } = require('../uploads');

const router = express.Router();

// إرسال بالخلفية بدون ما نوقّف الرد — نفصل بين كل DM بفاصل زمني بسيط
// عشان ما نصطدم برايت-ليمت ديسكورد لو العدد كبير.
async function sendBroadcast(targets, content, actor, scopeLabel, files = []) {
  let success = 0;
  let fail = 0;
  for (const userId of targets) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await discord.sendDMWithFiles(userId, content, files);
      success++;
    } catch {
      fail++;
    }
    // eslint-disable-next-line no-await-in-loop
    await new Promise((r) => setTimeout(r, 1200));
  }
  await logAction(actor, 'message.dm', `${scopeLabel} — نجح ${success} / فشل ${fail}`);
}

router.post(
  '/api/messages/dm',
  requireAuth,
  requirePermission('messages.dm'),
  limitRequestSize,
  upload.array('files', 10),
  async (req, res) => {
  const { mode, roleId, userId, content } = req.body || {};
  const files = toDiscordFiles(req.files);
  // رسالة بلا نص مقبولة ما دامت تحمل مرفقًا — كما في ديسكورد نفسه
  if ((!content || !String(content).trim()) && !files.length) {
    return res.status(400).json({ error: 'اكتب نص الرسالة أو أرفق ملفًا' });
  }

  let targets = [];
  let scopeLabel = '';
  try {
    if (mode === 'all') {
      const members = await discord.listAllMembers();
      targets = members.map((m) => m.user.id);
      scopeLabel = `كل الأعضاء (${targets.length})`;
    } else if (mode === 'role') {
      if (!roleId) return res.status(400).json({ error: 'اختر رتبة' });
      const members = await discord.listMembersByRole(roleId);
      targets = members.map((m) => m.user.id);
      scopeLabel = `أعضاء الرول ${roleId} (${targets.length})`;
    } else if (mode === 'user') {
      if (!userId) return res.status(400).json({ error: 'اكتب معرّف العضو' });
      targets = [String(userId)];
      scopeLabel = `العضو ${userId}`;
    } else {
      return res.status(400).json({ error: 'وجهة غير معروفة' });
    }
  } catch (err) {
    console.error('messages/dm target lookup:', err.message);
    return res.status(502).json({ error: 'تعذّر جلب الأعضاء من ديسكورد' });
  }

  const test = testRedirectUserId();
  const actualTargets = test ? [test] : targets;
  const label = test ? `${scopeLabel} — وضع تجربة: تحويل لعضو التجربة` : scopeLabel;

  res.json({ ok: true, targetCount: actualTargets.length, scopeLabel, testMode: Boolean(test) });

  sendBroadcast(actualTargets, String(content || '').trim(), req.admin, label, files).catch((err) =>
    console.error('فشل بث الرسائل الخاصة:', err.message)
  );
  }
);

router.post(
  '/api/messages/announce',
  requireAuth,
  requirePermission('messages.announce'),
  limitRequestSize,
  upload.array('files', 10),
  async (req, res) => {
  const { channelId, content } = req.body || {};
  const files = toDiscordFiles(req.files);
  if ((!content || !String(content).trim()) && !files.length) {
    return res.status(400).json({ error: 'اكتب نص الإعلان أو أرفق ملفًا' });
  }
  if (!channelId) return res.status(400).json({ error: 'اختر قناة' });

  const test = testRedirectUserId();
  try {
    if (test) {
      await discord.sendDMWithFiles(test, String(content || '').trim(), files);
      await logAction(req.admin, 'message.announce', `(وضع تجربة) إعلان كان بيروح لقناة ${channelId} — تحويل لعضو التجربة`);
    } else {
      await discord.sendChannelMessageWithFiles(channelId, String(content || '').trim(), files);
      await logAction(req.admin, 'message.announce', `أرسل إعلان بقناة ${channelId}`);
    }
    res.json({ ok: true, testMode: Boolean(test) });
  } catch (err) {
    console.error('messages/announce:', err.message);
    res.status(502).json({ error: 'تعذّر إرسال الإعلان' });
  }
  }
);

module.exports = router;
