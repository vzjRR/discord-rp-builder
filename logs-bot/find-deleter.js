// يبحث عن مين حذف رسالة معيّنة، بمطابقة سجل قناة moderation-log (فيه القناة
// والتوقيت التقريبي) مع سجل التدقيق (Audit Log) الخاص بديسكورد (فيه المنفّذ).
//
// قيد من Discord نفسه: سجل التدقيق ما يسجّل حذف عضو لرسالته هو نفسه — فقط
// حذف مشرف لرسالة عضو آخر. لو محد وجدناه يعني الأرجح إن صاحب الرسالة حذفها
// بنفسه (ولا أثر لذلك بسجل التدقيق أصلًا)، أو إن الحذف تجاوز مدة احتفاظ
// السجل (حاليًا آخر ٤٥ يوم تقريبًا حسب ديسكورد).
//
// الاستخدام: node find-deleter.js <messageId>

require('dotenv').config();

const API = 'https://discord.com/api/v10';
const messageId = process.argv[2];

if (!messageId || !/^\d{5,}$/.test(messageId)) {
  console.error('الاستخدام: node find-deleter.js <messageId>');
  process.exit(1);
}

const token = process.env.DISCORD_TOKEN;
const guildId = process.env.GUILD_ID;
if (!token || !guildId) {
  console.error('❌ الملف .env ناقص: تأكد من DISCORD_TOKEN و GUILD_ID');
  process.exit(1);
}

async function api(route) {
  const res = await fetch(`${API}${route}`, { headers: { Authorization: `Bot ${token}` } });
  if (!res.ok) throw new Error(`${route} → ${res.status} ${res.statusText}: ${await res.text()}`);
  return res.json();
}

const MODERATION_LOG_CHANNEL_NAME = '🛡️・moderation-log';
const MESSAGE_DELETE_ACTION_TYPE = 72;

(async () => {
  const channels = await api(`/guilds/${guildId}/channels`);
  const modLogChannel = channels.find((c) => c.name === MODERATION_LOG_CHANNEL_NAME);
  if (!modLogChannel) throw new Error(`ما لقيت قناة "${MODERATION_LOG_CHANNEL_NAME}"`);

  console.log(`📋 نبحث عن سجل الحذف للرسالة ${messageId} بقناة #${modLogChannel.name} ...`);

  // نمشي رجوعًا بسجل القناة (١٠٠ كحد أقصى بكل طلب) لحد ما نلقى سجل يحتوي هذا الـ ID بالفوتر
  let before = null;
  let logEntry = null;
  for (let page = 0; page < 20 && !logEntry; page++) {
    const q = before ? `?limit=100&before=${before}` : '?limit=100';
    const batch = await api(`/channels/${modLogChannel.id}/messages${q}`);
    if (!batch.length) break;
    for (const msg of batch) {
      const footer = msg.embeds?.[0]?.footer?.text || '';
      if (footer.includes(messageId)) {
        logEntry = msg;
        break;
      }
    }
    before = batch[batch.length - 1].id;
  }

  if (!logEntry) {
    console.log('❌ ما لقيت سجل حذف لهذا الـ ID بقناة moderation-log (بحثت آخر ٢٠٠٠ رسالة). تأكد من الـ ID.');
    return;
  }

  const embed = logEntry.embeds[0];
  const deletedAt = new Date(logEntry.timestamp).getTime();
  const channelMention = embed.description?.match(/<#(\d+)>/);
  const targetChannelId = channelMention ? channelMention[1] : null;

  console.log(`✅ لقيت السجل: "${embed.description}"`);
  console.log(`   وقت السجل: ${new Date(deletedAt).toISOString()}`);
  console.log(`   القناة المستهدفة: ${targetChannelId ? `<#${targetChannelId}>` : 'غير معروفة من النص'}`);

  console.log('\n📋 نفحص سجل التدقيق (Audit Log) عن عمليات حذف رسائل قريبة من هذا الوقت ...');
  const auditLog = await api(`/guilds/${guildId}/audit-logs?action_type=${MESSAGE_DELETE_ACTION_TYPE}&limit=50`);
  const users = new Map((auditLog.users || []).map((u) => [u.id, u]));

  const FIVE_MIN_MS = 5 * 60 * 1000;
  const candidates = auditLog.audit_log_entries.filter((entry) => {
    // الـ id بسجل التدقيق snowflake — أول ٤٢ بت منه فرق مللي ثانية عن Discord Epoch
    const entryTime = Number(BigInt(entry.id) >> 22n) + 1420070400000;
    const withinWindow = Math.abs(entryTime - deletedAt) < FIVE_MIN_MS;
    const sameChannel = !targetChannelId || entry.options?.channel_id === targetChannelId;
    return withinWindow && sameChannel;
  });

  if (!candidates.length) {
    console.log('\n❌ ما لقيت أي سجل تدقيق مطابق خلال ±٥ دقايق من وقت السجل.');
    console.log('   الأرجح: صاحب الرسالة حذفها بنفسه (Discord ما يسجّل هذا بسجل التدقيق أصلًا)،');
    console.log('   أو إن سجل التدقيق الخاص بهذا الحذف تجاوز مدة الاحتفاظ.');
    return;
  }

  console.log(`\n✅ ${candidates.length} سجل تدقيق مرشّح:`);
  for (const entry of candidates) {
    const executor = users.get(entry.user_id);
    const targetUser = users.get(entry.target_id);
    const entryTime = Number(BigInt(entry.id) >> 22n) + 1420070400000;
    console.log(
      `   ${new Date(entryTime).toISOString()} — ${executor ? executor.username : entry.user_id} ` +
        `حذف ${entry.options?.count || 1} رسالة من ${targetUser ? targetUser.username : entry.target_id} ` +
        `بقناة <#${entry.options?.channel_id}>`
    );
  }
})().catch((err) => {
  console.error('❌ فشل:', err.message);
  process.exit(1);
});
