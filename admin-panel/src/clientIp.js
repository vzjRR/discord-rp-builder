// التحقق إن الطلب جاي فعلًا عبر Cloudflare — يخدم غرضين:
//
//   1. حد محاولات الدخول: الدومين الخاص يمر عبر Cloudflare، فreq.ip يطلع IP
//      إيدج Cloudflare مو الزائر، ويصير كل الزوّار يشتركون بنفس العدّاد.
//      Cloudflare يضيف CF-Connecting-IP فيه IP الزائر الحقيقي.
//   2. إخفاء الاستضافة: رابط المنصة الخام يظل شغّال لو اكتشفه أحد، فنقدر
//      نرفض أي طلب ما جا عبر Cloudflare (REQUIRE_CLOUDFLARE بـ server.js).
//
// ⚠️ ليش ما نعتمد على IP المتصل وحده:
// كنا نتحقق إن req.ip ضمن نطاقات Cloudflare المعلنة، لكن هذا قابل للتزوير.
// إيدج Railway *يضيف* للـ X-Forwarded-For بدل ما يستبدله، ومع trust proxy=1
// إكسبرس ياخذ القيمة قبل الأخيرة — فمهاجم يطلب من رابط Railway الخام ويحط
// `X-Forwarded-For: <ip كلاودفلير>` تصير هي req.ip عندنا. مؤكّد بالاختبار.
//
// الطريقة المحكمة: سر مشترك يضيفه Cloudflare بهيدر عبر Transform Rule.
// اللي يطلب من رابط Railway مباشرة ما يعرف السر، فما يقدر ينتحل.

const SECRET_HEADER = 'x-edge-secret';

function edgeSecret() {
  return process.env.CLOUDFLARE_SECRET || null;
}

// مقارنة بزمن ثابت — مقارنة النصوص العادية تتسرّب منها معلومات عن السر
function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * هل الطلب جاي عبر Cloudflare فعلًا؟
 * ترجع false دايمًا لو CLOUDFLARE_SECRET مو مضبوط — ما نخمّن.
 */
function isFromCloudflare(req) {
  const secret = edgeSecret();
  if (!secret) return false;
  return safeEqual(req.headers[SECRET_HEADER] || '', secret);
}

/**
 * IP الزائر الحقيقي. نصدّق CF-Connecting-IP فقط لو ثبت إن الطلب من
 * Cloudflare عبر السر المشترك — وإلا نرجع للـ IP اللي شافه إكسبرس.
 */
function clientIp(req) {
  const cfIp = req.headers['cf-connecting-ip'];
  if (cfIp && isFromCloudflare(req)) return cfIp;
  return req.ip;
}

module.exports = { clientIp, isFromCloudflare, SECRET_HEADER };
