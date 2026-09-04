// "الفترة الحالية" (أي أسبوع/شهر نعتبره الآن الحيّ) مصدرها bot_state لا
// حساب مباشر من الوقت الحالي في كل مرة - هذا يخلي نقاط رسالة تُنسب دايمًا
// للفترة اللي rollover.js اعتمدها فعليًا كحالية، حتى في اللحظات القليلة
// بين تجاوز حد فترة حقيقي واكتشاف rollover.js له.

const { db } = require('./db');
const { getWeekBounds, getWeekKey, getMonthBounds, getMonthKey, nowInZone } = require('./timezone');

const KEYS = {
  CURRENT_WEEK_KEY: 'current_week_key',
  CURRENT_WEEK_START: 'current_week_start',
  CURRENT_MONTH_KEY: 'current_month_key',
  CURRENT_MONTH_START: 'current_month_start',
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

function initWeekStateIfMissing(timezone, weekStartDay) {
  const existingKey = getState(KEYS.CURRENT_WEEK_KEY);
  const existingStart = getState(KEYS.CURRENT_WEEK_START);
  if (existingKey && existingStart) return { key: existingKey, startMs: Number(existingStart) };

  const bounds = getWeekBounds(nowInZone(timezone), weekStartDay);
  const key = getWeekKey(bounds.start, weekStartDay);
  setState(KEYS.CURRENT_WEEK_KEY, key);
  setState(KEYS.CURRENT_WEEK_START, String(bounds.start.toMillis()));
  return { key, startMs: bounds.start.toMillis() };
}

function initMonthStateIfMissing(timezone) {
  const existingKey = getState(KEYS.CURRENT_MONTH_KEY);
  const existingStart = getState(KEYS.CURRENT_MONTH_START);
  if (existingKey && existingStart) return { key: existingKey, startMs: Number(existingStart) };

  const bounds = getMonthBounds(nowInZone(timezone));
  const key = getMonthKey(bounds.start);
  setState(KEYS.CURRENT_MONTH_KEY, key);
  setState(KEYS.CURRENT_MONTH_START, String(bounds.start.toMillis()));
  return { key, startMs: bounds.start.toMillis() };
}

function getCurrentWeekKey(timezone, weekStartDay) {
  return initWeekStateIfMissing(timezone, weekStartDay).key;
}

function getCurrentWeekStart(timezone, weekStartDay) {
  return initWeekStateIfMissing(timezone, weekStartDay).startMs;
}

function getCurrentMonthKey(timezone) {
  return initMonthStateIfMissing(timezone).key;
}

function getCurrentMonthStart(timezone) {
  return initMonthStateIfMissing(timezone).startMs;
}

function setCurrentWeek(key, startMs) {
  setState(KEYS.CURRENT_WEEK_KEY, key);
  setState(KEYS.CURRENT_WEEK_START, String(startMs));
}

function setCurrentMonth(key, startMs) {
  setState(KEYS.CURRENT_MONTH_KEY, key);
  setState(KEYS.CURRENT_MONTH_START, String(startMs));
}

/** الفترة اللي تنتمي لها رسالة فعليًا حسب توقيت إرسالها - مستقلة عن "الحالية". */
function periodKeysFor(messageCreatedAt, timezone, weekStartDay) {
  const { DateTime } = require('luxon');
  const at = DateTime.fromMillis(messageCreatedAt).setZone(timezone);
  return { weekKey: getWeekKey(at, weekStartDay), monthKey: getMonthKey(at) };
}

module.exports = {
  KEYS,
  getState,
  setState,
  getCurrentWeekKey,
  getCurrentWeekStart,
  getCurrentMonthKey,
  getCurrentMonthStart,
  setCurrentWeek,
  setCurrentMonth,
  periodKeysFor,
};
