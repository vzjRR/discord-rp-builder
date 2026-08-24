// دالة مشتركة لكل event handlers بمجلد events/ — تحل القناة من الاسم وترسل الإمبد.
// نفس فلسفة lib/permissions.js: لو القناة غير موجودة، تحذير بالكونسول وتجاهل بدل ما يكرش البوت.

const fs = require('fs');
const path = require('path');
const { EmbedBuilder } = require('discord.js');
const logsConfig = require('../config/logs');

// نسخة دائمة من كل لوق على القرص — بغض النظر عن نجاح الإرسال لديسكورد أو
// حتى وجود القناة أصلًا، عشان تبقى مصدر موثوق مستقل عن ديسكورد (تخزينه/
// حذف القنوات ما يفقدنا السجل). سطر JSON واحد لكل حدث (JSON Lines) —
// سهل البحث فيه بـ grep بدون أدوات إضافية.
const AUDIT_FILE_PATH = process.env.AUDIT_LOG_FILE_PATH || '/var/log/enclave/audit.log';

function appendAuditFile(entry) {
  try {
    fs.mkdirSync(path.dirname(AUDIT_FILE_PATH), { recursive: true });
    fs.appendFileSync(AUDIT_FILE_PATH, `${JSON.stringify(entry)}\n`);
  } catch (err) {
    console.error(`   ❌ فشل الكتابة بملف السجل الدائم (${AUDIT_FILE_PATH}): ${err.message}`);
  }
}

// LOG_CHANNEL_ID و LOG_DISABLE_TYPES اختياريان بملف .env — تخصيص لكل نشرة بدون
// لمس config/logs.js المشترك بين كل النشرات (تغييره هنا يؤثر على Enclave أيضًا).
//   LOG_CHANNEL_ID=123        → كل الأنواع المفعّلة تُرسل لقناة واحدة بهذا الـ ID
//                                بدل البحث عن قناة باسمها لكل نوع على حدة.
//   LOG_DISABLE_TYPES=bot,foo → أنواع تُعطَّل لهذه النشرة فقط، حتى لو enabled=true
//                                بـ config/logs.js.
function resolveLogChannel(guild, key) {
  const cfg = logsConfig[key];
  if (!cfg || !cfg.enabled) return null;

  const disabledTypes = (process.env.LOG_DISABLE_TYPES || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (disabledTypes.includes(key)) return null;

  const channelId = process.env.LOG_CHANNEL_ID;
  const channel = channelId
    ? guild.channels.cache.get(channelId)
    : guild.channels.cache.find((c) => c.name === cfg.channel && c.isTextBased());

  if (!channel || !channel.isTextBased()) {
    const label = channelId ? `id ${channelId}` : `"${cfg.channel}"`;
    console.warn(`   ⚠️  قناة اللوق ${label} (${key}) غير موجودة — تم تجاهل هذا اللوق.`);
    return null;
  }
  return channel;
}

async function sendLog(guild, key, { title, description, fields = [], footer, thumbnail } = {}) {
  const cfg = logsConfig[key];

  // الملف يُكتب دايمًا بغض النظر عن حالة القناة بديسكورد — هذا هو المصدر
  // الدائم اللي المفروض ما يفوّت أي حدث.
  appendAuditFile({
    ts: new Date().toISOString(),
    type: key,
    guildId: guild.id,
    guildName: guild.name,
    title: title || null,
    description: description || null,
    fields: fields.map((f) => ({ name: f.name, value: f.value })),
    footer: footer || null,
  });

  const channel = resolveLogChannel(guild, key);
  if (!channel) return;

  const embed = new EmbedBuilder().setColor(cfg.color).setTimestamp();
  if (title) embed.setTitle(title);
  if (description) embed.setDescription(description);
  if (fields.length) embed.addFields(fields);
  if (footer) embed.setFooter({ text: footer });
  if (thumbnail) embed.setThumbnail(thumbnail);

  try {
    await channel.send({ embeds: [embed] });
  } catch (err) {
    console.error(`   ❌ فشل إرسال لوق (${key}): ${err.message}`);
  }
}

module.exports = { resolveLogChannel, sendLog };
