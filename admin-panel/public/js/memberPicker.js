// أداة بحث/اختيار عضو قابلة لإعادة الاستخدام — تبحث حسب الاسم أو اليوزرنيم
// وتطلع قائمة نتائج تضغط عليها بدل ما تكتب ID يدويًا. فيها خيار احتياطي
// "إدخال ID يدويًا" لحالات نادرة (مثل حظر عضو خارج السيرفر أصلًا).
//
// الاستخدام:
//   const picker = createMemberPicker({
//     mount: document.getElementById('someDiv'),
//     mode: 'members' | 'bans',   // bans تبحث بقائمة المحظورين بدل الأعضاء
//     placeholder: '...',
//     onSelect: (member) => {...},
//   });
//   picker.getId() -> ID المختار أو null

function mpEscapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function createMemberPicker({ mount, mode = 'members', placeholder = 'اكتب اسم العضو أو يوزرنيمه...', onSelect }) {
  mount.innerHTML = `
    <div class="member-picker">
      <input type="text" class="mp-input" placeholder="${placeholder}" autocomplete="off">
      <div class="mp-results"></div>
      <button type="button" class="mp-manual-toggle">أو أدخل ID يدويًا</button>
      <input type="text" class="mp-manual-input" placeholder="ID العضو" style="display:none">
    </div>`;

  const input = mount.querySelector('.mp-input');
  const results = mount.querySelector('.mp-results');
  const manualToggle = mount.querySelector('.mp-manual-toggle');
  const manualInput = mount.querySelector('.mp-manual-input');

  let debounceTimer = null;
  let selectedId = null;
  let manualMode = false;

  manualToggle.addEventListener('click', () => {
    manualMode = !manualMode;
    manualInput.style.display = manualMode ? 'block' : 'none';
    mount.querySelector('.mp-input').style.display = manualMode ? 'none' : 'block';
    results.classList.remove('show');
    manualToggle.textContent = manualMode ? 'أو دوّر بالاسم' : 'أو أدخل ID يدويًا';
  });

  input.addEventListener('input', () => {
    selectedId = null;
    clearTimeout(debounceTimer);
    const q = input.value.trim();
    if (!q) {
      results.innerHTML = '';
      results.classList.remove('show');
      return;
    }
    debounceTimer = setTimeout(async () => {
      try {
        const endpoint = mode === 'bans' ? '/api/discord/bans' : '/api/discord/members';
        const data = await api('GET', `${endpoint}?query=${encodeURIComponent(q)}`);
        renderResults(mode === 'bans' ? data.bans : data.members);
      } catch {
        results.innerHTML = '<div class="mp-empty">تعذّر البحث</div>';
        results.classList.add('show');
      }
    }, 250);
  });

  function renderResults(list) {
    if (!list.length) {
      results.innerHTML = '<div class="mp-empty">ما فيه نتائج</div>';
      results.classList.add('show');
      return;
    }
    results.innerHTML = list
      .map((m) => {
        const label = m.nickname ? `${m.nickname} (@${m.username})` : `@${m.username}`;
        return `<div class="mp-item" data-id="${m.id}" data-label="${mpEscapeHtml(label)}">
          <img src="${m.avatarUrl || ''}" alt="" onerror="this.style.visibility='hidden'">
          <span class="mp-name">${mpEscapeHtml(label)}</span>
          <span class="mp-id">${m.id}</span>
        </div>`;
      })
      .join('');
    results.classList.add('show');
    results.querySelectorAll('.mp-item').forEach((el) => {
      el.addEventListener('click', () => {
        selectedId = el.dataset.id;
        input.value = el.dataset.label;
        results.classList.remove('show');
        results.innerHTML = '';
        if (onSelect) onSelect({ id: selectedId, label: el.dataset.label });
      });
    });
  }

  document.addEventListener('click', (e) => {
    if (!mount.contains(e.target)) results.classList.remove('show');
  });

  return {
    getId: () => (manualMode ? manualInput.value.trim() || null : selectedId),
    clear: () => {
      input.value = '';
      manualInput.value = '';
      selectedId = null;
      results.innerHTML = '';
    },
    // يعبّي ID يدويًا من برّا (مثلًا من طلب دخول معلّق) بدل ما يدوّر بالاسم
    setManualId: (id) => {
      manualMode = true;
      manualInput.style.display = 'block';
      input.style.display = 'none';
      manualToggle.textContent = 'أو دوّر بالاسم';
      manualInput.value = id;
    },
  };
}
