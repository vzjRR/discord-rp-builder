// سجل النشاط — كل فعل يصير من المنصة ينسجل هنا (مين سواه، وش سوى، وامتى).
// لا تسجّل هنا أي محتوى حساس (توكنات، أرقام سرية) — فقط وصف الفعل.

const fs = require('fs');
const path = require('path');
const { db } = require('./db');

// نفس الملف الدائم اللي يكتب فيه logs-bot (راجع logs-bot/lib/logs.js) — عشان
// كل شيء يتغيّر أو يُضاف أو يُحذف، بديسكورد أو باللوحة، يطلع بمكان واحد على
// القرص بدل ما يتوزّع بين قاعدة بيانات المنصة وملف البوت.
const AUDIT_FILE_PATH = process.env.AUDIT_LOG_FILE_PATH || '/var/log/enclave/audit.log';

function appendAuditFile(entry) {
  try {
    fs.mkdirSync(path.dirname(AUDIT_FILE_PATH), { recursive: true });
    fs.appendFileSync(AUDIT_FILE_PATH, `${JSON.stringify(entry)}\n`);
  } catch (err) {
    console.error(`❌ فشل الكتابة بملف السجل الدائم (${AUDIT_FILE_PATH}): ${err.message}`);
  }
}

function logAction(actor, action, detail = null) {
  try {
    db.prepare(
      'INSERT INTO audit_log (actor_admin_id, actor_name, action, detail) VALUES (?, ?, ?, ?)'
    ).run(actor?.id ?? null, actor?.name ?? 'النظام', action, detail);
  } catch (err) {
    console.error('❌ فشل تسجيل سجل النشاط:', err.message);
  }

  appendAuditFile({
    ts: new Date().toISOString(),
    type: 'panel',
    actorId: actor?.id ?? null,
    actorName: actor?.name ?? 'النظام',
    action,
    detail,
  });
}

function listActions({ page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const rows = db
    .prepare('SELECT id, actor_name, action, detail, created_at FROM audit_log ORDER BY created_at DESC LIMIT ? OFFSET ?')
    .all(pageSize, offset);
  const { count } = db.prepare('SELECT COUNT(*) AS count FROM audit_log').get();
  return { rows, total: count, page, pageSize };
}

// يمسح السجل بالكامل ثم يسجّل عملية المسح نفسها فورًا — سجل يُمحى دون أن
// يترك أثرًا لمن محاه يفقد قيمته كسجل.
function clearActions(actor) {
  const { count } = db.prepare('SELECT COUNT(*) AS count FROM audit_log').get();
  db.prepare('DELETE FROM audit_log').run();
  logAction(actor, 'logs.clear', `مسح سجل النشاط (${count} سجلًا)`);
  return count;
}

module.exports = { logAction, listActions, clearActions, appendAuditFile };
