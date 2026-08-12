// شريط أزرار تنسيق نصوص بصيغة ماركداون ديسكورد (عريض/مائل/تحته خط...) —
// يحط الأزرار فوق أي textarea ويطبّق التنسيق على النص المحدد فيها.

function attachFormatToolbar(textarea) {
  const bar = document.createElement('div');
  bar.className = 'fmt-toolbar';

  const buttons = [
    { label: 'B', title: 'عريض', before: '**', after: '**' },
    { label: 'I', title: 'مائل', before: '*', after: '*' },
    { label: 'U', title: 'تحته خط', before: '__', after: '__' },
    { label: 'S', title: 'يتوسطه خط', before: '~~', after: '~~' },
    { label: '</>', title: 'كود', before: '`', after: '`' },
    { label: '❝', title: 'اقتباس', before: '> ', after: '', line: true },
    { label: '•••', title: 'مخفي (spoiler)', before: '||', after: '||' },
  ];

  buttons.forEach((b) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'fmt-btn';
    btn.textContent = b.label;
    btn.title = b.title;
    btn.addEventListener('click', () => wrapSelection(textarea, b));
    bar.appendChild(btn);
  });

  textarea.parentNode.insertBefore(bar, textarea);
}

function wrapSelection(textarea, { before, after = '', line = false }) {
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const value = textarea.value;
  const selected = value.slice(start, end);

  let insertText;
  let newStart;
  let newEnd;

  if (line) {
    const lines = (selected || '').split('\n');
    insertText = lines.map((l) => before + l).join('\n');
    newStart = start;
    newEnd = start + insertText.length;
  } else {
    insertText = before + selected + after;
    newStart = start + before.length;
    newEnd = newStart + selected.length;
  }

  textarea.value = value.slice(0, start) + insertText + value.slice(end);
  textarea.focus();
  textarea.setSelectionRange(newStart, newEnd);
}
