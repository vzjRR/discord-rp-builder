const { ChannelType, PermissionFlagsBits } = require('discord.js');
const { connect } = require('./lib/discordClient');
const { buildOverwrites } = require('./lib/permissions');
const roleDefs = require('./config/roles');
const categoryDefs = require('./config/categories');
const zeroToleranceCfg = require('./welcome-bot/config/zeroTolerance');

const PENDING_ROLE_NAME = '⏳ Pending Verification';

function permBits(names = []) {
  return names.map((n) => {
    const bit = PermissionFlagsBits[n];
    if (bit === undefined) throw new Error(`صلاحية غير معروفة: ${n}`);
    return bit;
  });
}

// ─────────────────────────────────────────────────────────────
// 1) ROLES — يُنشئ الرولات الناقصة فقط، بنفس ترتيب config/roles.js
// ─────────────────────────────────────────────────────────────
async function createRoles(guild) {
  console.log(`\n🎭 المرحلة 1/2 — الرولات (${roleDefs.length} رول في القائمة)\n`);

  for (const def of roleDefs) {
    const existing = guild.roles.cache.find((r) => r.name === def.name);
    if (existing) {
      console.log(`   ⏭️  موجود مسبقًا: ${def.name}`);
      continue;
    }
    try {
      await guild.roles.create({
        name: def.name,
        color: def.color,
        hoist: !!def.hoist,
        mentionable: !!def.mentionable,
        permissions: permBits(def.permissions),
        reason: 'Discord RP Builder — إنشاء تلقائي',
      });
      console.log(`   ✅ تم إنشاء: ${def.name}`);
    } catch (err) {
      console.error(`   ❌ فشل إنشاء ${def.name}: ${err.message}`);
    }
  }

  console.log('\n📌 تذكير: رتّب الرولات يدويًا حسب Role Hierarchy في الدوكيومنت (Server Settings → Roles)');
  console.log('   ورول البوت نفسه لازم يكون فوق كل الرولات اللي أنشأها عشان يقدر يعدّل صلاحياتها لاحقًا.\n');
}

// ─────────────────────────────────────────────────────────────
// 2) CATEGORIES + CHANNELS
// ─────────────────────────────────────────────────────────────
function normalizeChannel(entry, categoryDefaults) {
  if (typeof entry === 'string') {
    return { name: entry, type: 'text', view: categoryDefaults.view, write: categoryDefaults.write };
  }
  return {
    name: entry.name,
    type: entry.type || 'text',
    view: entry.view || categoryDefaults.view,
    write: entry.write || categoryDefaults.write,
  };
}

async function ensureCategory(guild, catDef) {
  let category = guild.channels.cache.find((c) => c.type === ChannelType.GuildCategory && c.name === catDef.name);

  const overwrites = buildOverwrites(guild, { view: catDef.view, write: catDef.write }, 'text');

  if (!category) {
    category = await guild.channels.create({
      name: catDef.name,
      type: ChannelType.GuildCategory,
      permissionOverwrites: overwrites,
      reason: 'Discord RP Builder — إنشاء تلقائي',
    });
    console.log(`\n📁 تم إنشاء الكاتيجوري: ${catDef.name}`);
  } else {
    console.log(`\n📁 الكاتيجوري موجود مسبقًا: ${catDef.name} (سيتم فقط إضافة القنوات الناقصة)`);
  }

  const existingChildren = guild.channels.cache.filter((c) => c.parentId === category.id);

  for (const rawChannel of catDef.channels) {
    const ch = normalizeChannel(rawChannel, catDef);
    const discordType = ch.type === 'voice' ? ChannelType.GuildVoice : ChannelType.GuildText;

    const alreadyExists = existingChildren.find((c) => c.name === ch.name);
    if (alreadyExists) {
      console.log(`   ⏭️  القناة موجودة: ${ch.name}`);
      continue;
    }

    const chOverwrites = buildOverwrites(guild, { view: ch.view, write: ch.write }, ch.type);
    try {
      await guild.channels.create({
        name: ch.name,
        type: discordType,
        parent: category.id,
        permissionOverwrites: chOverwrites,
        reason: 'Discord RP Builder — إنشاء تلقائي',
      });
      console.log(`   ✅ تم إنشاء القناة: ${ch.name} (${ch.type})`);
    } catch (err) {
      console.error(`   ❌ فشل إنشاء ${ch.name}: ${err.message}`);
    }
  }
}

async function createCategories(guild, onlyKey) {
  const list = onlyKey ? categoryDefs.filter((c) => c.key === onlyKey) : categoryDefs;
  if (onlyKey && list.length === 0) {
    console.error(`❌ لا يوجد قسم بالمفتاح "${onlyKey}". استخدم "node build.js list" لعرض كل المفاتيح.`);
    return;
  }
  console.log(`\n🏗️  المرحلة 2/2 — الأقسام والقنوات (${list.length} قسم)`);
  for (const catDef of list) {
    await ensureCategory(guild, catDef);
  }
}

