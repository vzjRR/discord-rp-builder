// سجل النشاط — كل فعل يصير من المنصة ينسجل هنا (مين سواه، وش سوى، وامتى).
// لا تسجّل هنا أي محتوى حساس (توكنات، أرقام سرية) — فقط وصف الفعل.

const { db } = require('./db');

function logAction(actor, action, detail = null) {
  try {
    db.prepare(
      'INSERT INTO audit_log (actor_admin_id, actor_name, action, detail) VALUES (?, ?, ?, ?)'
    ).run(actor?.id ?? null, actor?.name ?? 'النظام', action, detail);
  } catch (err) {
    console.error('❌ فشل تسجيل سجل النشاط:', err.message);
  }
}

function listActions({ page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const rows = db
    .prepare('SELECT id, actor_name, action, detail, created_at FROM audit_log ORDER BY created_at DESC LIMIT ? OFFSET ?')
    .all(pageSize, offset);
  const { count } = db.prepare('SELECT COUNT(*) AS count FROM audit_log').get();
  return { rows, total: count, page, pageSize };
}

module.exports = { logAction, listActions };
