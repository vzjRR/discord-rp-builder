#!/usr/bin/env node
// استعادة نسخة احتياطية على مضيف جديد.
//
//   node scripts/restore-backup.js enclave-backup-....json [مجلد الوجهة]
//
// الوجهة الافتراضية /data — نفس ما تقرأه المنصة والبوت.
//
// لا نكتب فوق ملف موجود إلا بـ --force: الاستعادة على مضيف فيه بيانات
// عاملة تمحوها بلا رجعة، وخطأ مطبعي في المسار لا ينبغي أن يكلّف ذلك.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const args = process.argv.slice(2).filter((a) => a !== '--force');
const force = process.argv.includes('--force');
const [bundlePath, destDir = '/data'] = args;

if (!bundlePath) {
  console.error('الاستعمال: node scripts/restore-backup.js <ملف-النسخة.json> [مجلد الوجهة] [--force]');
  process.exit(1);
}

let bundle;
try {
  bundle = JSON.parse(fs.readFileSync(bundlePath, 'utf8'));
} catch (err) {
  console.error(`❌ تعذّرت قراءة ملف النسخة: ${err.message}`);
  process.exit(1);
}

if (bundle.version !== 1) {
  console.error(`❌ إصدار نسخة غير معروف: ${bundle.version}`);
  process.exit(1);
}

console.log(`📦 نسخة بتاريخ ${bundle.createdAt}`);
if (bundle.counts && Object.keys(bundle.counts).length) {
  console.log(`   محتواها: ${Object.entries(bundle.counts).map(([k, v]) => `${k}=${v}`).join('، ')}`);
}
(bundle.warnings || []).forEach((w) => console.log(`   ⚠️  ${w}`));

fs.mkdirSync(destDir, { recursive: true });

let written = 0;
let skipped = 0;

for (const [name, b64] of Object.entries(bundle.files)) {
  const target = path.join(destDir, name);
  const data = Buffer.from(b64, 'base64');

  // نتحقق من البصمة قبل الكتابة: نسخة تشوّهت في النقل أسوأ من لا نسخة،
  // لأنها تبدو سليمة حتى تُستعمل.
  const expected = bundle.checksums?.[name];
  if (expected) {
    const actual = crypto.createHash('sha256').update(data).digest('hex');
    if (actual !== expected) {
      console.error(`❌ ${name}: البصمة لا تطابق — الملف تالف، أُوقفت الاستعادة`);
      process.exit(1);
    }
  }

  if (fs.existsSync(target) && !force) {
    console.log(`   ⏭️  ${name} موجود مسبقًا — تُرك (استعمل --force للكتابة فوقه)`);
    skipped++;
    continue;
  }

  fs.writeFileSync(target, data);
  console.log(`   ✅ ${name} (${data.length.toLocaleString('ar')} بايت)`);
  written++;
}

// ملفات WAL و SHM القديمة تخصّ قاعدة أخرى؛ بقاؤها مع قاعدة مستعادة يفسدها
for (const name of Object.keys(bundle.files)) {
  if (!name.endsWith('.db')) continue;
  for (const suffix of ['-wal', '-shm']) {
    const stale = path.join(destDir, name + suffix);
    if (fs.existsSync(stale)) {
      fs.rmSync(stale, { force: true });
      console.log(`   🧹 حُذف ${name}${suffix} المتبقّي من قاعدة سابقة`);
    }
  }
}

console.log(`\nاكتملت الاستعادة إلى ${destDir} — كُتب ${written}، وتُرك ${skipped}.`);
if (skipped && !force) {
  console.log('لكتابة الملفات المتروكة فوق الموجود: أعد التنفيذ مع --force');
}
