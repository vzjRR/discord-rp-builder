// قيد من Discord نفسه، مو بالكود: حدث MESSAGE_DELETE ما يرجّع author/content إطلاقًا —
// المصدر الوحيد لهما هو كاش البوت (لازم يكون شاف الرسالة وهي حية عبر messageCreate قبل حذفها).
// رسائل موجودة من قبل ما يشتغل البوت (أو طلعت من الكاش) تطلع "غير معروف" — هذا متوقع ومو خطأ.
// messageUpdate عكسها: النص الجديد يوصل دايمًا بالحدث، بس النص القديم يعتمد على نفس شرط الكاش.
//
// مين حذف الرسالة قيد مماثل: ديسكورد ما يرسله مع حدث الحذف، فقط بسجل التدقيق
// (Audit Log) كحدث منفصل — وأحيانًا يتأخر جزء من ثانية عن حدث الحذف نفسه.
// لذلك ننتظر قليلًا (waitForDeleteExecutor) نشوف يجي سجل تدقيق مطابق قبل إرسال
// اللوق. حذف العضو لرسالته هو بنفسه لا يُسجَّل بسجل التدقيق إطلاقًا (قيد من
// ديسكورد أيضًا) — فيطلع "غير معروف" في تلك الحالة، وهذا متوقع لا خطأ.

const { AuditLogEvent } = require('discord.js');
const { sendLog } = require('../lib/logs');
const logsConfig = require('../config/logs');

const DELETE_EXECUTOR_WAIT_MS = 3000;

function truncate(str, max = 200) {
  if (!str) return '*(empty message)*';
  return str.length > max ? `${str.slice(0, max)}…` : str;
}

function formatAttachments(message) {
  if (!message.attachments || message.attachments.size === 0) return null;
  return [...message.attachments.values()].map((a) => a.url).join('\n');
}

// وقت إنشاء سجل تدقيق تقريبًا، من الـ snowflake ID نفسه (أول ٤٢ بت منه فرق
// مللي ثانية عن Discord Epoch) — بلا حاجة لطلب إضافي.
function auditEntryTimestamp(entry) {
  return Number(BigInt(entry.id) >> 22n) + 1420070400000;
}

function auditEntryMatches(entry, message) {
  if (entry.action !== AuditLogEvent.MessageDelete) return false;
  if (entry.targetId !== message.author.id) return false;
  const channelId = entry.extra?.channel?.id;
  if (channelId && channelId !== message.channel.id) return false;
  return Date.now() - auditEntryTimestamp(entry) < DELETE_EXECUTOR_WAIT_MS + 2000;
}

async function resolveExecutorTag(client, entry) {
  if (entry.executor) return entry.executor.tag;
  if (!entry.executorId) return null;
  try {
    const user = await client.users.fetch(entry.executorId);
    return user.tag;
  } catch {
    return null;
  }
}

/** ينتظر سجل تدقيق حذف رسالة يطابق هذه الرسالة، أو يرجع null بعد مهلة قصيرة. */
function waitForDeleteExecutor(client, message) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (value) => {
      if (done) return;
      done = true;
      client.off('guildAuditLogEntryCreate', onEntry);
      clearTimeout(timer);
      resolve(value);
    };
    const onEntry = async (entry, guild) => {
      if (guild.id !== message.guild.id) return;
      if (!auditEntryMatches(entry, message)) return;
      const tag = await resolveExecutorTag(client, entry);
      if (tag) finish(tag);
    };
    client.on('guildAuditLogEntryCreate', onEntry);
    const timer = setTimeout(() => finish(null), DELETE_EXECUTOR_WAIT_MS);
  });
}

function register(client) {
  client.on('messageDelete', async (message) => {
    if (!message.guild || message.guild.id !== process.env.GUILD_ID) return;
    if (message.author?.bot && logsConfig.ignoreBots) return;

    const wasCached = !message.partial;
    const attachmentsText = wasCached ? formatAttachments(message) : null;

    // ما فيه فايدة ننتظر لو ما نملك مؤلّف نطابقه بسجل التدقيق أصلًا (رسالة
    // غير مكاشة)، أو كان المؤلّف بوت (بوتات ما تظهر بسجل تدقيق الحذف بنفس الشكل).
    const executorTag = wasCached && message.author && !message.author.bot
      ? await waitForDeleteExecutor(client, message)
      : null;

    const fields = [];
    if (logsConfig.showMessageContent) {
      fields.push({
        name: 'Content',
        value: wasCached ? truncate(message.content) : '*(unrecoverable — Discord doesn\'t send deleted message content)*',
        inline: false,
      });
    }
    if (attachmentsText) fields.push({ name: 'Attachments', value: truncate(attachmentsText, 1000), inline: false });
    fields.push({
      name: 'Deleted By',
      value: executorTag || (wasCached ? 'الكاتب نفسه على الأغلب — ديسكورد لا يسجّل حذف العضو لرسالته بسجل التدقيق' : 'غير معروف'),
      inline: false,
    });

    await sendLog(message.guild, 'moderation', {
      title: '🗑️ Message Deleted',
      description: `in ${message.channel} — message from ${wasCached ? message.author.tag : 'Unknown — message wasn\'t cached before deletion'}`,
      fields,
      footer: `Message ID: ${message.id}`,
    });
  });

  client.on('messageUpdate', async (oldMessage, newMessage) => {
    if (!newMessage.guild || newMessage.guild.id !== process.env.GUILD_ID) return;
    if (newMessage.author?.bot && logsConfig.ignoreBots) return;
    if (!oldMessage.partial && oldMessage.content === newMessage.content) return; // تجاهل تحديثات embed/pin فقط

    await sendLog(newMessage.guild, 'moderation', {
      title: '✏️ Message Edited',
      description: `in ${newMessage.channel} by ${newMessage.author ? newMessage.author.tag : 'Unknown'} · [Jump to message](${newMessage.url})`,
      fields: logsConfig.showMessageContent
        ? [
            { name: 'Before', value: oldMessage.partial ? '*(unknown — not cached before this edit)*' : truncate(oldMessage.content), inline: false },
            { name: 'After', value: truncate(newMessage.content), inline: false },
          ]
        : [],
      footer: `Message ID: ${newMessage.id}`,
    });
  });
}

module.exports = { register };
