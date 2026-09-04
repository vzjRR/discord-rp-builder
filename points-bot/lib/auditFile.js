// نفس ملف السجل الدائم المشترك بين logs-bot والمنصة (راجع
// admin-panel/src/audit.js وlogs-bot/lib/logs.js) - عشان كل فعل، من
// ديسكورد أو النقاط أو المنصة، يطلع بمكان واحد على القرص.

const fs = require('fs');
const path = require('path');

const AUDIT_FILE_PATH = process.env.AUDIT_LOG_FILE_PATH || '/var/log/enclave/audit.log';

function appendAuditFile(entry) {
  try {
    fs.mkdirSync(path.dirname(AUDIT_FILE_PATH), { recursive: true });
    fs.appendFileSync(AUDIT_FILE_PATH, `${JSON.stringify(entry)}\n`);
  } catch (err) {
    console.error(`⚠️  فشل الكتابة بملف السجل الدائم (${AUDIT_FILE_PATH}):`, err.message);
  }
}

module.exports = { appendAuditFile, AUDIT_FILE_PATH };
