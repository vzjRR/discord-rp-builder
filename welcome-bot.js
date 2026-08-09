// بوت ترحيب مستمر (يبقى شغّال 24/7 بعكس build.js اللي يشتغل مرة ويطلع)
// شغّله بـ: node welcome-bot.js   (أو npm run welcome)
//
// يحتاج: تفعيل "Server Members Intent" من Discord Developer Portal → Bot
// (بدونها، حدث انضمام عضو جديد ما يوصل للبوت أبدًا)
//
// لو cfg.trackInvites = true، يحتاج كمان صلاحية "Manage Server" (Manage Guild)
// للبوت بالسيرفر عشان يقدر يقرأ قائمة الدعوات ويحدد مين دعا العضو الجديد.

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const {
  Client,
  GatewayIntentBits,
  AttachmentBuilder,
} = require('discord.js');
const cfg = require('./config/welcome');
const { composeWelcomeImage } = require('./lib/composeWelcomeImage');

const token = process.env.DISCORD_TOKEN;
const guildId = process.env.GUILD_ID;

if (!token || !guildId) {
  console.error('❌ الملف .env ناقص: تأكد من DISCORD_TOKEN و GUILD_ID');
  process.exit(1);
}

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildInvites,
  ],
});

function fillTemplate(str, vars) {
  return str.replace(/\{(\w+)\}/g, (_, key) => (vars[key] !== undefined ? vars[key] : `{${key}}`));
}

// ─────────────────────────────────────────────────────────────
// تتبع الدعوات — نحتفظ بعدد استخدامات كل رابط دعوة، ولما يدخل عضو جديد
// نقارن العدد القديم بالجديد لنعرف أي رابط استُخدم ومين صاحبه.
// أفضل جهد ممكن: روابط الدعوة أحادية الاستخدام تنحذف تلقائيًا بعد الاستخدام
// فما نقدر نحدد صاحبها بهذي الحالة (قيود Discord API نفسها).
// ─────────────────────────────────────────────────────────────
let inviteCache = new Map(); // code -> uses

async function refreshInviteCache(guild) {
  try {
    const invites = await guild.invites.fetch();
    inviteCache = new Map(invites.map((inv) => [inv.code, inv.uses]));
  } catch (err) {
    console.warn('⚠️  ما قدرنا نجيب قائمة الدعوات (تأكد إن البوت عنده صلاحية Manage Server):', err.message);
  }
}

async function findInviter(guild) {
  if (!cfg.trackInvites) return null;
  try {
    const before = inviteCache;
    const afterInvites = await guild.invites.fetch();

    let used = null;
    for (const invite of afterInvites.values()) {
      const prevUses = before.get(invite.code) ?? 0;
      if (invite.uses > prevUses) {
        used = invite;
        break;
      }
    }

    inviteCache = new Map(afterInvites.map((inv) => [inv.code, inv.uses]));
    return used ? used.inviter : null;
  } catch (err) {
    console.warn('⚠️  ما قدرنا نحدد مين دعا العضو الجديد:', err.message);
    return null;
  }
}

client.once('ready', async () => {
  console.log(`✅ بوت الترحيب متصل كـ ${client.user.tag}`);
  const guild = client.guilds.cache.get(guildId);
  if (cfg.trackInvites && guild) {
    await refreshInviteCache(guild);
    console.log(`📋 تم تحميل ${inviteCache.size} دعوة لتتبعها`);
  }
  console.log('👂 بانتظار انضمام أعضاء جدد... (اترك هذا الترمنال مفتوح)');
});

client.on('inviteCreate', (invite) => {
  if (invite.guild?.id === guildId) inviteCache.set(invite.code, invite.uses);
});

client.on('inviteDelete', (invite) => {
  if (invite.guild?.id === guildId) inviteCache.delete(invite.code);
});

client.on('guildMemberAdd', async (member) => {
  try {
    if (member.guild.id !== guildId) return; // تجاهل لو البوت بأكثر من سيرفر

    const guild = member.guild;
    const channel = guild.channels.cache.find((c) => c.name === cfg.channelName && c.isTextBased());
    if (!channel) {
      console.warn(`⚠️  ما لقيت قناة الترحيب "${cfg.channelName}" — تأكد من الاسم بـ config/welcome.js`);
      return;
    }

    const rulesChannel = guild.channels.cache.find((c) => c.name === cfg.rulesChannelName);
    const inviter = await findInviter(guild);

    const vars = {
      member: `<@${member.id}>`,
      memberTag: member.user.username,
      memberCount: guild.memberCount,
      serverName: guild.name,
      rulesChannel: rulesChannel ? `<#${rulesChannel.id}>` : '#rules',
      inviter: inviter ? `<@${inviter.id}>` : 'غير معروف',
    };

    const files = [];
    let imageRef = null;

    if (cfg.generateWelcomeImage) {
      try {
        const avatarUrl = member.user.displayAvatarURL({ extension: 'png', size: 512 });
        const imageBuffer = await composeWelcomeImage(avatarUrl);
        const filename = cfg.generatedImageFilename || 'welcome.png';
        files.push(new AttachmentBuilder(imageBuffer, { name: filename }));
        imageRef = `attachment://${filename}`;
      } catch (err) {
        console.warn('⚠️  فشل توليد صورة الترحيب، بنرسل النص فقط:', err.message);
      }
    } else if (cfg.bannerImagePath) {
      const fullPath = path.resolve(__dirname, cfg.bannerImagePath);
      if (fs.existsSync(fullPath)) {
        const filename = path.basename(fullPath);
        files.push(new AttachmentBuilder(fullPath, { name: filename }));
        imageRef = `attachment://${filename}`;
      } else {
        console.warn(`⚠️  ملف البانر غير موجود: ${fullPath} — تم تجاهله`);
      }
    }

    const content = fillTemplate(cfg.contentTemplate, vars);
    await channel.send({ content, files });
    console.log(`✅ رحّبنا بـ ${member.user.tag} (العضو #${guild.memberCount})${inviter ? ` — دعاه ${inviter.tag}` : ''}`);

    if (cfg.autoAssignRole) {
      const role = guild.roles.cache.find((r) => r.name === cfg.autoAssignRole);
      if (role) {
        await member.roles.add(role).catch((err) => console.warn(`⚠️  فشل إعطاء الرول: ${err.message}`));
      } else {
        console.warn(`⚠️  الرول "${cfg.autoAssignRole}" غير موجود — شغّل node build.js roles أولًا`);
      }
    }

    if (cfg.sendDM) {
      const dmText = fillTemplate(cfg.dmMessage, vars);
      await member.send(dmText).catch(() => {
        console.log(`   ℹ️  ما قدرنا نرسل DM لـ ${member.user.tag} (خصوصياته مقفلة على الأرجح)`);
      });
    }
  } catch (err) {
    console.error('❌ خطأ أثناء الترحيب:', err);
  }
});

client.login(token);

// ─────────────────────────────────────────────────────────────
// خادم HTTP صغير اختياري — مطلوب فقط لو نشرت البوت على منصة PaaS
// (زي Koyeb, Render, Railway) لأنها تحتاج البرنامج يفتح منفذ عشان تتأكد إنه شغّال.
// على جهازك الشخصي أو VPS عادي (pm2)، هذا الجزء ما يشتغل أصلًا لأن PORT غير معرّف — آمن 100%.
// ─────────────────────────────────────────────────────────────
if (process.env.PORT) {
  const http = require('http');
  http
    .createServer((_, res) => res.end('welcome-bot is alive'))
    .listen(process.env.PORT, () => {
      console.log(`🌐 Health-check server listening on port ${process.env.PORT}`);
    });
}