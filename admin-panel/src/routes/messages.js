const express = require('express');
const discord = require('../discord');
const { requireAuth } = require('../auth');
const { logAction } = require('../audit');
const { testRedirectUserId } = require('../testMode');

const router = express.Router();

// إرسال بالخلفية بدون ما نوقّف الرد — نفصل بين كل DM بفاصل زمني بسيط
// عشان ما نصطدم برايت-ليمت ديسكورد لو العدد كبير.
async function sendBroadcast(targets, content, actor, scopeLabel) {
  let success = 0;
  let fail = 0;
  for (const userId of targets) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await discord.sendDM(userId, content);
      success++;
    } catch {
      fail++;
    }
    // eslint-disable-next-line no-await-in-loop
    await new Promise((r) => setTimeout(r, 1200));
  }
  await logAction(actor, 'message.dm', `${scopeLabel} — نجح ${success} / فشل ${fail}`);
}

router.post('/api/messages/dm', requireAuth, async (req, res) => {
  const { mode, roleId, userId, content } = req.body || {};
  if (!content || !String(content).trim()) return res.status(400).json({ error: 'الرسالة فارغة' });

  let targets = [];
  let scopeLabel = '';
  try {
    if (mode === 'all') {
      const members = await discord.listAllMembers();
      targets = members.map((m) => m.user.id);
      scopeLabel = `كل الأعضاء (${targets.length})`;
    } else if (mode === 'role') {
      if (!roleId) return res.status(400).json({ error: 'اختر رول' });
      const members = await discord.listMembersByRole(roleId);
      targets = members.map((m) => m.user.id);
      scopeLabel = `أعضاء الرول ${roleId} (${targets.length})`;
    } else if (mode === 'user') {
      if (!userId) return res.status(400).json({ error: 'اكتب ID العضو' });
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

  sendBroadcast(actualTargets, String(content).trim(), req.admin, label).catch((err) =>
    console.error('فشل بث الرسائل الخاصة:', err.message)
  );
});

router.post('/api/messages/announce', requireAuth, async (req, res) => {
  const { channelId, content } = req.body || {};
  if (!content || !String(content).trim()) return res.status(400).json({ error: 'الرسالة فارغة' });
  if (!channelId) return res.status(400).json({ error: 'اختر قناة' });

  const test = testRedirectUserId();
  try {
    if (test) {
      await discord.sendDM(test, String(content).trim());
      await logAction(req.admin, 'message.announce', `(وضع تجربة) إعلان كان بيروح لقناة ${channelId} — تحويل لعضو التجربة`);
    } else {
      await discord.sendChannelMessage(channelId, String(content).trim());
      await logAction(req.admin, 'message.announce', `أرسل إعلان بقناة ${channelId}`);
    }
    res.json({ ok: true, testMode: Boolean(test) });
  } catch (err) {
    console.error('messages/announce:', err.message);
    res.status(502).json({ error: 'تعذّر إرسال الإعلان' });
  }
});

module.exports = router;
