// منصة تحكم Enclave RP — Express بسيط، بدون فريمورك واجهة (HTML/CSS/JS عادي)
// عشان يبقى الكود سهل الفهم والصيانة زي باقي أدوات هذا المستودع.
//
// التشغيل: npm install ثم npm start
// يحتاج: DISCORD_TOKEN, GUILD_ID, SESSION_SECRET
// (شوف .env.example لكل التفاصيل)

require('dotenv').config();
const path = require('path');
const express = require('express');
const cookieParser = require('cookie-parser');

const { migrate } = require('./src/db');
const auth = require('./src/auth');
const { isFromCloudflare } = require('./src/clientIp');
const permissions = require('./src/permissions');

const REQUIRED_ENV = ['DISCORD_TOKEN', 'GUILD_ID', 'SESSION_SECRET'];
const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`❌ متغيرات بيئة ناقصة: ${missing.join(', ')} — راجع .env.example`);
  process.exit(1);
}

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1); // خلف بروكسي Railway — عشان req.ip وreq.secure صحيحة

app.use(express.json({ limit: '256kb' }));
app.use(cookieParser(process.env.SESSION_SECRET));

// المنصة تُنشر خلف Cloudflare على الدومين الرسمي، لكن رابط الاستضافة الخام
// يظل يشتغل لو اكتشفه أحد — وهذا يكشف مكان الاستضافة ويلتف حول أي حماية
// نضيفها على مستوى Cloudflare. لما REQUIRE_CLOUDFLARE=true نرفض أي طلب ما
// جا عبر Cloudflare (يُتحقق منه بالسر المشترك — شوف src/clientIp.js).
//
// افتراضيًا مطفّي: لو انقلب شي بإعداد Cloudflare والخيار مفعّل، بتنقفل
// المنصة عن الجميع — ففعّله بعد ما تتأكد إن الدومين شغّال عبر Cloudflare.
// نرد 404 فاضية بدون أي تفاصيل — ما نأكد ولا ننفي وجود شي على هذا العنوان.
// نقبل true/1/yes/on بأي حالة أحرف ومع مسافات زايدة — لأن مقارنة نصية
// صارمة تعني إن خطأ إملائي بسيط بلوحة Railway يعطّل حماية بصمت وإنت
// فاكرها شغّالة، وهذا أسوأ من قبول عدة صيغ.
const REQUIRE_CF = ['true', '1', 'yes', 'on'].includes(
  String(process.env.REQUIRE_CLOUDFLARE || '').trim().toLowerCase()
);

if (REQUIRE_CF) {
  if (!process.env.CLOUDFLARE_SECRET) {
    console.error(
      '❌ REQUIRE_CLOUDFLARE=true بدون CLOUDFLARE_SECRET — كذا بترفض كل الطلبات ' +
        'وتنقفل المنصة عن الجميع. اضبط CLOUDFLARE_SECRET أو عطّل REQUIRE_CLOUDFLARE.'
    );
    process.exit(1);
  }
  app.use((req, res, next) => {
    if (isFromCloudflare(req)) return next();
    res.status(404).type('text/plain').send('Not Found');
  });
}

// أمان أساسي على الهيدرز — بدون مكتبة خارجية إضافية
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'same-origin');
  // كل الصفحات ملفات ثابتة بدون سكربتات خارجية — الاستثناء الوحيد صور
  // ديسكورد (أفاتار/أيقونة السيرفر). طبقة حماية إضافية لو صار XSS يومًا،
  // تمنع تحميل/تنفيذ أي شيء من دومين غريب.
  res.setHeader(
    'Content-Security-Policy',
    // blob: لازمة لمعاينة المرفقات قبل رفعها (عناوين كائنات محلية في
    // المتصفح، لا تُحمَّل من أي خادم)
    "default-src 'self'; img-src 'self' https://cdn.discordapp.com data: blob:; " +
      "media-src 'self' blob:; " +
      "script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; " +
      "connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none';"
  );
  next();
});

// يحل الجلسة الحالية (لو موجودة) ويحطها بـ req.admin — يستخدمها requireAuth
app.use(async (req, res, next) => {
  try {
    const token = req.cookies?.[auth.SESSION_COOKIE];
    req.admin = token ? await auth.resolveSession(token) : null;
  } catch (err) {
    console.error('فشل التحقق من الجلسة:', err.message);
    req.admin = null;
  }
  next();
});

app.get('/health', (req, res) => res.send('ok'));

// ── ملفات عامة (تصميم/أيقونات/PWA) — ما فيها بيانات حساسة ─────────
app.use('/css', express.static(path.join(__dirname, 'public/css')));
app.use('/js', express.static(path.join(__dirname, 'public/js')));
app.use('/icons', express.static(path.join(__dirname, 'public/icons')));
app.get('/manifest.webmanifest', (req, res) =>
  res.sendFile(path.join(__dirname, 'public/manifest.webmanifest'))
);
app.get('/sw.js', (req, res) => res.sendFile(path.join(__dirname, 'public/sw.js')));

// لو الحساب لازم يغيّر رقمه السري (أول دخول بحساب جديد) — نقفل كل شيء
// غيره لين يغيّره. المسارات المستثناة بس: تغيير الرقم نفسه، الخروج،
// معرفة هويته (يحتاجها change-pin.html)، وطلب رمز جديد (عام أصلًا).
const FRESH_PIN_EXEMPT_PATHS = new Set([
  '/api/me',
  '/api/me/pin',
  '/api/logout',
  '/change-pin',
  '/request-access',
  '/api/access-requests',
  '/forgot-pin',
  '/api/pin-reset/request',
  '/api/pin-reset/verify',
]);
app.use((req, res, next) => {
  if (req.admin?.mustChangePin && !FRESH_PIN_EXEMPT_PATHS.has(req.path)) {
    if (req.path.startsWith('/api/')) {
      return res.status(403).json({ error: 'عليك تغيير رقمك السري أولًا', mustChangePin: true });
    }
    return res.redirect('/change-pin');
  }
  next();
});

