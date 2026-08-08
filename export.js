// يقرأ الهيكل الفعلي من سيرفرك على Discord (رولات + أقسام + قنوات + صلاحيات)
// ويصدّره لملف server-snapshot.json — يُستخدم لمطابقة config/*.js مع أي تعديل يدوي سويته على Discord مباشرة
//
// الاستخدام:
//   node export.js

const fs = require('fs');
const { ChannelType, PermissionFlagsBits } = require('discord.js');
const { connect } = require('./lib/discordClient');

// يحوّل قيمة الصلاحية (BigInt) لأسماء مقروءة
function permsToNames(bitfield) {
  const names = [];
  for (const [name, bit] of Object.entries(PermissionFlagsBits)) {
    if (bitfield.has(bit)) names.push(name);
  }
  return names;
}

function overwritesToReadable(guild, channel) {
  const result = [];
  for (const ow of channel.permissionOverwrites.cache.values()) {
    let subject;
    if (ow.id === guild.id) subject = '@everyone';
    else {
      const role = guild.roles.cache.get(ow.id);
      subject = role ? role.name : `[unknown:${ow.id}]`;
    }
    result.push({
      target: subject,
      allow: permsToNames(ow.allow),
      deny: permsToNames(ow.deny),
    });
  }
  return result;
}

async function main() {
  const { client, guild } = await connect();
  console.log(`🔗 متصل بسيرفر: ${guild.name} — جاري القراءة...`);

  // الرولات (من الأعلى للأسفل حسب موقعها الفعلي بالسيرفر)
  const roles = guild.roles.cache
    .filter((r) => r.name !== '@everyone')
    .sort((a, b) => b.position - a.position)
    .map((r) => ({
      name: r.name,
      color: `#${r.color.toString(16).padStart(6, '0')}`,
      hoist: r.hoist,
      mentionable: r.mentionable,
      position: r.position,
      permissions: permsToNames(r.permissions),
    }));

  // الأقسام والقنوات
  const categories = guild.channels.cache
    .filter((c) => c.type === ChannelType.GuildCategory)
    .sort((a, b) => a.position - b.position)
    .map((cat) => {
      const children = guild.channels.cache
        .filter((c) => c.parentId === cat.id)
        .sort((a, b) => a.position - b.position)
        .map((ch) => ({
          name: ch.name,
          type: ch.type === ChannelType.GuildVoice ? 'voice' : ch.type === ChannelType.GuildText ? 'text' : `other(${ch.type})`,
          overwrites: overwritesToReadable(guild, ch),
        }));

      return {
        name: cat.name,
        overwrites: overwritesToReadable(guild, cat),
        channels: children,
      };
    });

  // قنوات بلا Category (لو فيه)
  const orphanChannels = guild.channels.cache
    .filter((c) => !c.parentId && c.type !== ChannelType.GuildCategory && c.type !== ChannelType.GuildCategory)
    .map((ch) => ({ name: ch.name, type: ch.type === ChannelType.GuildVoice ? 'voice' : 'text' }));

  const snapshot = {
    exportedAt: new Date().toISOString(),
    guildName: guild.name,
    roles,
    categories,
    orphanChannels,
  };

  fs.writeFileSync('server-snapshot.json', JSON.stringify(snapshot, null, 2), 'utf8');
  console.log(`\n✅ تم الحفظ في server-snapshot.json`);
  console.log(`   الرولات: ${roles.length} | الأقسام: ${categories.length} | قنوات بلا قسم: ${orphanChannels.length}`);
  console.log(`\n📤 ارفع هذا الملف هنا بالمحادثة (أو انسخ محتواه) عشان أحدّث config/categories.js و config/roles.js ليطابق الوضع الحالي.\n`);

  client.destroy();
  process.exit(0);
}

main().catch((err) => {
  console.error('❌ خطأ:', err);
  process.exit(1);
});