function listKeys() {
  console.log('\nمفاتيح الأقسام المتاحة (استخدمها مع: node build.js categories <key>):\n');
  for (const c of categoryDefs) console.log(`  - ${c.key.padEnd(24)} ${c.name}`);
  console.log('');
}

// ─────────────────────────────────────────────────────────────
// 3) بوابة التحقق المؤجل — تقيّد رؤية رول "⏳ Pending Verification" على
// قناة صفر التسامح فقط، بلا أي أثر على باقي الرولات. يعمل على القنوات
// الحيّة فعليًا بالسيرفر (لا على config/categories.js الذي قد لا يطابق
// آخر تغييرات يدوية) — يجلب كل الأقسام والقنوات المستقلة (بلا قسم) وقت
// التشغيل، فيبقى صحيحًا مهما تغيّرت بنية السيرفر لاحقًا. آمن التكرار.
async function applyVerificationGate(guild) {
  console.log('\n🚪 بوابة التحقق المؤجل — تقييد الرؤية لرول "⏳ Pending Verification"\n');

  const pendingRole = guild.roles.cache.find((r) => r.name === PENDING_ROLE_NAME);
  if (!pendingRole) {
    console.error(`❌ رول "${PENDING_ROLE_NAME}" غير موجود — شغّل "node build.js roles" أولًا.`);
    return;
  }

  const gateChannelId = zeroToleranceCfg.channelId;
  if (!gateChannelId) {
    console.error('❌ welcome-bot/config/zeroTolerance.js بدون channelId — لا توجد قناة نستثنيها من التقييد.');
    return;
  }

  await guild.channels.fetch();
  const gateChannel = guild.channels.cache.get(gateChannelId);
  if (!gateChannel) {
    console.error(`❌ ما لقيت قناة بالمعرّف ${gateChannelId} على هذا السيرفر.`);
    return;
  }

  const categories = guild.channels.cache.filter((c) => c.type === ChannelType.GuildCategory);
  const orphanChannels = guild.channels.cache.filter(
    (c) => !c.parentId && c.type !== ChannelType.GuildCategory && c.id !== gateChannelId
  );

  let changed = 0;
  for (const category of categories.values()) {
    try {
      await category.permissionOverwrites.edit(pendingRole.id, { ViewChannel: false });
      changed += 1;
    } catch (err) {
      console.error(`   ❌ فشل تقييد القسم "${category.name}": ${err.message}`);
    }
  }
  for (const channel of orphanChannels.values()) {
    try {
      await channel.permissionOverwrites.edit(pendingRole.id, { ViewChannel: false });
      changed += 1;
    } catch (err) {
      console.error(`   ❌ فشل تقييد القناة "${channel.name}": ${err.message}`);
    }
  }

  try {
    await gateChannel.permissionOverwrites.edit(pendingRole.id, { ViewChannel: true });
    console.log(`   ✅ قناة "${gateChannel.name}" تبقى ظاهرة لرول الانتظار`);
  } catch (err) {
    console.error(`   ❌ فشل إظهار قناة الانتظار: ${err.message}`);
  }

  console.log(`\n🎉 تم تقييد ${changed} قسم/قناة — رول "${PENDING_ROLE_NAME}" الآن لا يرى إلا "${gateChannel.name}".\n`);
}

// ─────────────────────────────────────────────────────────────
// CLI
// ─────────────────────────────────────────────────────────────
async function main() {
  const [, , phase, arg] = process.argv;

  if (!phase || !['roles', 'categories', 'all', 'list', 'verification-gate'].includes(phase)) {
    console.log(`
الاستخدام:
  node build.js roles                  → ينشئ كل الرولات الناقصة فقط
  node build.js categories             → ينشئ كل الأقسام والقنوات الناقصة
  node build.js categories <key>       → ينشئ قسم واحد فقط (للانتقال التدريجي)
  node build.js all                    → roles ثم categories بالكامل
  node build.js list                   → يعرض مفاتيح كل الأقسام
  node build.js verification-gate      → يقيّد رول "⏳ Pending Verification" على قناة صفر التسامح فقط
`);
    process.exit(0);
  }

  if (phase === 'list') {
    listKeys();
    process.exit(0);
  }

  const { client, guild } = await connect();
  console.log(`🔗 متصل بسيرفر: ${guild.name}`);

  if (phase === 'roles' || phase === 'all') {
    await createRoles(guild);
    await guild.roles.fetch(); // تحديث الكاش قبل استخدامها في overwrites
  }
  if (phase === 'categories' || phase === 'all') {
    await createCategories(guild, phase === 'categories' ? arg : undefined);
  }
  if (phase === 'verification-gate') {
    await guild.roles.fetch();
    await applyVerificationGate(guild);
  }

  console.log('\n🎉 انتهى.\n');
  client.destroy();
  process.exit(0);
}

main().catch((err) => {
  console.error('❌ خطأ عام:', err);
  process.exit(1);
});