// ── API ─────────────────────────────────────────────────────────
app.use(require('./src/routes/auth'));
app.use(require('./src/routes/discordMeta'));
app.use(require('./src/routes/messages'));
app.use(require('./src/routes/moderation'));
app.use(require('./src/routes/logs'));
app.use(require('./src/routes/admins'));
app.use(require('./src/routes/server'));
app.use(require('./src/routes/templates'));
app.use(require('./src/routes/access'));
app.use(require('./src/routes/preview'));
app.use(require('./src/routes/pinReset'));
app.use(require('./src/routes/status'));
app.use(require('./src/routes/backup'));

// أخطاء رفع المرفقات لها رسائل خاصة — قبل معالج الأخطاء العام
app.use(require('./src/uploads').uploadErrorHandler);

// ── صفحات الواجهة (كل وحدة محمية بحسب الحاجة) ────────────────────
const page = (name) => path.join(__dirname, 'public', name);

app.get('/login', (req, res) => {
  if (req.admin) return res.redirect('/');
  res.sendFile(page('login.html'));
});

// صفحة إرشادات التثبيت — عامة، ما فيها بيانات حساسة
app.get('/install', (req, res) => res.sendFile(page('install.html')));

// طلب رمز دخول جديد — عامة (قبل تسجيل الدخول أصلًا)
app.get('/request-access', (req, res) => {
  if (req.admin && !req.admin.mustChangePin) return res.redirect('/');
  res.sendFile(page('request-access.html'));
});

// استرجاع رقم سري منسي — عامة بالضرورة: من نسي رقمه لا يستطيع الدخول
app.get('/forgot-pin', (req, res) => {
  if (req.admin && !req.admin.mustChangePin) return res.redirect('/');
  res.sendFile(page('forgot-pin.html'));
});

// تغيير الرقم السري — تحتاج تسجيل دخول بس، تشتغل حتى لو mustChangePin
app.get('/change-pin', auth.requireAuth, (req, res) => res.sendFile(page('change-pin.html')));

// الصفحات محجوبة بحسب صلاحيات الحساب — والمسارات خلفها محجوبة أيضًا،
// فإخفاء الصفحة تيسير للمستخدم لا اعتماد أمني عليه.
const anyOf = permissions.requireAnyPermission;

app.get('/', auth.requireAuth, (req, res) => res.sendFile(page('dashboard.html')));
app.get('/messages', auth.requireAuth, anyOf(['messages.dm', 'messages.announce']), (req, res) =>
  res.sendFile(page('messages.html'))
);
app.get(
  '/moderation',
  auth.requireAuth,
  anyOf(['moderation.kick', 'moderation.ban', 'moderation.timeout', 'moderation.warn', 'moderation.purge', 'moderation.lock']),
  (req, res) => res.sendFile(page('moderation.html'))
);
app.get('/server', auth.requireAuth, anyOf(['server.manage']), (req, res) => res.sendFile(page('server.html')));
app.get('/status', auth.requireAuth, anyOf(['status.view']), (req, res) => res.sendFile(page('status.html')));
app.get('/templates', auth.requireAuth, anyOf(['templates.manage']), (req, res) => res.sendFile(page('templates.html')));
app.get('/logs', auth.requireAuth, anyOf(['logs.view']), (req, res) => res.sendFile(page('logs.html')));
app.get('/admins', auth.requireAuth, auth.requireOwner, (req, res) => res.sendFile(page('admins.html')));

// ── 404 + معالج أخطاء عام — ما نكشف أي تفاصيل داخلية للمستخدم ────
app.use((req, res) => res.status(404).json({ error: 'غير موجود' }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // جسم طلب مشوّه خطأ في الطلب لا في الخادم؛ نرد ٤٠٠ لا ٥٠٠ وما نسجّله
  // كخطأ غير متوقع، وإلا امتلأ السجل بضجيج يخفي الأعطال الحقيقية.
  if (err?.type === 'entity.parse.failed' || err?.status === 400) {
    return res.status(400).json({ error: 'صيغة الطلب غير صالحة' });
  }
  console.error('❌ خطأ غير متوقع:', err);
  res.status(500).json({ error: 'وقع خطأ، أعد المحاولة' });
});

const PORT = process.env.PORT || 3000;

(async () => {
  await migrate();
  await auth.ensureOwnerSeed();
  await auth.applyOwnerPinReset();
  app.listen(PORT, () => {
    console.log(`✅ منصة الإدارة شغالة على المنفذ ${PORT}`);
    if (process.env.TEST_MODE_REDIRECT_USER_ID) {
      console.log(`🧪 وضع التجربة شغّال — كل الرسائل بتروح لعضو ID=${process.env.TEST_MODE_REDIRECT_USER_ID}`);
    }
    // نطبع حالة الإعدادات الحسّاسة عند الإقلاع — بدونها ما تعرف إن متغيّر
    // ما انضبط إلا لما تكتشف إن الحماية مو شغّالة أصلًا.
    console.log(
      `🔒 قفل المصدر: ${REQUIRE_CF ? 'مفعّل' : 'مطفّي'} | ` +
        `سر Cloudflare: ${process.env.CLOUDFLARE_SECRET ? 'مضبوط' : 'غير مضبوط'} | ` +
        `الرابط العام: ${process.env.PUBLIC_BASE_URL || '(من الطلب)'}`
    );
  });
})().catch((err) => {
  console.error('❌ فشل تشغيل السيرفر:', err);
  process.exit(1);
});
