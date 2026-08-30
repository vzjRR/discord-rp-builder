// محاكاة "دخول عضو جديد" بالكامل — بدون ما يرسل أي شيء لديسكورد.
// يمشي نفس مسار lib/welcome.js (guildMemberAdd) خطوة بخطوة:
//   1. يجيب بيانات العضو + عدد أعضاء السيرفر
//   2. يتأكد إن قناة الترحيب وقناة القوانين والرول موجودين فعلًا
//   3. يركّب صورة الترحيب ويحفظها محليًا
//   4. يطبع نص الرسالة ورسالة الـ DM كما بتنرسل بالضبط
//
// كل نداءات الـ API هنا GET فقط (قراءة) — ما فيه أي إرسال أو تعديل.
//
// الاستخدام: node dry-run-join.js [userId]

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const cfg = require('./config/welcome');
const { composeWelcomeImage } = require('./lib/composeWelcomeImage');
const { buildTemplateVars, fillTemplate } = require('./lib/templateVars');

const DEFAULT_USER_ID = '1119011672351330377';
const API = 'https://discord.com/api/v10';

const userId = process.argv[2] || DEFAULT_USER_ID;
const outPath = path.join(__dirname, 'dry-run-output.png');
const token = process.env.DISCORD_TOKEN;
const guildId = process.env.GUILD_ID;

if (!token || !guildId) {
  console.error('❌ الملف .env ناقص: تأكد من DISCORD_TOKEN و GUILD_ID');
  process.exit(1);
}

async function api(route) {
  const res = await fetch(`${API}${route}`, { headers: { Authorization: `Bot ${token}` } });
  if (!res.ok) throw new Error(`${route} → ${res.status} ${res.statusText}`);
  return res.json();
}

// نستورد نفس دوال البوت الحقيقي بدل ما ننسخها — عشان المحاكاة تطابق الواقع دايمًا

function avatarUrl(user) {
  if (user.avatar) {
    return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png?size=512`;
  }
  const index =
    user.discriminator && user.discriminator !== '0'
      ? Number(user.discriminator) % 5
      : Number((BigInt(user.id) >> 22n) % 6n);
  return `https://cdn.discordapp.com/embed/avatars/${index}.png`;
}

const line = (t = '') => console.log(t);
const rule = () => line('─'.repeat(64));

(async () => {
  line('🧪 محاكاة دخول عضو جديد (DRY RUN — ما ينرسل ولا شيء لديسكورد)');
  rule();

  // ── 1. بيانات العضو والسيرفر ────────────────────────────────
  const user = await api(`/users/${userId}`);
  const guild = await api(`/guilds/${guildId}?with_counts=true`);
  const memberCount = guild.approximate_member_count ?? 0;

  let nickname = null;
  try {
    const member = await api(`/guilds/${guildId}/members/${userId}`);
    nickname = member.nick || null;
  } catch {
    line('ℹ️  العضو مو موجود بالسيرفر حاليًا — بنستخدم اسمه العام');
  }

  const displayName = nickname || user.global_name || user.username;

  line(`السيرفر        : ${guild.name}`);
  line(`العضو          : ${displayName}`);
  line(`اليوزرنيم      : @${user.username}`);
  line(`عدد الأعضاء    : ${memberCount}`);
  rule();

  // ── 2. فحص القناة والرول قبل ما نعتمد ───────────────────────
  line('🔍 فحص المتطلبات بالسيرفر:');
  const channels = await api(`/guilds/${guildId}/channels`);
  const roles = await api(`/guilds/${guildId}/roles`);

  const welcomeChannel = process.env.WELCOME_CHANNEL_ID
    ? channels.find((c) => c.id === process.env.WELCOME_CHANNEL_ID)
    : channels.find((c) => c.name === cfg.channelName);
  const rulesChannel = channels.find((c) => c.name === cfg.rulesChannelName);
  const ticketChannel = cfg.ticketChannelName
    ? channels.find((c) => c.name === cfg.ticketChannelName)
    : null;
  const autoRole = cfg.autoAssignRole ? roles.find((r) => r.name === cfg.autoAssignRole) : null;

  const welcomeChannelLabel = process.env.WELCOME_CHANNEL_ID
    ? `id ${process.env.WELCOME_CHANNEL_ID}`
    : `"${cfg.channelName}"`;
  line(`   ${welcomeChannel ? '✅' : '❌'} قناة الترحيب  ${welcomeChannelLabel}`);
  line(`   ${rulesChannel ? '✅' : '⚠️ '} قناة القوانين "${cfg.rulesChannelName}"`);
  if (cfg.ticketChannelName) {
    line(`   ${ticketChannel ? '✅' : '⚠️ '} قناة التذاكر  "${cfg.ticketChannelName}"`);
  }
  if (cfg.autoAssignRole) line(`   ${autoRole ? '✅' : '❌'} الرول التلقائي "${cfg.autoAssignRole}"`);
  rule();

  // ── 3. تركيب الصورة (نفس ما يسويها البوت) ───────────────────
  const imageBuffer = await composeWelcomeImage(avatarUrl(user), {
    displayName,
    username: user.username,
    memberCount,
  });
  fs.writeFileSync(outPath, imageBuffer);
  line(`🖼️  الصورة المرفقة → ${outPath}`);
  line(`    (تنرسل باسم "${cfg.generatedImageFilename || 'welcome.png'}")`);
  rule();

  // ── 4. النصوص كما بتنرسل بالضبط ─────────────────────────────
  const vars = buildTemplateVars({
    guildId,
    serverName: guild.name,
    memberId: user.id,
    memberTag: user.username,
    displayName,
    memberCount,
    welcomeChannelId: welcomeChannel?.id ?? null,
    rulesChannelId: rulesChannel?.id ?? null,
    ticketChannelId: ticketChannel?.id ?? null,
    inviter: '<@…>  (يتحدد وقت الدخول الحقيقي حسب رابط الدعوة)',
  });

  line(`💬 الرسالة اللي بتنرسل بقناة ${welcomeChannelLabel}:`);
  line();
  line(fillTemplate(cfg.contentTemplate, vars));
  line();

  if (cfg.sendDM) {
    line('📨 رسالة الخاص (DM) للعضو:');
    line();
    line(fillTemplate(cfg.dmMessage, vars));
    line();
  }

  if (cfg.autoAssignRole) {
    line(`🎭 الرول اللي بينعطى تلقائيًا: ${cfg.autoAssignRole}`);
  }

  rule();
  line('✅ انتهت المحاكاة — ما تم إرسال أي رسالة أو إعطاء أي رول.');
})().catch((err) => {
  console.error('❌ فشلت المحاكاة:', err.message);
  process.exit(1);
});
