// كل تفاعل المنصة مع ديسكورد عبر REST API مباشرة (بدون Gateway/WebSocket) —
// إرسال رسالة، طرد، حظر، تايم أوت... كلها أوامر لحظية ما تحتاج اتصال دائم.
// نفس DISCORD_TOKEN المستخدم بـ welcome-bot / logs-bot.

const API = 'https://discord.com/api/v10';
const token = process.env.DISCORD_TOKEN;
const guildId = process.env.GUILD_ID;

if (!token || !guildId) {
  console.error('❌ DISCORD_TOKEN أو GUILD_ID غير مضبوطين بمتغيرات البيئة.');
  process.exit(1);
}

const SEND_MESSAGES_BIT = '2048'; // 1 << 11

async function request(method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bot ${token}`,
      'Content-Type': 'application/json',
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (res.status === 429) {
    const data = await res.json().catch(() => ({}));
    const retryAfterMs = Math.ceil((data.retry_after || 1) * 1000);
    await new Promise((r) => setTimeout(r, retryAfterMs));
    return request(method, path, body);
  }

  if (res.status === 204) return null;

  const text = await res.text();
  const data = text ? JSON.parse(text) : null;

  if (!res.ok) {
    // ما نطبع/نرجع أي هيدرز أو تفاصيل اتصال — بس كود الحالة ورسالة ديسكورد
    const err = new Error(data?.message || `Discord API error (${res.status})`);
    err.status = res.status;
    err.code = data?.code;
    throw err;
  }

  return data;
}

// ── السيرفر / الهوية البصرية ────────────────────────────────────
async function getGuild() {
  return request('GET', `/guilds/${guildId}?with_counts=true`);
}

function iconUrl(guild, size = 512) {
  if (!guild?.icon) return null;
  const ext = guild.icon.startsWith('a_') ? 'gif' : 'png';
  return `https://cdn.discordapp.com/icons/${guild.id}/${guild.icon}.${ext}?size=${size}`;
}

function bannerUrl(guild, size = 1024) {
  if (!guild?.banner) return null;
  const ext = guild.banner.startsWith('a_') ? 'gif' : 'png';
  return `https://cdn.discordapp.com/banners/${guild.id}/${guild.banner}.${ext}?size=${size}`;
}

function avatarUrl(user, size = 64) {
  if (!user) return null;
  if (!user.avatar) {
    const idx = user.discriminator && user.discriminator !== '0'
      ? Number(user.discriminator) % 5
      : Number((BigInt(user.id) >> 22n) % 6n);
    return `https://cdn.discordapp.com/embed/avatars/${idx}.png`;
  }
  const ext = user.avatar.startsWith('a_') ? 'gif' : 'png';
  return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=${size}`;
}

// ── قنوات / رولات / أعضاء ────────────────────────────────────────

// نصية/إعلانات فقط — تستخدم بقوائم اختيار "أرسل رسالة بقناة"
async function listChannels() {
  const channels = await request('GET', `/guilds/${guildId}/channels`);
  return channels
    .filter((c) => [0, 5].includes(c.type))
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
}

// كل القنوات والكاتجوريز — تستخدم بصفحة إدارة السيرفر
async function listAllChannelsAndCategories() {
  const channels = await request('GET', `/guilds/${guildId}/channels`);
  return channels.sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
}

async function createChannel({ name, type, parentId, topic }) {
  return request('POST', `/guilds/${guildId}/channels`, {
    name,
    type,
    parent_id: parentId || null,
    topic: topic || undefined,
  });
}

async function updateChannel(channelId, { name, topic, parentId, position }) {
  const body = {};
  if (name !== undefined) body.name = name;
  if (topic !== undefined) body.topic = topic;
  if (parentId !== undefined) body.parent_id = parentId || null;
  if (position !== undefined) body.position = position;
  return request('PATCH', `/channels/${channelId}`, body);
}

async function deleteChannel(channelId) {
  return request('DELETE', `/channels/${channelId}`);
}

async function listRoles() {
  const roles = await request('GET', `/guilds/${guildId}/roles`);
  return roles.filter((r) => r.name !== '@everyone').sort((a, b) => b.position - a.position);
}

// بتات صلاحيات ديسكورد الشائعة (كنصوص عشان أرقامها تتجاوز حدود آمنة لبعض
// العمليات — نجمعها بـ BigInt ونحولها نص بالنهاية زي ما تتوقعه REST API)
const PERMISSION_BITS = {
  CREATE_INSTANT_INVITE: 1n,
  KICK_MEMBERS: 2n,
  BAN_MEMBERS: 4n,
  ADMINISTRATOR: 8n,
  MANAGE_CHANNELS: 16n,
  MANAGE_GUILD: 32n,
  VIEW_CHANNEL: 1024n,
  SEND_MESSAGES: 2048n,
  MANAGE_MESSAGES: 8192n,
  MENTION_EVERYONE: 131072n,
  CONNECT: 1048576n,
  SPEAK: 2097152n,
  MANAGE_ROLES: 268435456n,
  MODERATE_MEMBERS: 1099511627776n,
};

function combinePermissions(names = []) {
  let bits = 0n;
  for (const name of names) {
    if (PERMISSION_BITS[name]) bits |= PERMISSION_BITS[name];
  }
  return bits.toString();
}

async function createRole({ name, color, permissions, hoist, mentionable }) {
  return request('POST', `/guilds/${guildId}/roles`, {
    name,
    color: color || 0,
    permissions: combinePermissions(permissions),
    hoist: Boolean(hoist),
    mentionable: Boolean(mentionable),
  });
}

async function updateRole(roleId, { name, color, permissions, hoist, mentionable }) {
  const body = {};
  if (name !== undefined) body.name = name;
  if (color !== undefined) body.color = color;
  if (permissions !== undefined) body.permissions = combinePermissions(permissions);
  if (hoist !== undefined) body.hoist = Boolean(hoist);
  if (mentionable !== undefined) body.mentionable = Boolean(mentionable);
  return request('PATCH', `/guilds/${guildId}/roles/${roleId}`, body);
}

async function deleteRole(roleId) {
  return request('DELETE', `/guilds/${guildId}/roles/${roleId}`);
}

async function listBans() {
  return request('GET', `/guilds/${guildId}/bans?limit=1000`);
}

async function listAllMembers({ maxPages = 50 } = {}) {
  const out = [];
  let after = '0';
  for (let i = 0; i < maxPages; i++) {
    // eslint-disable-next-line no-await-in-loop
    const page = await request('GET', `/guilds/${guildId}/members?limit=1000&after=${after}`);
    if (!page.length) break;
    out.push(...page);
    after = page[page.length - 1].user.id;
    if (page.length < 1000) break;
  }
  return out;
}

async function listMembersByRole(roleId) {
  const members = await listAllMembers();
  return members.filter((m) => m.roles.includes(roleId));
}

async function searchMembers(query) {
  const q = encodeURIComponent(query);
  return request('GET', `/guilds/${guildId}/members/search?query=${q}&limit=25`);
}

// ── رسائل خاصة / إعلانات ─────────────────────────────────────────
async function sendDM(userId, content) {
  const channel = await request('POST', '/users/@me/channels', { recipient_id: userId });
  return request('POST', `/channels/${channel.id}/messages`, { content });
}

async function sendChannelMessage(channelId, content) {
  return request('POST', `/channels/${channelId}/messages`, { content });
}

// ── Moderation ────────────────────────────────────────────────────
async function kickMember(userId, reason) {
  return requestWithReason('DELETE', `/guilds/${guildId}/members/${userId}`, undefined, reason);
}

async function banMember(userId, { reason, deleteMessageSeconds = 0 } = {}) {
  return requestWithReason('PUT', `/guilds/${guildId}/bans/${userId}`, {
    delete_message_seconds: deleteMessageSeconds,
  }, reason);
}

async function unbanMember(userId, reason) {
  return requestWithReason('DELETE', `/guilds/${guildId}/bans/${userId}`, undefined, reason);
}

// null/0 دقايق = رفع التايم أوت
async function timeoutMember(userId, minutes, reason) {
  const until = minutes ? new Date(Date.now() + minutes * 60 * 1000).toISOString() : null;
  return requestWithReason('PATCH', `/guilds/${guildId}/members/${userId}`, {
    communication_disabled_until: until,
  }, reason);
}

async function requestWithReason(method, path, body, reason) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bot ${token}`,
      'Content-Type': 'application/json',
      ...(reason ? { 'X-Audit-Log-Reason': encodeURIComponent(reason).slice(0, 500) } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (res.status === 429) {
    const data = await res.json().catch(() => ({}));
    await new Promise((r) => setTimeout(r, Math.ceil((data.retry_after || 1) * 1000)));
    return requestWithReason(method, path, body, reason);
  }
  if (res.status === 204) return null;

  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const err = new Error(data?.message || `Discord API error (${res.status})`);
    err.status = res.status;
    throw err;
  }
  return data;
}

