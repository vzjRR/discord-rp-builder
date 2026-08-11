// اختبار محلي لرسم الأسماء — ما يتصل بديسكورد ولا يرسل أي شيء.
// يفحص إن الأسماء العربية/المختلطة تنرسم موصولة وبالترتيب الصحيح، وإن باقي
// أنواع الأسماء (لاتيني، أرقام، رياضي، سيريلك، رموز) ما انكسرت.
//
// الاستخدام:  npm run test:names
//   وبيطلع كمان صور معاينة بمجلد  test-names-output/  تقدر تفتحها وتتأكد بعينك.

const fs = require('fs');
const path = require('path');
const {
  renderTextLayer,
  textComposite,
  probeFonts,
  isCursiveScript,
  normalizeForRender,
  LAYOUT,
} = require('./lib/composeWelcomeImage');

const OUT_DIR = path.join(__dirname, 'test-names-output');

let passed = 0;
let failed = 0;

function check(label, condition, detail = '') {
  if (condition) {
    passed++;
    console.log(`  ✅ ${label}${detail ? `  ${detail}` : ''}`);
  } else {
    failed++;
    console.log(`  ❌ ${label}${detail ? `  ${detail}` : ''}`);
  }
}

const NAME_STYLE = LAYOUT.displayName;

async function inkWidth(text) {
  const r = await renderTextLayer(text, NAME_STYLE);
  return r ? r.width : 0;
}

