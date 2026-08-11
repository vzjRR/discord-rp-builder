// يركّب صورة ترحيب Enclave RP فوق assets/welcome_template.png:
//   • صورة العضو (Avatar) داخل الدائرة اليمنى (مكان الدائرة الخضراء بالتصميم)
//   • الاسم المعروض (Display Name) تحت كلمة WELCOME
//   • اليوزرنيم (@username) داخل الصندوق اللي تحت الأفاتار
//   • عدد أعضاء السيرفر داخل صندوق CURRENT MEMBERS تحت اليسار
// ويرجع Buffer لصورة PNG جاهزة للإرسال.
//
// كل الإحداثيات بالأسفل (LAYOUT) مقاسة على تصميم welcome_template.png الحالي
// (1858×846). لو غيّرت التصميم أو مقاسه لازم تعيد ضبطها.
// الدائرة الخضراء بالتصميم هي مجرد Placeholder — نغطيها بصورة العضو بالكامل.

const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

// ── الخطوط المدمجة ──────────────────────────────────────────────
// ما نعتمد على خطوط النظام إطلاقًا: Railway يشتغل لينكس وما فيه خطوط ويندوز،
// فلو اعتمدنا عليها بتطلع النصوص بخط ثاني (سيرفي) أو مربعات فاضية.
// الخطوط بـ assets/fonts ومعها fonts.conf، ونوجّه fontconfig لها عبر
// المتغيّر FONTCONFIG_PATH داخل سكربتات package.json.
//   Barlow-Bold      → خط العرض الأساسي (لاتيني/أرقام)
//   NotoSansMath     → حروف اليونيكود الرياضية (مثل 𝑃𝐿𝑎𝑛𝑘 بأسماء ديسكورد)
//   NotoNaskhArabic  → الأسماء العربية (بترتيب RTL صحيح)
//   NotoSans         → احتياطي واسع (سيريلك/يوناني/رموز)
//
// ⚠️ لازم يُضبط FONTCONFIG_PATH *قبل* ما تبدأ عملية Node — تغييره من داخل
// الكود ما يوصل لـ fontconfig لأنها تقرأه مرة وحدة عند تحميل المكتبة.
// عشان كذا شغّل دايمًا عبر `npm start` مو `node bot.js` مباشرة.
const FONTS_DIR = path.join(__dirname, '..', 'assets', 'fonts');

function checkBundledFonts() {
  const configured = process.env.FONTCONFIG_PATH
    ? path.resolve(process.env.FONTCONFIG_PATH)
    : null;

  if (configured === path.resolve(FONTS_DIR)) return;

  console.warn(
    '\n⚠️  FONTCONFIG_PATH مو مضبوط على assets/fonts — النصوص بتنرسم بخط احتياطي غلط.\n' +
      '   شغّل البوت بـ  npm start  (أو npm run test:image) بدل node مباشرة.\n' +
      `   الحالي: ${process.env.FONTCONFIG_PATH || '(غير مضبوط)'}\n`
  );
}

checkBundledFonts();

const TEMPLATE_PATH = path.join(__dirname, '..', 'assets', 'welcome_template.png');

const CANVAS = { width: 1858, height: 846 };

// مركز/نصف قطر الدائرة الخضراء بالتصميم. الأخضر الفعلي يمتد لين نصف قطر ≈154
// (بسبب ضغط JPEG)، فخلّينا RADIUS = 156 عشان يغطيه كامل بدون ما يلمس الحلقة
// النيون (تبدأ ≈159)، و FEATHER يخفف تسنين الحافة.
const CENTER = { x: 1490, y: 359 };
const RADIUS = 156;
const FEATHER = 1.5;

// كلها خطوط مدمجة بـ assets/fonts (شوف setupBundledFonts فوق)
const FONT_STACK = "Barlow, 'Noto Sans Math', 'Noto Naskh Arabic', 'Noto Sans', sans-serif";

