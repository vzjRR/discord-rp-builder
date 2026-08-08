// بوت ترحيب مستمر (يبقى شغّال 24/7 بعكس build.js اللي يشتغل مرة ويطلع)
// شغّله بـ: node welcome-bot.js   (أو npm run welcome)
//
// يحتاج: تفعيل "Server Members Intent" من Discord Developer Portal → Bot
// (بدونها، حدث انضمام عضو جديد ما يوصل للبوت أبدًا)

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const {
  Client,
  GatewayIntentBits,
  EmbedBuilder,
  AttachmentBuilder,
} = require('discord.js');
const cfg = require('./config/welcome');

const token = process.env.DISCORD_TOKEN;
const guildId = process.env.GUILD_ID;

if (!token || !guildId) {
  console.error('❌ الملف .env ناقص: تأكد من DISCORD_TOKEN و GUILD_ID');
  process.exit(1);
}

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers],
});

function fillTemplate(str, vars) {
  return str.replace(/\{(\w+)\}/g, (_, key) => (vars[key] !== undefined ? vars[key] : `{${key}}`));
}

client.once('ready', () => {
  console.log(`✅ بوت الترحيب متصل كـ ${client.user.tag}`);
  console.log('👂 بانتظار انضمام أعضاء جدد... (اترك هذا الترمنال مفتوح)');
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

    const vars = {
      member: `<@${member.id}>`,
      memberTag: member.user.username,
      memberCount: guild.memberCount,
      serverName: guild.name,
      rulesChannel: rulesChannel ? `<#${rulesChannel.id}>` : '#rules',
    };

    const embed = new EmbedBuilder()
      .setColor(cfg.color)
      .setTitle(fillTemplate(cfg.title, vars))
      .setDescription(fillTemplate(cfg.description, vars))
      .setFooter({ text: fillTemplate(cfg.footer, vars) })
      .setTimestamp();

    if (cfg.thumbnail === 'avatar') {
      embed.setThumbnail(member.user.displayAvatarURL({ size: 256 }));
    } else if (cfg.thumbnail) {
      embed.setThumbnail(cfg.thumbnail);
    }

    const files = [];
    if (cfg.bannerImagePath) {
      const fullPath = path.resolve(__dirname, cfg.bannerImagePath);
      if (fs.existsSync(fullPath)) {
        const filename = path.basename(fullPath);
        files.push(new AttachmentBuilder(fullPath, { name: filename }));
        embed.setImage(`attachment://${filename}`);
      } else {
        console.warn(`⚠️  ملف البانر غير موجود: ${fullPath} — تم تجاهله`);
      }
    }

    await channel.send({ content: `${vars.member}`, embeds: [embed], files });
    console.log(`✅ رحّبنا بـ ${member.user.tag} (العضو #${guild.memberCount})`);

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

