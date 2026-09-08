// تجديد الفترات (يومية/أسبوعية/شهرية/سنوية) - لا يعتمد على setTimeout مضبوط
// لـ"الحد القادم" (ذاك ينسى كل شيء لو البوت انطفى وقته). بدل هذا: bot_state
// يخزّن الفترة الحالية + بداية وقتها لكل نوع، وفحص دوري (setInterval) يقارنها
// بالفترة الحقيقية المحسوبة من الوقت الفعلي - فأي تجديد فات وقت انطفاء البوت
// يُكتشف ويُنفَّذ بأمان أول ما يرجع يشتغل، سواء بالفحص الفوري عند الإقلاع أو
// بالفحص الدوري بعده.
//
// لا يُرسل أي شيء لديسكورد عمدًا - كل نتيجة هنا تظهر فقط عبر المنصة، حيث
// يتحكم Owner بمين يشوفها (صلاحية points.view). نشر تلقائي بقناة عامة كان
// سيلتف حول هذا التحكم بالكامل.

const { DateTime } = require('luxon');
const { db } = require('./db');
const { getWeekKey, getMonthKey, getDayKey, getYearKey, nowInZone } = require('./timezone');
const {
  KEYS,
  getCurrentWeekKey,
  getCurrentWeekStart,
  getCurrentMonthKey,
  getCurrentMonthStart,
  getCurrentDayKey,
  getCurrentDayStart,
  getCurrentYearKey,
  getCurrentYearStart,
} = require('./period');
const { getRankedUsers } = require('./leaderboard');
const { recordAudit } = require('./points');

const CHECK_INTERVAL_MS = 5 * 60 * 1000;
const GUARD_LIMIT = 1000; // سقف أمان - نشر حقيقي لن يفوّت هذا العدد من الفترات أبدًا

// كل فترة بمكان واحد: عمود users المرتبط، وحدة الإضافة لحساب نهايتها،
// ودالة المفتاح (بعضها يحتاج weekStartDay وبعضها لا).
const PERIOD_CONFIG = {
  WEEK: {
    scope: 'weekly',
    column: 'weekly',
    addUnit: { weeks: 1 },
    getKey: (at, weekStartDay) => getWeekKey(at, weekStartDay),
    getCurrentKey: getCurrentWeekKey,
    getCurrentStart: getCurrentWeekStart,
    auditType: 'WEEKLY_ROLLOVER',
    label: 'أسبوعي',
  },
  MONTH: {
    scope: 'monthly',
    column: 'monthly',
    addUnit: { months: 1 },
    getKey: (at) => getMonthKey(at),
    getCurrentKey: getCurrentMonthKey,
    getCurrentStart: getCurrentMonthStart,
    auditType: 'MONTHLY_ROLLOVER',
    label: 'شهري',
  },
  DAY: {
    scope: 'daily',
    column: 'daily',
    addUnit: { days: 1 },
    getKey: (at) => getDayKey(at),
    getCurrentKey: getCurrentDayKey,
    getCurrentStart: getCurrentDayStart,
    auditType: 'DAILY_ROLLOVER',
    label: 'يومي',
  },
  YEAR: {
    scope: 'yearly',
    column: 'yearly',
    addUnit: { years: 1 },
    getKey: (at) => getYearKey(at),
    getCurrentKey: getCurrentYearKey,
    getCurrentStart: getCurrentYearStart,
    auditType: 'YEARLY_ROLLOVER',
    label: 'سنوي',
  },
};

