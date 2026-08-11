// أدوات مشتركة لكل صفحات المنصة

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: body !== undefined ? { 'Content-Type': 'application/json' } : {},
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch { /* بدون جسم استجابة */ }
  if (!res.ok) throw new Error(data?.error || 'حدث خطأ غير متوقع');
  return data;
}

function showMsg(el, text, ok) {
  el.textContent = text;
  el.className = 'msg show ' + (ok ? 'ok' : 'err');
}

function setupLogout() {
  const btn = document.querySelector('.logout-btn');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    try { await api('POST', '/api/logout'); } catch { /* تجاهل */ }
    window.location.href = '/login';
  });
}

function highlightActiveNav() {
  const path = window.location.pathname;
  document.querySelectorAll('.nav-link').forEach((a) => {
    if (a.getAttribute('href') === path) a.classList.add('active');
  });
}

async function loadWhoAmI() {
  const el = document.querySelector('.nav-footer .who');
  if (!el) return;
  try {
    const { admin, testMode } = await api('GET', '/api/me');
    el.textContent = `مسجّل دخول: ${admin.name}${admin.isOwner ? ' (Owner)' : ''}`;
    if (!admin.isOwner) {
      document.querySelectorAll('a[href="/admins"]').forEach((a) => a.remove());
    }
    if (testMode) {
      const banner = document.createElement('div');
      banner.className = 'msg show err';
      banner.style.margin = '0 0 20px';
      banner.textContent = '🧪 وضع التجربة شغّال — كل الرسائل الخارجة من المنصة تتحول لعضو التجربة، مو للهدف الحقيقي.';
      const main = document.querySelector('main.main');
      if (main) main.insertBefore(banner, main.firstChild);
    }
  } catch {
    window.location.href = '/login';
  }
}

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}));
}

document.addEventListener('DOMContentLoaded', () => {
  setupLogout();
  highlightActiveNav();
  loadWhoAmI();
});
