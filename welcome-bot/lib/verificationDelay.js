// نظام تأجيل رول Citizen: عضو جديد يستلم رول انتظار مؤقت (⏳ Pending
// Verification) بدل Citizen مباشرة، وبعد مهلة (٥ دقايق لعضو جديد كليًا،
// ١٥ دقيقة لعضو غادر السيرفر من قبل وعاد) يُستبدل تلقائيًا برول Citizen
// مع رسالة خاصة بكل مرحلة بالعربية والإنجليزية. لا يقيّد القنوات هنا —
// ذاك مرة واحدة على مستوى صلاحيات ديسكورد نفسها (راجع: node build.js
// verification-gate بجذر المستودع)، لا شيء يتكرر هنا بكل انضمام.
//
// التفعيل/الإيقاف من منصة الإدارة (افتراضيًا مطفّي) — نفس أسلوب تعديل
// نصوص الترحيب بالضبط: ملف JSON صغير على القرص المشترك، نقرأه بكل حدث
// انضمام بدل الاعتماد على متغيّر بيئة يحتاج إعادة نشر لتغييره.
//
// الجدولة محفوظة بقاعدة SQLite صغيرة لا بـ setTimeout وحده: عملية Node لا
// تُبقي مؤقّتاتها بين مرات التشغيل، فلو أعيد تشغيل البوت أثناء فترة انتظار
// عضو (نشر جديد، تعطّل مؤقت) يضيع موعده للأبد بدون هذا. عند الإقلاع نعيد
// جدولة كل موعد لم يفت، وننفّذ فورًا كل موعد فات أثناء توقف البوت.

const fs = require('fs');
const path = require('path');
const cfg = require('../config/verificationDelay');
const welcomeCfg = require('../config/welcome');
const activityTracker = require('./activityTracker');

const SETTINGS_PATH = process.env.VERIFICATION_DELAY_SETTINGS_PATH || '/data/verification-delay-settings.json';
const DB_PATH = process.env.VERIFICATION_DELAY_DB_PATH
  || (process.env.EVENTS_DB_PATH
    ? path.join(path.dirname(process.env.EVENTS_DB_PATH), 'verification-delay.db')
    : '/data/verification-delay.db');

let db = null;

function initDb() {
  if (db) return db;
  try {
    const Database = require('better-sqlite3');
    fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    db.exec(`
      CREATE TABLE IF NOT EXISTS pending_verifications (
        user_id TEXT PRIMARY KEY,
        due_at TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
    `);
    return db;
  } catch (err) {
    console.error('⚠️  تعذّر فتح قاعدة التحقق المؤجل:', err.message);
    db = null;
    return null;
  }
}

function isEnabled() {
  try {
    const raw = JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8'));
    return raw.enabled === true;
  } catch {
    return false; // ملف غير موجود أو تالف = لم يُفعَّل من المنصة بعد
  }
}

function upsertPending(userId, dueAt) {
  const conn = initDb();
  if (!conn) return;
  conn
    .prepare(
      `INSERT INTO pending_verifications (user_id, due_at) VALUES (?, ?)
       ON CONFLICT(user_id) DO UPDATE SET due_at = excluded.due_at, created_at = datetime('now')`
    )
    .run(userId, dueAt.toISOString());
}

function removePending(userId) {
  const conn = initDb();
  if (!conn) return;
  conn.prepare('DELETE FROM pending_verifications WHERE user_id = ?').run(userId);
}

function allPending() {
  const conn = initDb();
  if (!conn) return [];
  return conn.prepare('SELECT user_id AS userId, due_at AS dueAt FROM pending_verifications').all();
}

async function dmSafely(user, content) {
  try {
    await user.send({ content });
  } catch (err) {
    console.log(`   ℹ️  ما قدرنا نرسل DM لـ ${user.tag} (${err.message})`);
  }
}