// مواقع النصوص الثلاثة — كل واحد صندوق نحصر النص جواه ونوسّطه
const LAYOUT = {
  // الاسم المعروض: الشريط الفاضي بين الخطين تحت كلمة WELCOME
  displayName: {
    centerX: 920,
    centerY: 500,
    maxWidth: 660,
    maxHeight: 78,
    fontSize: 64,
    letterSpacing: 2,
    color: '#ffffff',
    glow: '#a855f7',
    glowRadius: 7,
  },
  // اليوزرنيم: الصندوق اللي تحت الأفاتار مباشرة
  username: {
    centerX: 1481,
    centerY: 594,
    maxWidth: 296,
    maxHeight: 62,
    fontSize: 40,
    letterSpacing: 1,
    color: '#e9d8ff',
    glow: '#a855f7',
    glowRadius: 5,
  },
  // عدد الأعضاء: تحت عبارة CURRENT MEMBERS داخل صندوق تحت اليسار
  memberCount: {
    centerX: 377,
    centerY: 727,
    maxWidth: 200,
    maxHeight: 52,
    fontSize: 46,
    letterSpacing: 2,
    color: '#ffffff',
    glow: '#c084fc',
    glowRadius: 6,
  },
};

function escapeXml(str) {
  return String(str).replace(/[<>&'"]/g, (c) =>
    ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' }[c])
  );
}

// يرسم النص على كانفاس شفاف ثم يقصّه على حدود الحبر بالضبط (trim)، عشان نقدر
// نوسّطه بدقة داخل صندوقه ونصغّره لو طلع أعرض من الصندوق.
async function renderTextLayer(text, style) {
  const { fontSize, letterSpacing, color, glow, glowRadius } = style;
  const pad = glowRadius * 3 + 10;
  const w = 4000;
  const h = Math.ceil(fontSize * 2.4) + pad * 2;
  const baseline = Math.round(h / 2 + fontSize * 0.36);

  const svg = `<svg width="${w}" height="${h}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="g" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="${glowRadius}" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <g filter="url(#g)">
    <text x="${pad}" y="${baseline}" font-family="${FONT_STACK}" font-size="${fontSize}"
          font-weight="bold" letter-spacing="${letterSpacing}" fill="${glow}"
          opacity="0.85">${escapeXml(text)}</text>
  </g>
  <text x="${pad}" y="${baseline}" font-family="${FONT_STACK}" font-size="${fontSize}"
        font-weight="bold" letter-spacing="${letterSpacing}" fill="${color}">${escapeXml(text)}</text>
</svg>`;

  // لو النص ما رسم أي بكسل (اسم كله إيموجي ملوّن أو رموز ما يغطيها أي خط)
  // فـ trim يطيح على صورة شفافة بالكامل — نرجّع null بدل ما نكسر الترحيب كله.
  try {
    const { data, info } = await sharp(Buffer.from(svg))
      .trim({ threshold: 6 })
      .png()
      .toBuffer({ resolveWithObject: true });

    if (info.width < 2 || info.height < 2) return null;
    return { buffer: data, width: info.width, height: info.height };
  } catch {
    return null;
  }
}

// يرجع طبقة النص جاهزة للتركيب: مصغّرة لتناسب الصندوق + موضع (left/top) موسّط
async function textComposite(text, style) {
  if (text === null || text === undefined || String(text).trim() === '') return null;

  const rendered = await renderTextLayer(String(text).trim(), style);
  if (!rendered) return null;

  let { buffer, width, height } = rendered;

  const scale = Math.min(1, style.maxWidth / width, style.maxHeight / height);
  if (scale < 1) {
    const newW = Math.max(1, Math.round(width * scale));
    const newH = Math.max(1, Math.round(height * scale));
    buffer = await sharp(buffer).resize(newW, newH).png().toBuffer();
    width = newW;
    height = newH;
  }

  return {
    input: buffer,
    left: Math.round(style.centerX - width / 2),
    top: Math.round(style.centerY - height / 2),
  };
}

// قناع دائري بحواف ناعمة بنفس مقاس الأفاتار.
// لازم يكون RGBA (مو رمادي بقناة وحدة) لأن blend: 'dest-in' يشتغل على قناة الألفا،
// وصورة بقناة وحدة تُعتبر معتمة بالكامل فما تقص شيء.
function circleMask(size) {
  const r = size / 2;
  const mask = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = Math.hypot(x + 0.5 - r, y + 0.5 - r);
      let a = 255;
      if (d > r) a = 0;
      else if (d > r - FEATHER) a = Math.round((1 - (d - (r - FEATHER)) / FEATHER) * 255);
      const i = (y * size + x) * 4;
      mask[i] = mask[i + 1] = mask[i + 2] = 255;
      mask[i + 3] = a;
    }
  }
  return sharp(mask, { raw: { width: size, height: size, channels: 4 } }).png().toBuffer();
}

