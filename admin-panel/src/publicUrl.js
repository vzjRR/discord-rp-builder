// الرابط العام للمنصة — الذي يُرسل إلى الأعضاء في الرسائل الخاصة.
//
// لا يُشتق من الطلب: المنصة تصل الإنترنت عبر نفق Cloudflare صادر فقط
// (REQUIRE_CLOUDFLARE=false هو الوضع المعتمد)، فلا Worker يعيد كتابة اسم
// المضيف هنا كما في نشرة Railway القديمة. لو أُعيد استخدام Worker أمام
// النفق مستقبلاً فترويسة X-Public-Host أدناه ما زالت تُحترم كخيار وسيط.
//
// الترتيب: المتغيّر الصريح PUBLIC_BASE_URL، ثم ترويسة X-Public-Host إن
// وُجدت (توافقًا مع إعداد قديم أو مستقبلي بـ Worker)، ثم القيمة الافتراضية
// المعروفة لهذا النشر (المستودع خاص بهذا المشروع أصلًا — إعدادات القنوات
// والرولات فيه محدّدة بالاسم كذلك)، ثم الطلب كملاذ أخير.
const DEFAULT_PUBLIC_URL = 'https://panel.enclaverp.cc';

function publicBaseUrl(req) {
  const configured = process.env.PUBLIC_BASE_URL;
  if (configured) return configured.replace(/\/+$/, '');

  const fromEdge = req?.headers?.['x-public-host'];
  if (fromEdge && /^[a-z0-9.-]+$/i.test(fromEdge)) return `https://${fromEdge}`;

  return DEFAULT_PUBLIC_URL;
}

module.exports = { publicBaseUrl, DEFAULT_PUBLIC_URL };
