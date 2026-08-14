// اختبار محلي لقوالب الرسائل — ما يتصل بديسكورد ولا يرسل شيء.
// يتأكد إن كل متغيّر بالقوالب ينتعبّى فعلًا، وإن روابط القنوات داخل رسالة الخاص
// روابط كاملة قابلة للضغط (مو منشن <#id> اللي ما يشتغل برّا السيرفر).
//
// الاستخدام:  npm run test:templates

const cfg = require('./config/welcome');
const { buildTemplateVars, fillTemplate } = require('./lib/templateVars');

let passed = 0;
let failed = 0;
function check(label, cond, detail = '') {
  if (cond) { passed++; console.log(`  ✅ ${label}${detail ? `  ${detail}` : ''}`); }
  else { failed++; console.log(`  ❌ ${label}${detail ? `  ${detail}` : ''}`); }
}

const GUILD = '1535571261395312680';
const vars = buildTemplateVars({
  guildId: GUILD,
  serverName: 'ENCLAVE RP',
  memberId: '111',
  memberTag: 'tester',
  displayName: 'Tester',
  memberCount: 25,
  welcomeChannelId: '222',
  rulesChannelId: '333',
  ticketChannelId: '444',
  inviter: '<@999>',
});

console.log('\n── قوالب الرسائل ────────────────────────────────────');

for (const [name, tpl] of [['contentTemplate', cfg.contentTemplate], ['dmMessage', cfg.dmMessage]]) {
  const out = fillTemplate(tpl, vars);
  const leftover = out.match(/\{(\w+)\}/g);
  check(`${name}: ما فيه متغيّر غير معرّف`, !leftover, leftover ? `متبقّي: ${leftover.join(' ')}` : '');
}

console.log('\n── روابط رسالة الخاص (لازم تكون قابلة للضغط) ────────');
const dm = fillTemplate(cfg.dmMessage, vars);

check('فيها رابط قناة الطيران كامل', dm.includes(`https://discord.com/channels/${GUILD}/222`));
check('فيها رابط القوانين كامل', dm.includes(`https://discord.com/channels/${GUILD}/333`));
check('فيها رابط التذاكر كامل', dm.includes(`https://discord.com/channels/${GUILD}/444`));
check('ما تستخدم منشن <#id> (ما ينضغط بالـ DM)', !/<#\d+>/.test(dm),
  (dm.match(/<#\d+>/g) || []).join(' '));

console.log('\n── تعطّل رشيق لو قناة ناقصة ──────────────────────────');
const missing = buildTemplateVars({
  guildId: GUILD, serverName: 'X', memberId: '1', memberTag: 't',
  displayName: 'T', memberCount: 1,
  welcomeChannelId: null, rulesChannelId: null, ticketChannelId: null,
});
const dmMissing = fillTemplate(cfg.dmMessage, missing);
check('ما ينكسر لو القنوات مو موجودة', typeof dmMissing === 'string' && dmMissing.length > 0);
check('ما يطلع رابط ناقص فيه null/undefined', !/null|undefined/.test(dmMissing));
check('الداعي الافتراضي "رابط دعوة السيرفر"', missing.inviter === 'رابط دعوة السيرفر');

console.log('\n── صحة إعدادات القنوات ──────────────────────────────');
for (const key of ['channelName', 'rulesChannelName', 'ticketChannelName']) {
  const v = cfg[key];
  check(`${key} معرّف`, v === null || (typeof v === 'string' && v.trim().length > 0), String(v));
}

console.log(`\n${failed === 0 ? '✅' : '❌'} النتيجة: ${passed} نجح، ${failed} فشل\n`);
process.exit(failed === 0 ? 0 : 1);