async function buildAvatarLayer(avatarUrl) {
  const resp = await fetch(avatarUrl);
  if (!resp.ok) throw new Error(`فشل تحميل صورة العضو (${resp.status})`);
  const avatarBuffer = Buffer.from(await resp.arrayBuffer());

  const size = RADIUS * 2;
  const avatar = await sharp(avatarBuffer)
    .resize(size, size, { fit: 'cover' })
    .ensureAlpha()
    .png()
    .toBuffer();

  const maskPng = await circleMask(size);

  // نضرب ألفا الأفاتار في القناع الدائري (dest-in) عشان يصير دائرة بحواف ناعمة
  const rounded = await sharp(avatar)
    .composite([{ input: maskPng, blend: 'dest-in' }])
    .png()
    .toBuffer();

  return { input: rounded, left: CENTER.x - RADIUS, top: CENTER.y - RADIUS };
}

/**
 * @param {string} avatarUrl        رابط صورة العضو (PNG يفضّل بمقاس 512)
 * @param {object} [info]
 * @param {string} [info.displayName]  الاسم المعروض — يُكتب تحت WELCOME
 * @param {string} [info.username]     اليوزرنيم — يُكتب تحت الأفاتار
 * @param {number} [info.memberCount]  عدد أعضاء السيرفر — يُكتب تحت اليسار
 */
async function composeWelcomeImage(avatarUrl, info = {}) {
  const layers = [await buildAvatarLayer(avatarUrl)];

  const usernameText = info.username ? `@${String(info.username).replace(/^@/, '')}` : null;
  const countText =
    typeof info.memberCount === 'number' ? info.memberCount.toLocaleString('en-US') : null;

  const texts = await Promise.all([
    textComposite(info.displayName, LAYOUT.displayName),
    textComposite(usernameText, LAYOUT.username),
    textComposite(countText, LAYOUT.memberCount),
  ]);

  for (const t of texts) if (t) layers.push(t);

  const templateBuffer = fs.readFileSync(TEMPLATE_PATH);
  return sharp(templateBuffer).composite(layers).png().toBuffer();
}

// فحص ذاتي للخطوط — يتأكد إن الخطوط المدمجة انحمّلت فعلًا وقت التشغيل.
// الفكرة: نقيس عرض نفس النص بخطين مختلفين من الحزمة. لو الخطوط ما انحمّلت،
// الاثنين بيرجعون لنفس الخط الاحتياطي فتطلع المقاسات متطابقة — وهذي إشارة الخطأ.
// ونتأكد كمان إن العربي يرسم فعلًا (Noto Naskh Arabic موجود).
async function probeFonts() {
  const measure = async (family, text) => {
    const svg = `<svg width="1200" height="120" xmlns="http://www.w3.org/2000/svg">
      <text x="10" y="80" font-family="${family}" font-size="56" font-weight="bold"
            fill="#ffffff">${escapeXml(text)}</text></svg>`;
    try {
      const { info } = await sharp(Buffer.from(svg))
        .trim({ threshold: 6 })
        .png()
        .toBuffer({ resolveWithObject: true });
      return `${info.width}x${info.height}`;
    } catch {
      return null;
    }
  };

  const sample = 'Welcome 123';
  const barlow = await measure('Barlow', sample);
  const noto = await measure('Noto Sans', sample);
  const arabic = await measure(FONT_STACK, 'مرحبا');

  return {
    ok: Boolean(barlow && noto && barlow !== noto && arabic),
    barlow,
    noto,
    arabic,
  };
}

module.exports = { composeWelcomeImage, probeFonts, CANVAS, CENTER, RADIUS, LAYOUT };
