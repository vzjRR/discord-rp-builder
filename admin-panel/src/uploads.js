// استقبال المرفقات (صور، فيديو، ملفات) قبل تمريرها إلى ديسكورد.
//
// نحتفظ بالملف في الذاكرة لا على القرص: هو عابر — يُرسل إلى ديسكورد فورًا
// ثم لا حاجة إليه، وقرص الحاوية محدود وتُعاد تهيئته مع كل نشر.
//
// حدّ الحجم عندنا أوسع قليلًا من حدّ ديسكورد للسيرفرات غير المعزَّزة (١٠
// ميغابايت) كي يستفيد السيرفر المعزَّز من حدّه الأعلى؛ وإن رفض ديسكورد
// الملف أظهرنا سببه كما ورد منه بدل رسالة عامة.

const multer = require('multer');

const MAX_FILE_BYTES = 100 * 1024 * 1024; // ١٠٠ ميغابايت للملف الواحد
const MAX_FILES = 10; // نفس ما يسمح به ديسكورد في الرسالة الواحدة
// سقف الطلب كله. الحدّ لكل ملف وحده لا يكفي: عشرة ملفات بحدّها الأعلى
// تعني جيغابايت واحدًا في ذاكرة العملية دفعةً واحدة. والمنصة والبوت
// يعملان في حاوية واحدة، فنفاد ذاكرتها يُسقط الاثنين معًا — أي أن رفعة
// واحدة كبيرة كانت تكفي لإسقاط الترحيب بالأعضاء أيضًا.
const MAX_REQUEST_BYTES = 100 * 1024 * 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: MAX_FILE_BYTES,
    files: MAX_FILES,
    // حقول نصية غير الملفات — لا يحتاج أي منها أكثر من ذلك، وتركها بلا
    // حدّ يفتح طريقًا لاستنزاف الذاكرة دون رفع ملف أصلًا
    fields: 20,
    fieldSize: 64 * 1024,
  },
});

/**
 * يرفض الطلب الضخم قبل قراءة بايت واحد من جسمه.
 * Content-Length قابل للكذب، لكن الكذب هنا لا ينفع المهاجم: الحدّ لكل
 * ملف يبقى قائمًا داخل multer، وهذا الفحص يوفّر علينا استقبال ما نعرف
 * سلفًا أننا سنرفضه.
 */
function limitRequestSize(req, res, next) {
  const declared = Number(req.headers['content-length'] || 0);
  if (declared > MAX_REQUEST_BYTES) {
    return res.status(413).json({
      error: 'مجموع حجم المرفقات أكبر من الحدّ المسموح (١٠٠ ميغابايت للرسالة الواحدة)',
    });
  }
  next();
}

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
    // محارف اتجاه النص تقلب ما بعدها عند العرض، فيُظهر ملفٌ تنفيذي نفسه
    // صورةً في واجهة ديسكورد. ننزعها فيبقى الاسم كما هو حقيقةً.
    .replace(/[\u202a-\u202e\u2066-\u2069\u200e\u200f]/g, '')
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

module.exports = {
  upload,
  toDiscordFiles,
  uploadErrorHandler,
  limitRequestSize,
  MAX_FILE_BYTES,
  MAX_FILES,
  MAX_REQUEST_BYTES,
};
