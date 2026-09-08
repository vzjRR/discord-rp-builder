// مبدّل الوضع الفاتح/الليلي — يُحفظ بالمتصفح (localStorage) مثل تفضيل
// اللغة تمامًا: تفضيل عرض يخصّ الجهاز، يعمل حتى قبل تسجيل الدخول.
// تطبيق القيمة المحفوظة يحصل بسكربت مضمّن مبكرًا برأس كل صفحة (قبل هذا
// الملف) لتفادي وميض اللون الافتراضي قبل قراءة التفضيل.

const THEME_KEY = 'enclave_theme';

function currentTheme() {
  return localStorage.getItem(THEME_KEY) === 'dark' ? 'dark' : 'light';
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute('content', theme === 'dark' ? '#0a090d' : '#ffffff');
}

function updateToggleUI(btn) {
  const dark = currentTheme() === 'dark';
  btn.textContent = dark ? '☀️' : '🌙';
  const label = dark ? 'التبديل للوضع الفاتح' : 'التبديل للوضع الليلي';
  btn.setAttribute('aria-label', label);
  btn.title = label;
}

function setTheme(theme) {
  try { localStorage.setItem(THEME_KEY, theme); } catch { /* تجاهل */ }
  applyTheme(theme);
  document.querySelectorAll('[data-theme-toggle]').forEach(updateToggleUI);
}

function mountThemeToggle(container) {
  if (!container || container.querySelector('[data-theme-toggle]')) return;
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'theme-toggle';
  btn.setAttribute('data-theme-toggle', '');
  btn.addEventListener('click', () => setTheme(currentTheme() === 'dark' ? 'light' : 'dark'));
  container.appendChild(btn);
  updateToggleUI(btn);
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-theme-toggle-mount]').forEach(mountThemeToggle);
});
