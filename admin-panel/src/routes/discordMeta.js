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
    res.json({
      roles: roles.map((r) => ({
        id: r.id,
        name: r.name,
        color: r.color,
        permissions: r.permissions,
        hoist: r.hoist,
        mentionable: r.mentionable,
      })),
    });
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
        avatarUrl: discord.avatarUrl(m.user, 64),
      })),
    });
  } catch (err) {
    console.error('discord/members:', err.message);
    res.status(502).json({ error: 'تعذّر البحث عن الأعضاء' });
  }
});

router.get('/api/discord/bans', requireAuth, async (req, res) => {
  const query = String(req.query.query || '').trim().toLowerCase();
  try {
    const bans = await discord.listBans();
    const mapped = bans.map((b) => ({
      id: b.user.id,
      username: b.user.username,
      reason: b.reason,
      avatarUrl: discord.avatarUrl(b.user, 64),
    }));
    const filtered = query
      ? mapped.filter((b) => b.username.toLowerCase().includes(query) || b.id.includes(query))
      : mapped;
    res.json({ bans: filtered.slice(0, 25) });
  } catch (err) {
    console.error('discord/bans:', err.message);
    res.status(502).json({ error: 'تعذّر جلب قائمة المحظورين' });
  }
});

router.get('/api/discord/all-channels', requireAuth, async (req, res) => {
  try {
    const channels = await discord.listAllChannelsAndCategories();
    res.json({
      channels: channels.map((c) => ({
        id: c.id,
        name: c.name,
        type: c.type,
        parentId: c.parent_id,
        topic: c.topic ?? null,
        position: c.position,
      })),
    });
  } catch (err) {
    console.error('discord/all-channels:', err.message);
    res.status(502).json({ error: 'تعذّر جلب القنوات من ديسكورد' });
  }
});

module.exports = router;