function finalizePeriod(periodType, finishedKey, bounds, nextKey, nextStartMs) {
  const config = PERIOD_CONFIG[periodType];
  const entries = getRankedUsers(config.scope);
  const now = Date.now();
  const stateKeyName = KEYS[periodType].key;
  const stateStartName = KEYS[periodType].start;

  db.transaction(() => {
    for (const entry of entries) {
      db.prepare(
        `INSERT INTO period_history
           (period_type, period_key, user_id, username, display_name, points, images, rank_position,
            period_start, period_end, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(period_type, period_key, user_id) DO NOTHING`
      ).run(
        periodType,
        finishedKey,
        entry.userId,
        entry.username,
        entry.displayName,
        entry.points,
        entry.images,
        entry.rank,
        bounds.start.toMillis(),
        bounds.end.toMillis(),
        now
      );
    }

    db.prepare(`UPDATE users SET ${config.column}_points = 0, ${config.column}_images = 0, updated_at = ?`).run(now);

    db.prepare(
      `INSERT INTO bot_state (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
    ).run(stateKeyName, nextKey, now);
    db.prepare(
      `INSERT INTO bot_state (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
    ).run(stateStartName, String(nextStartMs), now);
  })();

  recordAudit({
    actionType: config.auditType,
    details: { finishedKey, nextKey, participants: entries.length },
  });

  return entries;
}

function catchUpPeriod(periodType, timezone, weekStartDay) {
  const config = PERIOD_CONFIG[periodType];
  const now = nowInZone(timezone);

  let storedKey = config.getCurrentKey(timezone, weekStartDay);
  let storedStartMs = config.getCurrentStart(timezone, weekStartDay);
  const realKey = config.getKey(now, weekStartDay);

  let finished;
  let guard = 0;

  while (storedKey !== realKey && guard < GUARD_LIMIT) {
    guard += 1;
    const periodStart = DateTime.fromMillis(storedStartMs).setZone(timezone);
    const periodEnd = periodStart.plus(config.addUnit);
    const bounds = { start: periodStart, end: periodEnd };
    const nextKey = config.getKey(periodEnd, weekStartDay);
    const nextStartMs = periodEnd.toMillis();

    const entries = finalizePeriod(periodType, storedKey, bounds, nextKey, nextStartMs);
    finished = { key: storedKey, bounds, entries };

    storedKey = nextKey;
    storedStartMs = nextStartMs;
  }

  if (guard >= GUARD_LIMIT) {
    console.error(`⚠️  rollover ${periodType} وصل سقف الأمان - راجع bot_state`);
    recordAudit({ actionType: 'ERROR', details: { scope: `${periodType}_rollover_guard`, guard } });
  }

  return finished;
}

function checkRollover(periodType, timezone, weekStartDay) {
  const config = PERIOD_CONFIG[periodType];
  try {
    const finished = catchUpPeriod(periodType, timezone, weekStartDay);
    if (finished) console.log(`✅ تجديد ${config.label}: ${finished.key} (${finished.entries.length} مشارك)`);
  } catch (err) {
    console.error(`❌ فشل فحص التجديد ${config.label}:`, err.message);
    recordAudit({ actionType: 'ERROR', details: { scope: `${periodType.toLowerCase()}_rollover`, error: String(err) } });
  }
}

function checkDailyRollover(timezone) {
  checkRollover('DAY', timezone);
}
function checkWeeklyRollover(timezone, weekStartDay) {
  checkRollover('WEEK', timezone, weekStartDay);
}
function checkMonthlyRollover(timezone) {
  checkRollover('MONTH', timezone);
}
function checkYearlyRollover(timezone) {
  checkRollover('YEAR', timezone);
}

function startRolloverScheduler(timezone, weekStartDay) {
  const run = () => {
    checkDailyRollover(timezone);
    checkWeeklyRollover(timezone, weekStartDay);
    checkMonthlyRollover(timezone);
    checkYearlyRollover(timezone);
  };
  run();
  setInterval(run, CHECK_INTERVAL_MS);
  console.log('⏰ فحص التجديد الدوري شغّال (كل ٥ دقايق) — يومي/أسبوعي/شهري/سنوي');
}

module.exports = {
  startRolloverScheduler,
  checkDailyRollover,
  checkWeeklyRollover,
  checkMonthlyRollover,
  checkYearlyRollover,
};
