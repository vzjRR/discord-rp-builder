// "الفترة الحالية" (أي يوم/أسبوع/شهر/سنة نعتبره الآن الحيّ) مصدرها bot_state
// لا حساب مباشر من الوقت الحالي في كل مرة - هذا يخلي نقاط رسالة تُنسب دايمًا
// للفترة اللي rollover.js اعتمدها فعليًا كحالية، حتى في اللحظات القليلة
// بين تجاوز حد فترة حقيقي واكتشاف rollover.js له.

const { DateTime } = require('luxon');
const { db } = require('./db');
const {
  getWeekBounds,
  getWeekKey,
  getMonthBounds,
  getMonthKey,
  getDayBounds,
  getDayKey,
  getYearBounds,
  getYearKey,
  nowInZone,
} = require('./timezone');

const KEYS = {
  WEEK: { key: 'current_week_key', start: 'current_week_start' },
  MONTH: { key: 'current_month_key', start: 'current_month_start' },
  DAY: { key: 'current_day_key', start: 'current_day_start' },
  YEAR: { key: 'current_year_key', start: 'current_year_start' },
};

function getState(key) {
  const row = db.prepare('SELECT value FROM bot_state WHERE key = ?').get(key);
  return row ? row.value : undefined;
}

function setState(key, value) {
  const now = Date.now();
  db.prepare(
    `INSERT INTO bot_state (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
  ).run(key, value, now);
}

function boundsAndKeyFor(period, now, weekStartDay) {
  if (period === 'WEEK') {
    const bounds = getWeekBounds(now, weekStartDay);
    return { bounds, key: getWeekKey(bounds.start, weekStartDay) };
  }
  if (period === 'MONTH') {
    const bounds = getMonthBounds(now);
    return { bounds, key: getMonthKey(bounds.start) };
  }
  if (period === 'DAY') {
    const bounds = getDayBounds(now);
    return { bounds, key: getDayKey(bounds.start) };
  }
  const bounds = getYearBounds(now);
  return { bounds, key: getYearKey(bounds.start) };
}

/** الفترة الحالية المخزَّنة، أو تُهيَّأ أول مرة من الوقت الفعلي إن لم تكن موجودة. */
function initPeriodStateIfMissing(period, timezone, weekStartDay) {
  const stateKeys = KEYS[period];
  const existingKey = getState(stateKeys.key);
  const existingStart = getState(stateKeys.start);
  if (existingKey && existingStart) return { key: existingKey, startMs: Number(existingStart) };

  const { bounds, key } = boundsAndKeyFor(period, nowInZone(timezone), weekStartDay);
  setState(stateKeys.key, key);
  setState(stateKeys.start, String(bounds.start.toMillis()));
  return { key, startMs: bounds.start.toMillis() };
}

function getCurrentWeekKey(timezone, weekStartDay) {
  return initPeriodStateIfMissing('WEEK', timezone, weekStartDay).key;
}
function getCurrentWeekStart(timezone, weekStartDay) {
  return initPeriodStateIfMissing('WEEK', timezone, weekStartDay).startMs;
}
function getCurrentMonthKey(timezone) {
  return initPeriodStateIfMissing('MONTH', timezone).key;
}
function getCurrentMonthStart(timezone) {
  return initPeriodStateIfMissing('MONTH', timezone).startMs;
}
function getCurrentDayKey(timezone) {
  return initPeriodStateIfMissing('DAY', timezone).key;
}
function getCurrentDayStart(timezone) {
  return initPeriodStateIfMissing('DAY', timezone).startMs;
}
function getCurrentYearKey(timezone) {
  return initPeriodStateIfMissing('YEAR', timezone).key;
}
function getCurrentYearStart(timezone) {
  return initPeriodStateIfMissing('YEAR', timezone).startMs;
}

function setCurrentWeek(key, startMs) {
  setState(KEYS.WEEK.key, key);
  setState(KEYS.WEEK.start, String(startMs));
}
function setCurrentMonth(key, startMs) {
  setState(KEYS.MONTH.key, key);
  setState(KEYS.MONTH.start, String(startMs));
}
function setCurrentDay(key, startMs) {
  setState(KEYS.DAY.key, key);
  setState(KEYS.DAY.start, String(startMs));
}
function setCurrentYear(key, startMs) {
  setState(KEYS.YEAR.key, key);
  setState(KEYS.YEAR.start, String(startMs));
}

/** الفترات اللي تنتمي لها رسالة فعليًا حسب توقيت إرسالها - مستقلة عن "الحالية". */
function periodKeysFor(messageCreatedAt, timezone, weekStartDay) {
  const at = DateTime.fromMillis(messageCreatedAt).setZone(timezone);
  return {
    weekKey: getWeekKey(at, weekStartDay),
    monthKey: getMonthKey(at),
    dayKey: getDayKey(at),
    yearKey: getYearKey(at),
  };
}

module.exports = {
  KEYS,
  getState,
  setState,
  getCurrentWeekKey,
  getCurrentWeekStart,
  getCurrentMonthKey,
  getCurrentMonthStart,
  getCurrentDayKey,
  getCurrentDayStart,
  getCurrentYearKey,
  getCurrentYearStart,
  setCurrentWeek,
  setCurrentMonth,
  setCurrentDay,
  setCurrentYear,
  periodKeysFor,
};
