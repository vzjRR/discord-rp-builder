// مشروع مستقل بذاته (شوف package.json بنفس المجلد) — يُشغَّل وينشر منفصل عن
// welcome-bot/logs-bot وعن أدوات build.js بجذر المستودع. عملية Node خاصة به.
// التشغيل: npm install ثم npm start (أو node bot.js)
//
// لا يوجد ولا أمر واحد لهذا البوت عمدًا (لا slash ولا بادئة نص) — كل شيء
// تلقائي بحت. القراءة والإدارة تتم فقط من admin-panel (صلاحية points.view/points.manage).
//
// يحتاج تفعيل "Message Content Intent" من Discord Developer Portal → Bot
// (بدونها attachments/embeds ما توصل مع أحداث الرسائل من أعضاء غير-بوت).

require('dotenv').config();
const { Client, GatewayIntentBits, Partials } = require('discord.js');
const { migrate } = require('./lib/db');
const { countImages } = require('./lib/imageDetector');
const { recordNewMessage, recordMessageEdit, recordMessageDelete, cfg } = require('./lib/points');
const { startRolloverScheduler } = require('./lib/rollover');

const token = process.env.DISCORD_TOKEN;
const channelId = process.env.IMAGE_POINTS_CHANNEL_ID;

if (!token || !channelId) {
  console.error('❌ الملف .env ناقص: تأكد من DISCORD_TOKEN و IMAGE_POINTS_CHANNEL_ID');
  process.exit(1);
}

migrate();

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    // مطلوبة عشان نقرأ attachments/embeds برسائل أعضاء غير-بوت (صلاحية مميّزة،
    // فعّلها من Developer Portal → Bot → Privileged Gateway Intents).
    GatewayIntentBits.MessageContent,
  ],
  // نحتاج الرسالة القديمة كاملة عند تعديل/حذف رسالة قديمة لم تُخزَّن بالـ cache
  // (البوت أعاد التشغيل، أو الرسالة قديمة وطُردت من الـ cache) — partial بدل تجاهلها.
  partials: [Partials.Message, Partials.Channel],
});

function buildContext(message, imageCount) {
  return {
    messageId: message.id,
    userId: message.author.id,
    channelId: message.channelId,
    imageCount,
    username: message.author.username,
    displayName: message.member?.displayName || message.author.globalName || message.author.username,
    messageCreatedAt: message.createdTimestamp,
  };
}

async function resolveFullMessage(message) {
  if (!message.partial) return message;
  try {
    return await message.fetch();
  } catch {
    // الرسالة انحذفت أصلًا أو ما عاد نقدر نجيبها — messageDelete يتكفّل بالحالة هذي بنفسه
    return null;
  }
}

client.on('messageCreate', async (message) => {
  if (message.channelId !== channelId) return;
  if (message.author.bot) return;

  const { count } = countImages(message);
  const result = recordNewMessage(buildContext(message, count), 'live');
  if (result.outcome === 'counted') {
    console.log(`🖼️  +${result.pointsDelta} نقطة لـ ${message.author.tag} (رسالة ${message.id})`);
  }
});

client.on('messageUpdate', async (_oldMessage, newMessage) => {
  if (newMessage.channelId !== channelId) return;

  const full = await resolveFullMessage(newMessage);
  if (!full || full.author?.bot) return;

  const { count } = countImages(full);
  const result = recordMessageEdit(buildContext(full, count));
  if (result.pointsDelta !== 0) {
    console.log(`✏️  ${result.pointsDelta > 0 ? '+' : ''}${result.pointsDelta} نقطة (تعديل رسالة ${full.id})`);
  }
});

client.on('messageDelete', (message) => {
  if (message.channelId !== channelId) return;
  const result = recordMessageDelete(message.id, message.channelId);
  if (result.pointsDelta !== 0) {
    console.log(`🗑️  ${result.pointsDelta} نقطة (حذف رسالة ${message.id})`);
  }
});

client.once('ready', () => {
  console.log(`✅ بوت النقاط متصل كـ ${client.user.tag}`);
  console.log(`📌 يراقب القناة ${channelId} فقط — لا أوامر، كل شيء تلقائي`);

  const { timezone, weekStartDay } = cfg();
  startRolloverScheduler(timezone, weekStartDay);
});

client.login(token);

// ─────────────────────────────────────────────────────────────
// خادم HTTP صغير اختياري — مطلوب فقط لو نشرت البوت على منصة PaaS
// (زي Koyeb, Render, Railway) لأنها تحتاج البرنامج يفتح منفذ عشان تتأكد إنه شغّال.
// على VPS عادي (systemd/pm2)، هذا الجزء ما يشتغل أصلًا لأن PORT غير معرّف — آمن 100%.
// ─────────────────────────────────────────────────────────────
if (process.env.PORT) {
  const http = require('http');
  http
    .createServer((_, res) => res.end('points-bot is alive'))
    .listen(process.env.PORT, () => {
      console.log(`🌐 Health-check server listening on port ${process.env.PORT}`);
    });
}
