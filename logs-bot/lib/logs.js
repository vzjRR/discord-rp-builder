// دالة مشتركة لكل event handlers بمجلد events/ — تحل القناة من الاسم وترسل الإمبد.
// نفس فلسفة lib/permissions.js: لو القناة غير موجودة، تحذير بالكونسول وتجاهل بدل ما يكرش البوت.

const { EmbedBuilder } = require('discord.js');
const logsConfig = require('../config/logs');

function resolveLogChannel(guild, key) {
  const cfg = logsConfig[key];
  if (!cfg || !cfg.enabled) return null;

  const channel = guild.channels.cache.find((c) => c.name === cfg.channel && c.isTextBased());
  if (!channel) {
    console.warn(`   ⚠️  قناة اللوق "${cfg.channel}" (${key}) غير موجودة — تم تجاهل هذا اللوق.`);
    return null;
  }
  return channel;
}

async function sendLog(guild, key, { title, description, fields = [], footer, thumbnail } = {}) {
  const cfg = logsConfig[key];
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
