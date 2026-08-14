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
    "default-src 'self'; img-src 'self' https://cdn.discordapp.com data:; " +
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
]);
app.use((req, res, next) => {
  if (req.admin?.mustChangePin && !FRESH_PIN_EXEMPT_PATHS.has(req.path)) {
    if (req.path.startsWith('/api/')) {
      return res.status(403).json({ error: 'لازم تغيّر رقمك السري أول', mustChangePin: true });
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

// تغيير الرقم السري — تحتاج تسجيل دخول بس، تشتغل حتى لو mustChangePin
app.get('/change-pin', auth.requireAuth, (req, res) => res.sendFile(page('change-pin.html')));

app.get('/', auth.requireAuth, (req, res) => res.sendFile(page('dashboard.html')));
app.get('/messages', auth.requireAuth, (req, res) => res.sendFile(page('messages.html')));
app.get('/moderation', auth.requireAuth, (req, res) => res.sendFile(page('moderation.html')));
app.get('/server', auth.requireAuth, (req, res) => res.sendFile(page('server.html')));
app.get('/templates', auth.requireAuth, (req, res) => res.sendFile(page('templates.html')));
app.get('/logs', auth.requireAuth, (req, res) => res.sendFile(page('logs.html')));
app.get('/admins', auth.requireAuth, auth.requireOwner, (req, res) => res.sendFile(page('admins.html')));

// ── 404 + معالج أخطاء عام — ما نكشف أي تفاصيل داخلية للمستخدم ────
app.use((req, res) => res.status(404).json({ error: 'غير موجود' }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('❌ خطأ غير متوقع:', err);
  res.status(500).json({ error: 'حدث خطأ، حاول مرة ثانية' });
});

const PORT = process.env.PORT || 3000;

(async () => {
  await migrate();
  await auth.ensureOwnerSeed();
  app.listen(PORT, () => {
    console.log(`✅ منصة الإدارة شغالة على المنفذ ${PORT}`);
    if (process.env.TEST_MODE_REDIRECT_USER_ID) {
      console.log(`🧪 وضع التجربة شغّال — كل الرسائل بتروح لعضو ID=${process.env.TEST_MODE_REDIRECT_USER_ID}`);
    }
  });
})().catch((err) => {
  console.error('❌ فشل تشغيل السيرفر:', err);
  process.exit(1);
});
