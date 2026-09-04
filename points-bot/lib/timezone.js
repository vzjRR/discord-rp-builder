// حساب حدود الأسبوع/الشهر بتوقيت TIMEZONE (افتراضيًا Asia/Muscat)، مش UTC
// مباشرة. Luxon تبعية جديدة على هذا المستودع لكن ضرورية هنا: لا بوت آخر
// باحتاج حساب تاريخ حقيقي (activityTracker يكتفي بـ toISOString().slice(0,10)
// وهذا يكفيه لأنه لا يهتم ببداية الأسبوع أو DST) - إعادة بناء هذا الحساب
// يدويًا بـ Date/Intl عرضة لأخطاء صعبة الاكتشاف، فتبعية صغيرة مُختبرة أفضل.

const { DateTime } = require('luxon');

const WEEKDAY_NUMBER = {
  MONDAY: 1,
  TUESDAY: 2,
  WEDNESDAY: 3,
  THURSDAY: 4,
  FRIDAY: 5,
  SATURDAY: 6,
  SUNDAY: 7,
};

function nowInZone(timezone) {
  return DateTime.now().setZone(timezone);
}

/** حدود الأسبوع [start, end) الذي تقع فيه at، يبدأ الساعة ٠٠:٠٠ يوم weekStartDay. */
function getWeekBounds(at, weekStartDay) {
  const target = WEEKDAY_NUMBER[weekStartDay];
  const zoned = at.startOf('day');
  const diff = (zoned.weekday - target + 7) % 7;
  const start = zoned.minus({ days: diff }).startOf('day');
  const end = start.plus({ weeks: 1 });
  return { start, end };
}

/** معرّف ثابت وقابل للترتيب للأسبوع، مثل "2026-W35". */
function getWeekKey(at, weekStartDay) {
  const { start } = getWeekBounds(at, weekStartDay);
  const weekNumber = String(start.weekNumber).padStart(2, '0');
  return `${start.weekYear}-W${weekNumber}`;
}

function getMonthBounds(at) {
  const start = at.startOf('month');
  const end = start.plus({ months: 1 });
  return { start, end };
}

function getMonthKey(at) {
  return at.toFormat('yyyy-LL');
}

module.exports = { nowInZone, getWeekBounds, getWeekKey, getMonthBounds, getMonthKey };
