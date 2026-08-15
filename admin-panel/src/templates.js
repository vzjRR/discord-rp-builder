// نصوص الرسائل التي تُرسل إلى الأعضاء بشأن حساباتهم في المنصة.
// لكل نص قيمة افتراضية في الكود، ويمكن للمالك تعديلها من المنصة فتُحفظ
// كملف JSON على القرص الدائم (نفس أسلوب قوالب رسائل الترحيب).

const fs = require('fs');
const path = require('path');

const ONBOARDING_PATH = process.env.ONBOARDING_MESSAGE_PATH || '/data/onboarding-message.json';
const REVOCATION_PATH = process.env.REVOCATION_MESSAGE_PATH || '/data/revocation-message.json';

const DEFAULT_ONBOARDING = `🔐 **تم إنشاء حساب لك في منصة إدارة Enclave RP**

مرحبًا {name}، أصبح لديك وصول إلى منصة التحكم الخاصة بالسيرفر، ويمكنك من خلالها:
• إرسال الرسائل الخاصة والإعلانات إلى الأعضاء
• استخدام أدوات الإشراف (طرد، حظر، إسكات مؤقت، حذف رسائل)
• إدارة قنوات السيرفر ورتبه

**رابط الدخول:**
{platformUrl}

**رقمك السري المؤقت:**
{pin}

⚠️ يجب تغيير هذا الرقم فور أول تسجيل دخول قبل أن تتمكن من استخدام المنصة.

⚠️ **تنبيه مهم:** هذا الرقم يمنحك صلاحيات واسعة في التحكم بالسيرفر. **يُمنع مشاركته مع أي شخص** — فهو خاص بك وحدك، وإذا وصل إلى غيرك أمكنه التحكم بالسيرفر باسمك. وإن نسيته، يمكنك طلب رقم جديد من صفحة تسجيل الدخول.`;

const DEFAULT_REVOCATION = `🔒 **تم سحب صلاحيتك من منصة إدارة Enclave RP**

مرحبًا {name}، نُعلمك بأن حسابك في منصة التحكم قد أُلغي، ولم يعد رقمك السري صالحًا للدخول.

إن كنت ترى أن هذا حدث عن طريق الخطأ، أو رغبت في استعادة الوصول، فيمكنك تقديم طلب جديد من:
{platformUrl}/request-access

نشكرك على ما قدمته خلال فترة إشرافك.`;

function readOverride(file, key = 'message') {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return typeof parsed[key] === 'string' && parsed[key].trim() ? parsed[key] : null;
  } catch {
    return null;
  }
}

function writeOverride(file, message) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ message }, null, 2));
}

function clearOverride(file) {
  try {
    fs.unlinkSync(file);
  } catch {
    // لا يوجد تعديل محفوظ أصلًا
  }
}

const readOnboardingTemplate = () => readOverride(ONBOARDING_PATH) ?? DEFAULT_ONBOARDING;
const readRevocationTemplate = () => readOverride(REVOCATION_PATH) ?? DEFAULT_REVOCATION;

function fillTemplate(str, vars) {
  return String(str).replace(/\{(\w+)\}/g, (_, key) => (vars[key] !== undefined ? vars[key] : `{${key}}`));
}

module.exports = {
  ONBOARDING_PATH,
  REVOCATION_PATH,
  DEFAULT_ONBOARDING,
  DEFAULT_REVOCATION,
  readOnboardingTemplate,
  readRevocationTemplate,
  isOnboardingCustom: () => readOverride(ONBOARDING_PATH) !== null,
  isRevocationCustom: () => readOverride(REVOCATION_PATH) !== null,
  writeOnboarding: (m) => writeOverride(ONBOARDING_PATH, m),
  writeRevocation: (m) => writeOverride(REVOCATION_PATH, m),
  resetOnboarding: () => clearOverride(ONBOARDING_PATH),
  resetRevocation: () => clearOverride(REVOCATION_PATH),
  fillTemplate,
};
