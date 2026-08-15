// استقبال المرفقات (صور، فيديو، ملفات) قبل تمريرها إلى ديسكورد.
//
// نحتفظ بالملف في الذاكرة لا على القرص: هو عابر — يُرسل إلى ديسكورد فورًا
// ثم لا حاجة إليه، وقرص الحاوية محدود وتُعاد تهيئته مع كل نشر.
//
// حدّ الحجم عندنا أوسع قليلًا من حدّ ديسكورد للسيرفرات غير المعزَّزة (١٠
// ميغابايت) كي يستفيد السيرفر المعزَّز من حدّه الأعلى؛ وإن رفض ديسكورد
// الملف أظهرنا سببه كما ورد منه بدل رسالة عامة.

const multer = require('multer');

const MAX_FILE_BYTES = 100 * 1024 * 1024; // ١٠٠ ميغابايت
const MAX_FILES = 10; // نفس ما يسمح به ديسكورد في الرسالة الواحدة

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_BYTES, files: MAX_FILES },
});

/** يحوّل ملفات multer إلى الشكل الذي يفهمه discord.requestMultipart. */
function toDiscordFiles(files = []) {
  return files.map((f) => ({
    filename: sanitizeName(f.originalname),
    contentType: f.mimetype || 'application/octet-stream',
    buffer: f.buffer,
  }));
}

// اسم الملف يظهر للجميع في ديسكورد ويأتي من جهاز المُرسِل، فننزع منه
// المسارات ومحارف التحكّم ونقصّه — لا نمرّر ما لم نفحصه.
function sanitizeName(name) {
  const base = String(name || 'file')
    .split(/[\\/]/)
    .pop()
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .trim();
  return (base || 'file').slice(0, 120);
}

/** يترجم أخطاء multer إلى رسائل مفهومة بدل خطأ ٥٠٠ عام. */
function uploadErrorHandler(err, req, res, next) {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: 'حجم الملف أكبر من الحدّ المسموح (١٠٠ ميغابايت)' });
    }
    if (err.code === 'LIMIT_FILE_COUNT') {
      return res.status(400).json({ error: `لا يمكن إرفاق أكثر من ${MAX_FILES} ملفات في رسالة واحدة` });
    }
    return res.status(400).json({ error: 'تعذّر استقبال المرفقات' });
  }
  return next(err);
}

module.exports = { upload, toDiscordFiles, uploadErrorHandler, MAX_FILE_BYTES, MAX_FILES };
