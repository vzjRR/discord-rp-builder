// تجديد الفترة الأسبوعية/الشهرية - لا يعتمد على setTimeout مضبوط لـ"الحد
// القادم" (ذاك ينسى كل شيء لو البوت انطفى وقته). بدل هذا: bot_state يخزّن
// الفترة الحالية + بداية وقتها، وفحص دوري (setInterval) يقارنها بالفترة
// الحقيقية المحسوبة من الوقت الفعلي - فأي تجديد فات وقت انطفاء البوت
// يُكتشف ويُنفَّذ بأمان أول ما يرجع يشتغل، سواء بالفحص الفوري عند
// الإقلاع أو بالفحص الدوري بعده.
//
// لا يُرسل أي شيء لديسكورد عمدًا - كل نتيجة هنا تظهر فقط عبر المنصة، حيث
// يتحكم Owner بمين يشوفها (صلاحية points.view). نشر تلقائي بقناة عامة كان
// سيلتف حول هذا التحكم بالكامل.

const { DateTime } = require('luxon');
const { db } = require('./db');
const { getWeekKey, getMonthKey, nowInZone } = require('./timezone');
const { getCurrentWeekKey, getCurrentWeekStart, getCurrentMonthKey, getCurrentMonthStart } = require('./period');
const { getRankedUsers } = require('./leaderboard');
const { recordAudit } = require('./points');

const CHECK_INTERVAL_MS = 5 * 60 * 1000;
const GUARD_LIMIT = 1000; // سقف أمان - نشر حقيقي لن يفوّت هذا العدد من الفترات أبدًا

function finalizePeriod(periodType, finishedKey, bounds, nextKey, nextStartMs) {
  const scope = periodType === 'WEEK' ? 'weekly' : 'monthly';
  const entries = getRankedUsers(scope);
  const now = Date.now();
  const stateKeyName = periodType === 'WEEK' ? 'current_week_key' : 'current_month_key';
  const stateStartName = periodType === 'WEEK' ? 'current_week_start' : 'current_month_start';

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

    if (periodType === 'WEEK') {
      db.prepare('UPDATE users SET weekly_points = 0, weekly_images = 0, updated_at = ?').run(now);
    } else {
      db.prepare('UPDATE users SET monthly_points = 0, monthly_images = 0, updated_at = ?').run(now);
    }

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
    actionType: periodType === 'WEEK' ? 'WEEKLY_ROLLOVER' : 'MONTHLY_ROLLOVER',
    details: { finishedKey, nextKey, participants: entries.length },
  });

  return entries;
}

function catchUpPeriod(periodType, timezone, weekStartDay) {
  const now = nowInZone(timezone);

  let storedKey;
  let storedStartMs;
  let realKey;

  if (periodType === 'WEEK') {
    storedKey = getCurrentWeekKey(timezone, weekStartDay);
    storedStartMs = getCurrentWeekStart(timezone, weekStartDay);
    realKey = getWeekKey(now, weekStartDay);
  } else {
    storedKey = getCurrentMonthKey(timezone);
    storedStartMs = getCurrentMonthStart(timezone);
    realKey = getMonthKey(now);
  }

  let finished;
  let guard = 0;

  while (storedKey !== realKey && guard < GUARD_LIMIT) {
    guard += 1;
    const periodStart = DateTime.fromMillis(storedStartMs).setZone(timezone);
    const periodEnd = periodType === 'WEEK' ? periodStart.plus({ weeks: 1 }) : periodStart.plus({ months: 1 });
    const bounds = { start: periodStart, end: periodEnd };
    const nextKey = periodType === 'WEEK' ? getWeekKey(periodEnd, weekStartDay) : getMonthKey(periodEnd);
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

function checkWeeklyRollover(timezone, weekStartDay) {
  try {
    const finished = catchUpPeriod('WEEK', timezone, weekStartDay);
    if (finished) console.log(`✅ تجديد أسبوعي: ${finished.key} (${finished.entries.length} مشارك)`);
  } catch (err) {
    console.error('❌ فشل فحص التجديد الأسبوعي:', err.message);
    recordAudit({ actionType: 'ERROR', details: { scope: 'weekly_rollover', error: String(err) } });
  }
}

function checkMonthlyRollover(timezone) {
  try {
    const finished = catchUpPeriod('MONTH', timezone);
    if (finished) console.log(`✅ تجديد شهري: ${finished.key} (${finished.entries.length} مشارك)`);
  } catch (err) {
    console.error('❌ فشل فحص التجديد الشهري:', err.message);
    recordAudit({ actionType: 'ERROR', details: { scope: 'monthly_rollover', error: String(err) } });
  }
}

function startRolloverScheduler(timezone, weekStartDay) {
  const run = () => {
    checkWeeklyRollover(timezone, weekStartDay);
    checkMonthlyRollover(timezone);
  };
  run();
  setInterval(run, CHECK_INTERVAL_MS);
  console.log('⏰ فحص التجديد الدوري شغّال (كل ٥ دقايق)');
}

module.exports = { startRolloverScheduler, checkWeeklyRollover, checkMonthlyRollover };