async function fetchRecentMessages(channelId, limit) {
  return request('GET', `/channels/${channelId}/messages?limit=${Math.min(limit, 100)}`);
}

// يحذف فقط رسائل أعمارها أقل من ١٤ يوم (قيد ديسكورد على bulk-delete)
async function purgeMessages(channelId, count) {
  let remaining = Math.min(count, 500);
  let deleted = 0;
  const fourteenDaysAgo = Date.now() - 14 * 24 * 60 * 60 * 1000;

  while (remaining > 0) {
    // eslint-disable-next-line no-await-in-loop
    const batch = await fetchRecentMessages(channelId, Math.min(remaining, 100));
    if (!batch.length) break;

    const eligible = batch.filter((m) => new Date(m.timestamp).getTime() > fourteenDaysAgo);
    if (eligible.length < 2) {
      // bulk-delete يحتاج رسالتين فأكثر — نحذف وحدة لوحدة لو بقيت وحدة بس
      if (eligible.length === 1) {
        // eslint-disable-next-line no-await-in-loop
        await request('DELETE', `/channels/${channelId}/messages/${eligible[0].id}`);
        deleted += 1;
      }
      break;
    }

    // eslint-disable-next-line no-await-in-loop
    await request('POST', `/channels/${channelId}/messages/bulk-delete`, {
      messages: eligible.map((m) => m.id),
    });
    deleted += eligible.length;
    remaining -= batch.length;
    if (batch.length < 100) break;
  }
  return deleted;
}

async function lockChannel(channelId) {
  return request('PUT', `/channels/${channelId}/permissions/${guildId}`, {
    type: 0,
    deny: SEND_MESSAGES_BIT,
    allow: '0',
  });
}

async function unlockChannel(channelId) {
  return request('DELETE', `/channels/${channelId}/permissions/${guildId}`);
}

module.exports = {
  getGuild,
  iconUrl,
  bannerUrl,
  avatarUrl,
  listChannels,
  listAllChannelsAndCategories,
  createChannel,
  updateChannel,
  deleteChannel,
  listRoles,
  createRole,
  updateRole,
  deleteRole,
  PERMISSION_BITS,
  listAllMembers,
  listMembersByRole,
  searchMembers,
  listBans,
  sendDM,
  sendChannelMessage,
  kickMember,
  banMember,
  unbanMember,
  timeoutMember,
  fetchRecentMessages,
  purgeMessages,
  lockChannel,
  unlockChannel,
};
