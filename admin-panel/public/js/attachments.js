// لوحة المرفقات في المحرّر — صور وفيديو وملفات، كما في ديسكورد:
// زر إرفاق، أو سحب وإفلات، أو لصق صورة من الحافظة، مع معاينة قبل الإرسال.

const MAX_FILES = 10;
const MAX_BYTES = 100 * 1024 * 1024;

function humanSize(bytes) {
  if (bytes < 1024) return `${bytes} بايت`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} كيلوبايت`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} ميغابايت`;
}

function kindOf(file) {
  if (file.type.startsWith('image/')) return 'image';
  if (file.type.startsWith('video/')) return 'video';
  if (file.type.startsWith('audio/')) return 'audio';
  return 'file';
}

const ICONS = { image: '🖼️', video: '🎬', audio: '🎵', file: '📎' };

/**
 * يركّب لوحة مرفقات أسفل حقل نصّي.
 * @returns {{files: () => File[], clear: () => void}}
 */
function attachUploader(textarea, { onChange } = {}) {
  let picked = [];

  const wrap = document.createElement('div');
  wrap.className = 'attach-wrap';
  wrap.innerHTML = `
    <div class="attach-bar">
      <button type="button" class="btn small ghost attach-btn">📎 إرفاق ملف</button>
      <span class="subtitle attach-hint">أو اسحب الملفات هنا، أو الصق صورة</span>
    </div>
    <input type="file" multiple hidden class="attach-input">
    <div class="attach-list"></div>`;
  textarea.parentNode.insertBefore(wrap, textarea.nextSibling);

  const input = wrap.querySelector('.attach-input');
  const list = wrap.querySelector('.attach-list');

  function render() {
    list.innerHTML = picked.map((f, i) => {
      const kind = kindOf(f);
      // عنوان كائن مؤقّت للمعاينة — نُبطله بعد تحميل العنصر تفاديًا لتسريب الذاكرة
      const preview = kind === 'image'
        ? `<img src="${URL.createObjectURL(f)}" alt="" onload="URL.revokeObjectURL(this.src)">`
        : kind === 'video'
          ? `<video src="${URL.createObjectURL(f)}" muted></video>`
          : `<span class="attach-icon">${ICONS[kind]}</span>`;
      return `
        <div class="attach-item" title="${escapeHtml(f.name)}">
          <div class="attach-thumb">${preview}</div>
          <div class="attach-meta">
            <div class="attach-name">${escapeHtml(f.name)}</div>
            <div class="subtitle">${escapeHtml(humanSize(f.size))}</div>
          </div>
          <button type="button" class="attach-remove" data-remove="${i}" aria-label="إزالة">✕</button>
        </div>`;
    }).join('');

    list.querySelectorAll('[data-remove]').forEach((btn) => {
      btn.addEventListener('click', () => {
        picked.splice(Number(btn.dataset.remove), 1);
        render();
      });
    });

    if (onChange) onChange(picked);
  }

  function add(files) {
    const incoming = [...files];
    for (const f of incoming) {
      if (picked.length >= MAX_FILES) {
        alert(`لا يمكن إرفاق أكثر من ${MAX_FILES} ملفات في رسالة واحدة.`);
        break;
      }
      if (f.size > MAX_BYTES) {
        alert(`الملف "${f.name}" أكبر من الحدّ المسموح (${humanSize(MAX_BYTES)}).`);
        continue;
      }
      picked.push(f);
    }
    render();
  }

  wrap.querySelector('.attach-btn').addEventListener('click', () => input.click());
  input.addEventListener('change', () => { add(input.files); input.value = ''; });

  // السحب والإفلات على حقل النص كله، كما في ديسكورد
  ['dragenter', 'dragover'].forEach((ev) =>
    textarea.addEventListener(ev, (e) => { e.preventDefault(); textarea.classList.add('drag-over'); }));
  ['dragleave', 'drop'].forEach((ev) =>
    textarea.addEventListener(ev, () => textarea.classList.remove('drag-over')));
  textarea.addEventListener('drop', (e) => {
    e.preventDefault();
    if (e.dataTransfer?.files?.length) add(e.dataTransfer.files);
  });

  // لصق صورة من الحافظة (لقطة شاشة مثلًا)
  textarea.addEventListener('paste', (e) => {
    const files = [...(e.clipboardData?.files || [])];
    if (files.length) { e.preventDefault(); add(files); }
  });

  return {
    files: () => picked,
    clear: () => { picked = []; render(); },
  };
}

/** يبني جسم الطلب: multipart عند وجود مرفقات، وإلا JSON عادي. */
async function postWithAttachments(url, fields, files) {
  if (!files.length) return api('POST', url, fields);

  const form = new FormData();
  Object.entries(fields).forEach(([k, v]) => {
    if (v !== undefined && v !== null) form.append(k, v);
  });
  files.forEach((f) => form.append('files', f, f.name));

  const res = await fetch(url, { method: 'POST', body: form });
  let data = null;
  try { data = await res.json(); } catch { /* بدون جسم استجابة */ }
  if (!res.ok) {
    if (data?.mustChangePin) {
      window.location.href = '/change-pin';
      return new Promise(() => {});
    }
    throw new Error(data?.error || 'تعذّر إرسال الرسالة');
  }
  return data;
}
