// مصدر واحد لمتغيّرات القوالب ({member} و {welcomeChannel} ...) يستخدمه
// البوت الحقيقي (lib/welcome.js) والمحاكاة (dry-run-join.js) — عشان اللي تشوفه
// بالـ dry-run يكون هو نفسه اللي ينرسل فعلًا، بدون ما تختلف النسختين مع الوقت.

// روابط القنوات: منشن <#id> يطلع باسم القناة ويكون قابل للضغط داخل السيرفر،
// لكن برسائل الخاص أحيانًا ما ينفتح. الرابط الكامل discord.com/channels/...
// يشتغل دايمًا وينقل العضو للقناة مباشرة — فنوفّر الاثنين ونستخدم الرابط بالـ DM.
function channelUrl(guildId, channelId) {
  return `https://discord.com/channels/${guildId}/${channelId}`;
}

/**
 * @param {object} o
 * @param {string} o.guildId
 * @param {string} o.serverName
 * @param {string} o.memberId
 * @param {string} o.memberTag       اليوزرنيم بدون منشن
 * @param {string} o.displayName
 * @param {number} o.memberCount
 * @param {string|null} [o.welcomeChannelId]
 * @param {string|null} [o.rulesChannelId]
 * @param {string|null} [o.ticketChannelId]
 * @param {string} [o.inviter]       نص جاهز لمنشن الداعي
 */
function buildTemplateVars(o) {
  const link = (id, fallback) => (id ? channelUrl(o.guildId, id) : fallback);
  const mention = (id, fallback) => (id ? `<#${id}>` : fallback);

  return {
    member: `<@${o.memberId}>`,
    memberTag: o.memberTag,
    displayName: o.displayName,
    memberCount: o.memberCount,
    serverName: o.serverName,

    welcomeChannel: mention(o.welcomeChannelId, '#enclave-airport'),
    welcomeChannelUrl: link(o.welcomeChannelId, ''),
    rulesChannel: mention(o.rulesChannelId, '#rules'),
    rulesChannelUrl: link(o.rulesChannelId, ''),
    ticketChannel: mention(o.ticketChannelId, '#create-ticket'),
    ticketChannelUrl: link(o.ticketChannelId, ''),

    inviter: o.inviter ?? 'غير معروف',
  };
}

function fillTemplate(str, vars) {
  return String(str).replace(/\{(\w+)\}/g, (_, key) =>
    vars[key] !== undefined ? vars[key] : `{${key}}`
  );
}

module.exports = { buildTemplateVars, fillTemplate, channelUrl };
