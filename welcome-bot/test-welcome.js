// اختبار محلي لصورة الترحيب — ما يرسل أي شيء لديسكورد إطلاقًا.
// يقرأ بيانات العضو (اسم + أفاتار) وعدد أعضاء السيرفر عبر REST فقط (GET)،
// يركّب الصورة، ويحفظها بملف محلي عشان تشوف النتيجة قبل التشغيل الحقيقي.
//
// الاستخدام:
//   node test-welcome.js                       ← يستخدم TEST_USER_ID الافتراضي بالأسفل
//   node test-welcome.js <userId>              ← عضو ثاني
//   node test-welcome.js <userId> <outputPath> ← مسار حفظ مخصص

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { composeWelcomeImage } = require('./lib/composeWelcomeImage');

const TEST_USER_ID = '1119011672351330377';
const API = 'https://discord.com/api/v10';

const userId = process.argv[2] || TEST_USER_ID;
const outPath = path.resolve(process.argv[3] || path.join(__dirname, 'test-output.png'));

const token = process.env.DISCORD_TOKEN;
const guildId = process.env.GUILD_ID;

if (!token) {
  console.error('❌ الملف .env ناقص: DISCORD_TOKEN مطلوب');
  process.exit(1);
}

async function api(route) {
  const res = await fetch(`${API}${route}`, { headers: { Authorization: `Bot ${token}` } });
  if (!res.ok) throw new Error(`${route} → ${res.status} ${res.statusText}`);
  return res.json();
}

function avatarUrl(user) {
  // نجبره PNG دائمًا (حتى لو الأفاتار متحرك a_) لأن الصورة النهائية ثابتة
  if (user.avatar) {
    return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.png?size=512`;
  }
  // أفاتار افتراضي لحسابات بدون صورة
  const index = user.discriminator && user.discriminator !== '0'
    ? Number(user.discriminator) % 5
    : Number((BigInt(user.id) >> 22n) % 6n);
  return `https://cdn.discordapp.com/embed/avatars/${index}.png`;
}

(async () => {
  console.log(`🔎 نجيب بيانات العضو ${userId} ...`);
  const user = await api(`/users/${userId}`);

  // نحاول نجيب اللقب داخل السيرفر (nickname) لو العضو موجود فيه
  let nickname = null;
  if (guildId) {
    try {
      const member = await api(`/guilds/${guildId}/members/${userId}`);
      nickname = member.nick || null;
    } catch (err) {
      console.log(`   ℹ️  العضو مو موجود بالسيرفر أو ما نقدر نقرأ عضويته (${err.message})`);
    }
  }

  let memberCount = null;
  if (guildId) {
    try {
      const guild = await api(`/guilds/${guildId}?with_counts=true`);
      memberCount = guild.approximate_member_count ?? null;
      console.log(`👥 عدد أعضاء "${guild.name}": ${memberCount}`);
    } catch (err) {
      console.log(`   ℹ️  ما قدرنا نقرأ عدد الأعضاء (${err.message})`);
    }
  }

  const displayName = nickname || user.global_name || user.username;

  console.log(`   الاسم المعروض : ${displayName}`);
  console.log(`   اليوزرنيم     : @${user.username}`);
  console.log(`   الأفاتار      : ${avatarUrl(user)}`);

  const buffer = await composeWelcomeImage(avatarUrl(user), {
    displayName,
    username: user.username,
    memberCount: memberCount ?? 0,
  });

  fs.writeFileSync(outPath, buffer);
  console.log(`\n✅ تم الحفظ محليًا (ما تم إرسال شيء لديسكورد): ${outPath}`);
})().catch((err) => {
  console.error('❌ فشل الاختبار:', err.message);
  process.exit(1);
});