async function resolveVerification(guild, userId, timers) {
  removePending(userId);
  timers.delete(userId);

  const member = await guild.members.fetch(userId).catch(() => null);
  if (!member) return; // غادر السيرفر قبل انتهاء المهلة — لا شيء نفعله

  const pendingRole = guild.roles.cache.find((r) => r.name === cfg.pendingRoleName);
  const citizenRole = welcomeCfg.autoAssignRole
    ? guild.roles.cache.find((r) => r.name === welcomeCfg.autoAssignRole)
    : null;

  if (pendingRole && member.roles.cache.has(pendingRole.id)) {
    await member.roles.remove(pendingRole).catch((err) => console.warn(`⚠️  فشل إزالة رول الانتظار: ${err.message}`));
  }
  if (citizenRole) {
    await member.roles.add(citizenRole).catch((err) => console.warn(`⚠️  فشل إعطاء رول Citizen: ${err.message}`));
  } else if (welcomeCfg.autoAssignRole) {
    console.warn(`⚠️  رول "${welcomeCfg.autoAssignRole}" غير موجود — راجع config/welcome.js`);
  }

  await dmSafely(member.user, cfg.verifiedMessage(guild));
  console.log(`✅ تم التحقق من ${member.user.tag} بعد فترة الانتظار`);
}

function scheduleResolve(guild, userId, dueAt, timers) {
  const existing = timers.get(userId);
  if (existing) clearTimeout(existing);

  const ms = Math.max(0, new Date(dueAt).getTime() - Date.now());
  const timer = setTimeout(() => {
    resolveVerification(guild, userId, timers).catch((err) => console.error('⚠️  فشل إنهاء التحقق المؤجل:', err.message));
  }, ms);
  timers.set(userId, timer);
}

function register(client) {
  const guildId = process.env.GUILD_ID;
  const timers = new Map(); // userId -> مؤقّت setTimeout، نلغيه لو العضو غادر قبل الأوان

  client.on('guildMemberAdd', async (member) => {
    try {
      if (member.guild.id !== guildId) return;
      if (!isEnabled()) return; // مطفّاة — سلوك الانضمام العادي بـ welcome.js يكفي

      const pendingRole = member.guild.roles.cache.find((r) => r.name === cfg.pendingRoleName);
      if (!pendingRole) {
        console.warn(`⚠️  رول "${cfg.pendingRoleName}" غير موجود — تجاهلت التحقق المؤجل لهذا العضو`);
        return;
      }

      const isReturning = activityTracker.hasEverLeft(member.id);
      const delayMs = isReturning ? cfg.returningMemberDelayMs : cfg.newMemberDelayMs;
      const dueAt = new Date(Date.now() + delayMs);

      await member.roles.add(pendingRole).catch((err) => console.warn(`⚠️  فشل إعطاء رول الانتظار: ${err.message}`));
      upsertPending(member.id, dueAt);
      scheduleResolve(member.guild, member.id, dueAt, timers);

      await dmSafely(member.user, cfg.pendingMessage(member.guild));
      console.log(`⏳ ${member.user.tag} بانتظار التحقق (${isReturning ? 'عائد — ١٥ دقيقة' : 'جديد — ٥ دقايق'})`);
    } catch (err) {
      console.error('⚠️  خطأ في نظام التحقق المؤجل (انضمام):', err.message);
    }
  });

  // العضو غادر أثناء الانتظار: نلغي مؤقّته وصفّه — لا فائدة من منح رول
  // Citizen لعضو لم يعد بالسيرفر أصلًا.
  client.on('guildMemberRemove', (member) => {
    if (member.guild.id !== guildId) return;
    const timer = timers.get(member.id);
    if (timer) {
      clearTimeout(timer);
      timers.delete(member.id);
    }
    removePending(member.id);
  });

  client.once('ready', () => {
    const guild = client.guilds.cache.get(guildId);
    if (!guild) return;
    const rows = allPending();
    if (!rows.length) return;
    console.log(`⏳ استرجاع ${rows.length} تحقق مؤجل معلّق من قبل إعادة تشغيل البوت`);
    for (const row of rows) {
      scheduleResolve(guild, row.userId, row.dueAt, timers);
    }
  });
}

module.exports = { register, isEnabled };
