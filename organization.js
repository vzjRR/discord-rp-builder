// ينشئ Category خاصة بمنظمة واحدة عند اعتمادها (بدل إنشاء Gang 1/2/3 يدويًا بشكل دائم)
// الاستخدام:
//   node organization.js "اسم المنظمة"
//
// ينشئ تلقائيًا:
//   - رول 🔒 Org: <name>
//   - كاتيجوري [ ORGANIZATION — <NAME> ]
//   - قنوات: chat / announcements / management / operations + صوت
//   - صلاحيات: أعضاء المنظمة فقط + STAFF_UP للإشراف

const { ChannelType, PermissionFlagsBits } = require('discord.js');
const { connect } = require('./lib/discordClient');
const { buildOverwrites } = require('./lib/permissions');
const T = require('./config/constants');

async function createOrganization(orgName) {
  const { client, guild } = await connect();

  const roleName = `🔒 Org: ${orgName}`;
  let role = guild.roles.cache.find((r) => r.name === roleName);
  if (!role) {
    role = await guild.roles.create({
      name: roleName,
      color: '#992D22',
      hoist: false,
      mentionable: false,
      permissions: [],
      reason: `منظمة جديدة معتمدة: ${orgName}`,
    });
    console.log(`✅ تم إنشاء رول: ${roleName}`);
  } else {
    console.log(`⏭️  الرول موجود مسبقًا: ${roleName}`);
  }

  const categoryName = `[ ORGANIZATION — ${orgName.toUpperCase()} ]`;
  const access = { view: [...T.STAFF_UP, roleName], write: [...T.STAFF_UP, roleName] };

  let category = guild.channels.cache.find((c) => c.type === ChannelType.GuildCategory && c.name === categoryName);
  if (!category) {
    category = await guild.channels.create({
      name: categoryName,
      type: ChannelType.GuildCategory,
      permissionOverwrites: buildOverwrites(guild, access, 'text'),
      reason: `منظمة جديدة معتمدة: ${orgName}`,
    });
    console.log(`✅ تم إنشاء الكاتيجوري: ${categoryName}`);
  } else {
    console.log(`⏭️  الكاتيجوري موجود مسبقًا: ${categoryName}`);
  }

  const channelsToCreate = [
    { name: '💬・chat', type: 'text' },
    { name: '📢・announcements', type: 'text', write: [...T.STAFF_UP] }, // القيادة فقط تعلن؛ عدّلها لو تحتاج رول قائد منفصل
    { name: '📋・management', type: 'text' },
    { name: '📦・operations', type: 'text' },
    { name: '🔊・Organization', type: 'voice' },
  ];

  const existingChildren = guild.channels.cache.filter((c) => c.parentId === category.id);
  for (const ch of channelsToCreate) {
    if (existingChildren.find((c) => c.name === ch.name)) {
      console.log(`   ⏭️  القناة موجودة: ${ch.name}`);
      continue;
    }
    const chAccess = { view: access.view, write: ch.write || access.write };
    await guild.channels.create({
      name: ch.name,
      type: ch.type === 'voice' ? ChannelType.GuildVoice : ChannelType.GuildText,
      parent: category.id,
      permissionOverwrites: buildOverwrites(guild, chAccess, ch.type),
      reason: `منظمة جديدة معتمدة: ${orgName}`,
    });
    console.log(`   ✅ تم إنشاء: ${ch.name}`);
  }

  console.log(`\n🎉 المنظمة "${orgName}" جاهزة. أعطِ الرول "${roleName}" لأعضائها.\n`);
  client.destroy();
  process.exit(0);
}

const orgName = process.argv[2];
if (!orgName) {
  console.log('الاستخدام: node organization.js "اسم المنظمة"');
  process.exit(1);
}

createOrganization(orgName).catch((err) => {
  console.error('❌ خطأ:', err);
  process.exit(1);
});
