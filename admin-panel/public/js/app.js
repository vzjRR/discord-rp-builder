// أدوات مشتركة لكل صفحات المنصة

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: body !== undefined ? { 'Content-Type': 'application/json' } : {},
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch { /* بدون جسم استجابة */ }
  if (!res.ok) {
    if (data?.mustChangePin) {
      window.location.href = '/change-pin';
      return new Promise(() => {}); // نوقف التنفيذ — الصفحة بتنتقل على أي حال
    }
    throw new Error(data?.error || 'حدث خطأ غير متوقع');
  }
  return data;
}

// أي نص مصدره ديسكورد (اسم رول/قناة/سيرفر/عضو) لازم يتهرّب منه قبل ما
// يدخل innerHTML — هذي الأسماء يقدر يغيّرها أي شخص عنده صلاحية مناسبة
// بديسكورد نفسه، مو بس مستخدمين المنصة.
function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
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

  const changePinLink = document.createElement('a');
  changePinLink.href = '/change-pin';
  changePinLink.textContent = '🔑 تغيير الرقم السري';
  changePinLink.style.cssText = 'display:block;font-size:12px;color:var(--text-dim);margin-bottom:8px;text-align:center';
  btn.parentNode.insertBefore(changePinLink, btn);
}

function highlightActiveNav() {
  const path = window.location.pathname;
  document.querySelectorAll('.nav-link').forEach((a) => {
    if (a.getAttribute('href') === path) a.classList.add('active');
  });
}

// كل رابط في القائمة الجانبية وما يلزمه من صلاحية — رابط لا يملك صاحب
// الجلسة صلاحيته يُزال، فلا يرى في المنصة إلا ما يخصّه. الخادم يمنع
// المسارات نفسها، وهذا تيسير للواجهة لا حماية.
const NAV_PERMISSIONS = {
  '/messages': ['messages.dm', 'messages.announce'],
  '/server': [
    'server.manage',
    'moderation.kick', 'moderation.ban', 'moderation.timeout',
    'moderation.warn', 'moderation.purge', 'moderation.lock',
  ],
  '/status': ['status.view'],
  '/points': ['points.view', 'points.manage'],
  '/templates': ['templates.manage'],
  '/logs': ['logs.view'],
};

function applyNavPermissions(admin) {
  if (admin.isOwner) return;
  const held = admin.permissions || [];
  Object.entries(NAV_PERMISSIONS).forEach(([href, needed]) => {
    if (!needed.some((k) => held.includes(k))) {
      document.querySelectorAll(`.nav-link[href="${href}"]`).forEach((a) => a.remove());
    }
  });
}

async function loadWhoAmI() {
  const el = document.querySelector('.nav-footer .who');
  if (!el) return;
  try {
    const { admin, testMode } = await api('GET', '/api/me');
    window.currentAdmin = admin;
    el.textContent = `مسجّل الدخول: ${admin.name}${admin.isOwner ? ' (مالك)' : ''}`;
    if (!admin.isOwner) {
      document.querySelectorAll('a[href="/admins"]').forEach((a) => a.remove());
    }
    applyNavPermissions(admin);

    // حساب بلا معرّف ديسكورد مربوط: ما يقدر يستعمل زر "الدخول عبر
    // ديسكورد" بعد — نعرض له طريقة الربط مرة توضّح الخيار، لا تحجب شيئًا.
    if (!admin.discordUserId) {
      const banner = document.createElement('div');
      banner.className = 'msg show ok';
      banner.style.margin = '0 0 20px';
      banner.style.display = 'flex';
      banner.style.alignItems = 'center';
      banner.style.justifyContent = 'space-between';
      banner.style.gap = '12px';
      banner.innerHTML =
        '<span>حسابك يدخل بالرقم السري فقط حاليًا — اربطه بديسكورد لتدخل بزر واحد بلا رقم.</span>' +
        '<a href="/api/auth/discord/link/start" class="btn btn-discord small" style="margin:0">ربط الحساب</a>';
      const main = document.querySelector('main.main');
      if (main) main.insertBefore(banner, main.firstChild);
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

function showLinkResultBanner() {
  const params = new URLSearchParams(window.location.search);
  const linked = params.get('linked');
  const linkError = params.get('linkError');
  if (!linked && !linkError) return;

  const main = document.querySelector('main.main');
  if (main) {
    const banner = document.createElement('div');
    banner.className = 'msg show ' + (linked ? 'ok' : 'err');
    banner.style.margin = '0 0 20px';
    banner.textContent = linked
      ? '✅ تم ربط حساب ديسكورد بنجاح — تقدر تدخل بزر "الدخول عبر ديسكورد" الآن.'
      : 'هذا الحساب مربوط بحساب آخر على المنصة أصلًا.';
    main.insertBefore(banner, main.firstChild);
  }
  window.history.replaceState(null, '', window.location.pathname);
}

document.addEventListener('DOMContentLoaded', () => {
  setupLogout();
  highlightActiveNav();
  loadWhoAmI();
  showLinkResultBanner();
});
