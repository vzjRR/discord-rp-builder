// نقاط قراءة بسيطة تغذّي قوائم الاختيار بالواجهة (قنوات/رولات/بحث أعضاء)
// كلها للاستخدام الداخلي فقط بعد تسجيل الدخول — ما تكشف أي شيء عن البوت
// أو النظام، بس بيانات السيرفر العامة (أسماء قنوات/رولات/أعضاء).

const express = require('express');
const discord = require('../discord');
const { requireAuth } = require('../auth');

const router = express.Router();

router.get('/api/discord/guild', requireAuth, async (req, res) => {
  try {
    const guild = await discord.getGuild();
    res.json({
      name: guild.name,
      memberCount: guild.approximate_member_count ?? guild.member_count ?? null,
      iconUrl: discord.iconUrl(guild),
      bannerUrl: discord.bannerUrl(guild),
    });
  } catch (err) {
    console.error('discord/guild:', err.message);
    res.status(502).json({ error: 'تعذّر جلب بيانات السيرفر' });
  }
});

router.get('/api/discord/channels', requireAuth, async (req, res) => {
  try {
    const channels = await discord.listChannels();
    res.json({ channels: channels.map((c) => ({ id: c.id, name: c.name })) });
  } catch (err) {
    console.error('discord/channels:', err.message);
    res.status(502).json({ error: 'تعذّر جلب القنوات من ديسكورد' });
  }
});

router.get('/api/discord/roles', requireAuth, async (req, res) => {
  try {
    const roles = await discord.listRoles();
    res.json({ roles: roles.map((r) => ({ id: r.id, name: r.name, color: r.color })) });
  } catch (err) {
    console.error('discord/roles:', err.message);
    res.status(502).json({ error: 'تعذّر جلب الرولات من ديسكورد' });
  }
});

router.get('/api/discord/members', requireAuth, async (req, res) => {
  const query = String(req.query.query || '').trim();
  if (!query) return res.json({ members: [] });
  try {
    const members = await discord.searchMembers(query);
    res.json({
      members: members.map((m) => ({
        id: m.user.id,
        username: m.user.username,
        nickname: m.nick,
      })),
    });
  } catch (err) {
    console.error('discord/members:', err.message);
    res.status(502).json({ error: 'تعذّر البحث عن الأعضاء' });
  }
});

module.exports = router;