// أسماء واقعية من ديسكورد — عربية، مختلطة، ولاتينية
const NAMES = [
  'azبانيذا',          // ← الاسم اللي كشف المشكلة
  'بانيذا',
  'مرحبا',
  'محمد العتيبي',
  'عبدالله',
  'لا إله إلا الله',    // فيه ليجاتشر لا متكرر
  'أحمد٢٠٢٤',          // عربي + أرقام هندية
  'Ali علي 99',
  'زيد Zaid زيد',       // عربي-لاتيني-عربي
  'ســـلام',            // فيه تطويل (kashida)
  'Xx_Gamer_xX',
  'ＦＵＬＬＷＩＤＴＨ',
  '𝑃𝐿𝑎𝑛𝑘',
  'Привет',
  '★ Nova ★',
  '12345',
  'a',
  '🔥 Blaze 🔥',
  'أحمد 🇸🇦',
  '👑 King',
  '😀🎮✈️⭐',
  'إبراهيم عبد الرحمن الشمري الطويل جدا',  // اسم طويل يتقلّص
];

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });

  console.log('\n── 1. فحص الخطوط والوصل ─────────────────────────────');
  const p = await probeFonts();
  check('الخطوط المدمجة محمّلة', Boolean(p.barlow && p.noto && p.barlow !== p.noto),
    `Barlow=${p.barlow} NotoSans=${p.noto}`);
  check('العربي ينرسم', Boolean(p.arabic), `عربي=${p.arabic}`);
  check('حروف العربي تتوصل', p.arabicJoined === true, `نسبة الوصل=${p.joinRatio} (<0.8)`);
  check('probeFonts.ok', p.ok === true);

  console.log('\n── 2. فحص وصل الحروف عبر مسار الرسم الحقيقي ──────────');
  const one = await inkWidth('ب');
  const three = await inkWidth('ببب');
  const ratio = one ? three / (one * 3) : 0;
  check('"ببب" أضيق من ٣ باءات مفردة (وصل شغّال)', ratio > 0 && ratio < 0.8,
    `ب=${one} ببب=${three} نسبة=${ratio.toFixed(2)}`);

  const lam = await inkWidth('ل');
  const alef = await inkWidth('ا');
  const lamAlef = await inkWidth('لا');
  check('ليجاتشر "لا" يتكوّن', lamAlef > 0 && lamAlef < (lam + alef) * 0.85,
    `لا=${lamAlef} مقابل ل+ا=${lam + alef}`);

  const mixed = await inkWidth('azبانيذا');
  const pureAr = await inkWidth('بانيذا');
  const az = await inkWidth('az');
  check('المختلط "azبانيذا" = az + العربي الموصول (بدون تفكيك)',
    mixed > pureAr && mixed < pureAr + az + 20,
    `مختلط=${mixed} عربي=${pureAr} az=${az}`);

  console.log('\n── 3. كشف السكربتات المتصلة ─────────────────────────');
  check('يكشف العربي', isCursiveScript('بانيذا') === true);
  check('يكشف المختلط', isCursiveScript('azبانيذا') === true);
  check('ما يكشف اللاتيني', isCursiveScript('PlainName') === false);
  check('ما يكشف الأرقام', isCursiveScript('12345') === false);
  check('ما يكشف السيريلك', isCursiveScript('Привет') === false);

  console.log('\n── 3.5 الحروف العريضة (Fullwidth) ما تطلع مربعات ────');
  check('ＦＵＬＬ → FULL', normalizeForRender('ＦＵＬＬ') === 'FULL');
  check('ＸＸ＿１２３ → XX_123', normalizeForRender('ＸＸ＿１２３') === 'XX_123');
  check('المسافة العريضة تصير مسافة عادية', normalizeForRender('ａ　ｂ') === 'a b');
  check('ما يلمس العربي', normalizeForRender('بانيذا') === 'بانيذا');
  check('ما يلمس ASCII', normalizeForRender('Plain_123') === 'Plain_123');
  {
    const fw = await textComposite('ＦＵＬＬＷＩＤＴＨ', NAME_STYLE);
    const ascii = await textComposite('FULLWIDTH', NAME_STYLE);
    const a = await require('sharp')(fw.input).metadata();
    const b = await require('sharp')(ascii.input).metadata();
    check('العريض ينرسم نفس ASCII (مو tofu)', a.width === b.width && a.height === b.height,
      `عريض=${a.width}x${a.height} ascii=${b.width}x${b.height}`);
  }

  console.log('\n── 3.6 الإيموجي تنرسم فعلًا (مو مربعات tofu) ────────');
  // الحيلة: نرسم كودبوينت غير معرّف نهائيًا (U+1FFFD) — هذا *دايمًا* يطلع مربع
  // tofu بنفس مقاس أي مربع لكودبوينت من ٥ خانات hex. فلو الإيموجي طلعت بنفس
  // المقاس بالضبط معناها هي كمان tofu ومحد رسمها.
  const tofuRef = await renderTextLayer('\u{1FFFD}', NAME_STYLE);
  const tofuSize = tofuRef ? `${tofuRef.width}x${tofuRef.height}` : 'none';
  for (const [emoji, label] of [
    ['\u{1F600}', '😀'],
    ['\u{1F525}', '🔥'],
    ['\u{2708}️', '✈️'],
    ['\u{1F3AE}', '🎮'],
    ['\u{1F451}', '👑'],
  ]) {
    const r = await renderTextLayer(emoji, NAME_STYLE);
    const size = r ? `${r.width}x${r.height}` : 'none';
    check(`${label} تنرسم بخط الإيموجي`, Boolean(r) && size !== tofuSize,
      `${size} (مربع tofu = ${tofuSize})`);
  }

  console.log('\n── 4. رسم كل الأسماء بدون أخطاء ─────────────────────');
  for (const name of NAMES) {
    try {
      const layer = await textComposite(name, NAME_STYLE);
      if (!layer) {
        check(`"${name}"`, false, '→ رجع null (ما انرسم أي بكسل)');
        continue;
      }
      const meta = await require('sharp')(layer.input).metadata();
      const fitsW = meta.width <= NAME_STYLE.maxWidth;
      const fitsH = meta.height <= NAME_STYLE.maxHeight;
      check(`"${name}"`, fitsW && fitsH,
        `${meta.width}x${meta.height} داخل ${NAME_STYLE.maxWidth}x${NAME_STYLE.maxHeight}`);

      const safe = name.replace(/[^\p{L}\p{N}]+/gu, '_').slice(0, 24) || 'name';
      fs.writeFileSync(path.join(OUT_DIR, `${safe}.png`), layer.input);
    } catch (err) {
      check(`"${name}"`, false, `→ استثناء: ${err.message}`);
    }
  }

  console.log('\n── 5. حالات حدّية ───────────────────────────────────');
  for (const edge of [null, undefined, '', '   ']) {
    const r = await textComposite(edge, NAME_STYLE);
    check(`قيمة فاضية (${JSON.stringify(edge)}) ترجع null بدل ما تكسر`, r === null);
  }

  console.log(`\n📁 صور المعاينة: ${OUT_DIR}`);
  console.log(`\n${failed === 0 ? '✅' : '❌'} النتيجة: ${passed} نجح، ${failed} فشل\n`);
  process.exit(failed === 0 ? 0 : 1);
})().catch((err) => {
  console.error('❌ فشل الاختبار:', err);
  process.exit(1);
});
