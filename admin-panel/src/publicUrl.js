// الرابط العام للمنصة — الذي يُرسل إلى الأعضاء في الرسائل الخاصة.
//
// لا يمكن اشتقاقه من الطلب: المنصة تعمل خلف Cloudflare Worker يعيد كتابة
// اسم المضيف إلى اسم الاستضافة، ثم يعيد بروكسي Railway كتابة ترويسة
// X-Forwarded-Host إلى اسم الاستضافة أيضًا. فأي رابط يُبنى من الطلب ينتهي
// إلى رابط الاستضافة الخام — وهو بالضبط ما يجب ألّا يصل إلى أي عضو.
//
// الترتيب: المتغيّر الصريح، ثم ترويسة يضبطها الـ Worker وحده، ثم القيمة
// الافتراضية المعروفة لهذا النشر (المستودع خاص بهذا المشروع أصلًا — إعدادات
// القنوات والرولات فيه محدّدة بالاسم كذلك)، ثم الطلب كملاذ أخير.
const DEFAULT_PUBLIC_URL = 'https://enclave-admin.tsh87.com';

function publicBaseUrl(req) {
  const configured = process.env.PUBLIC_BASE_URL;
  if (configured) return configured.replace(/\/+$/, '');

  const fromEdge = req?.headers?.['x-public-host'];
  if (fromEdge && /^[a-z0-9.-]+$/i.test(fromEdge)) return `https://${fromEdge}`;

  return DEFAULT_PUBLIC_URL;
}

module.exports = { publicBaseUrl, DEFAULT_PUBLIC_URL };
