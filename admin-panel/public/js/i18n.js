// ترجمة واجهة المنصة — العربية الفصحى والإنجليزية.
//
// الاختيار يُحفظ في المتصفح (localStorage) لا في الخادم: هو تفضيل عرض
// يخصّ الجهاز، ولا يستدعي جلسة ولا حسابًا، فيعمل قبل تسجيل الدخول أيضًا.
//
// كل نص في الصفحات موسوم بـ data-i18n (أو data-i18n-placeholder للحقول).
// الافتراضي العربية؛ وما لم يُترجم يبقى كما هو بدل أن يختفي.

const I18N = {
  ar: {
    dir: 'rtl', lang: 'ar', name: 'العربية',

    'nav.home': 'الرئيسية',
    'nav.messages': 'الرسائل والإعلانات',
    'nav.moderation': 'الإشراف',
    'nav.server': 'إدارة السيرفر',
    'nav.status': 'حالة السيرفر',
    'nav.templates': 'الرسائل الثابتة',
    'nav.logs': 'سجل النشاط',
    'nav.admins': 'إدارة الحسابات',
    'nav.logout': 'تسجيل الخروج',
    'nav.changePin': '🔑 تغيير الرقم السري',
    'nav.loggedIn': 'المسجّل الدخول',
    'nav.owner': 'مالك',

    'login.title': 'لوحة إدارة Enclave RP',
    'login.subtitle': 'أدخل رقمك السري الخاص',
    'login.submit': 'دخول',
    'login.forgot': 'نسيت رقمي السري',
    'login.noCode': 'ألا تملك رمزًا؟',
    'login.requestCode': 'اطلب رمز دخول',
    'login.install': '📱 كيف تثبّت المنصة على جهازك',
    'login.failed': 'تعذّر تسجيل الدخول',

    'lang.label': 'اللغة',
    'common.credit': 'تم التطوير عن طريق',
    'common.loading': 'جارٍ التحميل…',
  },

  en: {
    dir: 'ltr', lang: 'en', name: 'English',

    'nav.home': 'Home',
    'nav.messages': 'Messages & Announcements',
    'nav.moderation': 'Moderation',
    'nav.server': 'Server Management',
    'nav.status': 'Server Status',
    'nav.templates': 'Saved Messages',
    'nav.logs': 'Activity Log',
    'nav.admins': 'Accounts',
    'nav.logout': 'Sign out',
    'nav.changePin': '🔑 Change PIN',
    'nav.loggedIn': 'Signed in',
    'nav.owner': 'Owner',

    'login.title': 'Enclave RP Admin Panel',
    'login.subtitle': 'Enter your personal PIN',
    'login.submit': 'Sign in',
    'login.forgot': 'I forgot my PIN',
    'login.noCode': "Don't have a code?",
    'login.requestCode': 'Request access',
    'login.install': '📱 How to install this panel on your device',
    'login.failed': 'Sign-in failed',

    'lang.label': 'Language',
    'common.credit': 'Developed by',
    'common.loading': 'Loading…',
  },
};

const STORAGE_KEY = 'enclave_lang';

function currentLang() {
  const saved = localStorage.getItem(STORAGE_KEY);
  return I18N[saved] ? saved : 'ar';
}

function t(key) {
  const lang = currentLang();
  return I18N[lang][key] ?? I18N.ar[key] ?? key;
}

function applyTranslations(root = document) {
  const pack = I18N[currentLang()];

  document.documentElement.lang = pack.lang;
  document.documentElement.dir = pack.dir;

  root.querySelectorAll('[data-i18n]').forEach((el) => {
    const value = pack[el.dataset.i18n];
    if (value !== undefined) el.textContent = value;
  });

  root.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
    const value = pack[el.dataset.i18nPlaceholder];
    if (value !== undefined) el.placeholder = value;
  });
}

function setLang(lang) {
  if (!I18N[lang]) return;
  localStorage.setItem(STORAGE_KEY, lang);
  window.location.reload(); // أبسط من إعادة بناء كل صفحة يدويًا، وأضمن
}

/** يركّب مبدّل اللغة — يُستعمل في الصفحات العامة قبل تسجيل الدخول. */
function mountLangSwitcher(container) {
  if (!container) return;
  const lang = currentLang();
  container.className = 'lang-switch';
  container.innerHTML = Object.entries(I18N)
    .map(([code, pack]) =>
      `<button type="button" data-lang="${code}"${code === lang ? ' class="active"' : ''}>${pack.name}</button>`)
    .join('');
  container.querySelectorAll('[data-lang]').forEach((btn) => {
    btn.addEventListener('click', () => setLang(btn.dataset.lang));
  });
}

document.addEventListener('DOMContentLoaded', () => {
  applyTranslations();
  mountLangSwitcher(document.getElementById('langSwitch'));
});
