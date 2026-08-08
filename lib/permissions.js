const { PermissionFlagsBits } = require('discord.js');

function resolveRole(guild, name) {
  return guild.roles.cache.find((r) => r.name === name);
}

/**
 * يبني مصفوفة permissionOverwrites لقناة نصية أو صوتية بناءً على { view, write }
 * view  = من يستطيع رؤية القناة (أسماء رولات، أو '@everyone')
 * write = من يستطيع الكتابة/الاتصال (يجب أن يكون ضمن view أيضًا)
 */
function buildOverwrites(guild, { view = [], write = [] }, channelType = 'text') {
  const overwrites = [];
  const isPublic = view.includes('@everyone');
  const everyoneCanWrite = write.includes('@everyone');

  const sendPerms =
    channelType === 'voice'
      ? [PermissionFlagsBits.Connect, PermissionFlagsBits.Speak]
      : [
          PermissionFlagsBits.SendMessages,
          PermissionFlagsBits.AddReactions,
          PermissionFlagsBits.CreatePublicThreads,
          PermissionFlagsBits.CreatePrivateThreads,
        ];

  const everyoneAllow = [];
  const everyoneDeny = [];
  if (isPublic) everyoneAllow.push(PermissionFlagsBits.ViewChannel);
  else everyoneDeny.push(PermissionFlagsBits.ViewChannel);
  if (everyoneCanWrite) everyoneAllow.push(...sendPerms);
  else everyoneDeny.push(...sendPerms);

  overwrites.push({ id: guild.id, allow: everyoneAllow, deny: everyoneDeny });

  const roleNames = new Set([...view, ...write].filter((n) => n !== '@everyone'));
  for (const name of roleNames) {
    const role = resolveRole(guild, name);
    if (!role) {
      console.warn(`   ⚠️  الرول غير موجود بعد، تم تجاهله في overwrite: ${name}`);
      continue;
    }
    const allow = [PermissionFlagsBits.ViewChannel];
    if (write.includes(name)) allow.push(...sendPerms);
    overwrites.push({ id: role.id, allow, deny: [] });
  }

  return overwrites;
}

module.exports = { buildOverwrites, resolveRole };
