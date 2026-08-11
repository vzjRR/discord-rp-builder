// سجل النشاط — كل فعل يصير من المنصة ينسجل هنا (مين سواه، وش سوى، وامتى).
// لا تسجّل هنا أي محتوى حساس (توكنات، أرقام سرية) — فقط وصف الفعل.

const { pool } = require('./db');

async function logAction(actor, action, detail = null) {
  try {
    await pool.query(
      'INSERT INTO audit_log (actor_admin_id, actor_name, action, detail) VALUES ($1, $2, $3, $4)',
      [actor?.id ?? null, actor?.name ?? 'النظام', action, detail]
    );
  } catch (err) {
    console.error('❌ فشل تسجيل سجل النشاط:', err.message);
  }
}

async function listActions({ page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const { rows } = await pool.query(
    'SELECT id, actor_name, action, detail, created_at FROM audit_log ORDER BY created_at DESC LIMIT $1 OFFSET $2',
    [pageSize, offset]
  );
  const { rows: countRows } = await pool.query('SELECT COUNT(*)::int AS count FROM audit_log');
  return { rows, total: countRows[0].count, page, pageSize };
}

module.exports = { logAction, listActions };
