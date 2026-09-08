// محرك النقاط - قلب هذا البوت. القاعدة الوحيدة اللي يعتمد عليها كل شيء:
//
//   نقطة واحدة لكل رسالة فيها صورة واحدة على الأقل - أبدًا أكثر، بغض
//   النظر عن عدد الصور بنفس الرسالة (رسالة فيها مليون صورة = +١ بالضبط).
//
// idempotent بالتصميم: processed_messages.message_id هو المفتاح الأساسي،
// فإعادة معالجة نفس الرسالة (إعادة تشغيل، duplicate event، إعادة تشغيل
// مسح الأرشيف) لا تُضاعف النقاط أبدًا - الإدراج الثاني يفشل بصمت ونتجاهله.

const { db } = require('./db');
const {
  periodKeysFor,
  getCurrentWeekKey,
  getCurrentMonthKey,
  getCurrentDayKey,
  getCurrentYearKey,
} = require('./period');
const { appendAuditFile } = require('./auditFile');

function boolEnv(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value.trim() === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(value.trim().toLowerCase());
}

function cfg() {
  return {
    timezone: process.env.TIMEZONE || 'Asia/Muscat',
    weekStartDay: (process.env.WEEK_START_DAY || 'MONDAY').toUpperCase(),
    imagePointsChannelId: process.env.IMAGE_POINTS_CHANNEL_ID,
    adjustPointsOnMessageEdit: boolEnv('ADJUST_POINTS_ON_MESSAGE_EDIT', true),
  };
}

function isTargetChannel(channelId) {
  return channelId === cfg().imagePointsChannelId;
}

/** نقطة واحدة إن كانت فيها صورة، صفر غير ذلك - أبدًا أكثر مهما كان العدد. */
function pointsForImageCount(imageCount) {
  return imageCount > 0 ? 1 : 0;
}

function recordAudit(entry) {
  const now = Date.now();
  try {
    db.prepare(
      `INSERT INTO audit_log (action_type, user_id, actor_id, message_id, channel_id, points_delta, details, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      entry.actionType,
      entry.userId ?? null,
      entry.actorId ?? null,
      entry.messageId ?? null,
      entry.channelId ?? null,
      entry.pointsDelta ?? null,
      entry.details ? JSON.stringify(entry.details) : null,
      now
    );
  } catch (err) {
    console.error('⚠️  فشل تسجيل سجل نقاط:', err.message);
  }
  appendAuditFile({ ts: new Date(now).toISOString(), type: 'points', ...entry });
}

function getUser(userId) {
  return db.prepare('SELECT * FROM users WHERE discord_user_id = ?').get(userId);
}

function upsertUserProfile(userId, username, displayName) {
  const now = Date.now();
  const existing = getUser(userId);
  if (existing) {
    if (existing.username !== username || existing.display_name !== displayName) {
      db.prepare('UPDATE users SET username = ?, display_name = ?, updated_at = ? WHERE discord_user_id = ?').run(
        username,
        displayName,
        now,
        userId
      );
    }
    return;
  }
  db.prepare(
    `INSERT INTO users (discord_user_id, username, display_name,
                         total_points, weekly_points, monthly_points, daily_points, yearly_points,
                         total_images, weekly_images, monthly_images, daily_images, yearly_images,
                         first_point_at, last_point_at, created_at, updated_at)
     VALUES (?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL, NULL, ?, ?)`
  ).run(userId, username, displayName, now, now);
}

/**
 * يحرّك رصيد عضو. `periods` يحدد أي "سلال" فترة حالية (أسبوعية/شهرية/يومية/سنوية)
 * تتأثر بالتغيير هذا، غير total التي تتأثر دايمًا. كل الأرصدة محمية من السالب
 * (clamp) لأن الحذف/التعديل قد يصل بترتيب غير متوقع تحت ضغط أحداث ديسكورد.
 */
function applyUserDelta(userId, pointsDelta, imagesDelta, periods) {
  if (pointsDelta === 0 && imagesDelta === 0) return;
  const now = Date.now();
  const current = getUser(userId);
  if (!current) {
    console.error('applyUserDelta: مستخدم غير موجود', userId);
    return;
  }

  const clamp = (n) => Math.max(0, n);
  db.prepare(
    `UPDATE users SET
       total_points = ?, weekly_points = ?, monthly_points = ?, daily_points = ?, yearly_points = ?,
       total_images = ?, weekly_images = ?, monthly_images = ?, daily_images = ?, yearly_images = ?,
       first_point_at = ?, last_point_at = ?, updated_at = ?
     WHERE discord_user_id = ?`
  ).run(
    clamp(current.total_points + pointsDelta),
    periods.weekly ? clamp(current.weekly_points + pointsDelta) : current.weekly_points,
    periods.monthly ? clamp(current.monthly_points + pointsDelta) : current.monthly_points,
    periods.daily ? clamp(current.daily_points + pointsDelta) : current.daily_points,
    periods.yearly ? clamp(current.yearly_points + pointsDelta) : current.yearly_points,
    clamp(current.total_images + imagesDelta),
    periods.weekly ? clamp(current.weekly_images + imagesDelta) : current.weekly_images,
    periods.monthly ? clamp(current.monthly_images + imagesDelta) : current.monthly_images,
    periods.daily ? clamp(current.daily_images + imagesDelta) : current.daily_images,
    periods.yearly ? clamp(current.yearly_images + imagesDelta) : current.yearly_images,
    current.first_point_at ?? (pointsDelta > 0 ? now : current.first_point_at),
    pointsDelta > 0 ? now : current.last_point_at,
    now,
    userId
  );
}

/** أي من الفترات الحالية (يوم/أسبوع/شهر/سنة) تطابق مفاتيح فترة رسالة معيّنة. */
function currentPeriodsFor(keys, config) {
  return {
    weekly: keys.weekKey === getCurrentWeekKey(config.timezone, config.weekStartDay),
    monthly: keys.monthKey === getCurrentMonthKey(config.timezone),
    daily: keys.dayKey === getCurrentDayKey(config.timezone),
    yearly: keys.yearKey === getCurrentYearKey(config.timezone),
  };
}

/**
 * رسالة جديدة (messageCreate حي، أو مسح أرشيف). آمن يتكرر: لو الرسالة
 * مُعالجة أصلًا، الإدراج يفشل (message_id مفتاح أساسي) ونرجع بدون أي تأثير.
 */
function recordNewMessage(ctx, source = 'live') {
  if (!isTargetChannel(ctx.channelId)) return { outcome: 'ignored_wrong_channel', pointsDelta: 0 };
  if (ctx.imageCount <= 0) return { outcome: 'no_images', pointsDelta: 0 };

  const config = cfg();

  return db.transaction(() => {
    const alreadyExists = db.prepare('SELECT 1 FROM processed_messages WHERE message_id = ?').get(ctx.messageId);
    if (alreadyExists) return { outcome: 'already_processed', pointsDelta: 0 };

    upsertUserProfile(ctx.userId, ctx.username, ctx.displayName);

    const keys = periodKeysFor(ctx.messageCreatedAt, config.timezone, config.weekStartDay);
    const points = pointsForImageCount(ctx.imageCount);
    const now = Date.now();

    db.prepare(
      `INSERT INTO processed_messages
         (message_id, user_id, channel_id, image_count, points_awarded, week_key, month_key, day_key, year_key,
          source, message_created_at, created_at, updated_at, deleted_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`
    ).run(
      ctx.messageId,
      ctx.userId,
      ctx.channelId,
      ctx.imageCount,
      points,
      keys.weekKey,
      keys.monthKey,
      keys.dayKey,
      keys.yearKey,
      source,
      ctx.messageCreatedAt,
      now,
      now
    );

    applyUserDelta(ctx.userId, points, ctx.imageCount, currentPeriodsFor(keys, config));

    recordAudit({
      actionType: 'IMAGE_COUNTED',
      userId: ctx.userId,
      messageId: ctx.messageId,
      channelId: ctx.channelId,
      pointsDelta: points,
      details: { images: ctx.imageCount, source, ...keys },
    });

    return { outcome: 'counted', pointsDelta: points };
  })();
}

/**
 * تعديل رسالة. النقاط محدودة بـ ١ لكل رسالة، فالانتقال 0<->N صور فقط هو
 * اللي يحرّك نقطة - أي تعديل ثاني (يبقى فيها صور أو تبقى بلا صورة) لا يغيّر شيء.
 */
function recordMessageEdit(ctx) {
  if (!isTargetChannel(ctx.channelId)) return { outcome: 'ignored_wrong_channel', pointsDelta: 0 };

  const config = cfg();

  return db.transaction(() => {
    const existing = db.prepare('SELECT * FROM processed_messages WHERE message_id = ?').get(ctx.messageId);

    if (!existing) {
      // أول ظهور فعلي (كانت أصلًا بلا صور، أو بقناة ثانية وقتها) - نعاملها كرسالة جديدة.
      return recordNewMessage(ctx, 'live');
    }
    if (existing.deleted_at) return { outcome: 'no_change', pointsDelta: 0 };
    if (!config.adjustPointsOnMessageEdit) return { outcome: 'edit_adjustment_disabled', pointsDelta: 0 };

    const imagesDelta = ctx.imageCount - existing.image_count;
    if (imagesDelta === 0) return { outcome: 'no_change', pointsDelta: 0 };

    const newPoints = pointsForImageCount(ctx.imageCount);
    const pointsDelta = newPoints - existing.points_awarded;
    const now = Date.now();

    db.prepare('UPDATE processed_messages SET image_count = ?, points_awarded = ?, updated_at = ? WHERE message_id = ?').run(
      ctx.imageCount,
      newPoints,
      now,
      ctx.messageId
    );

    const keys = { weekKey: existing.week_key, monthKey: existing.month_key, dayKey: existing.day_key, yearKey: existing.year_key };
    applyUserDelta(existing.user_id, pointsDelta, imagesDelta, currentPeriodsFor(keys, config));

    recordAudit({
      actionType: 'MESSAGE_EDIT_ADJUSTED',
      userId: existing.user_id,
      messageId: ctx.messageId,
      channelId: ctx.channelId,
      pointsDelta,
      details: { previousImages: existing.image_count, newImages: ctx.imageCount },
    });

    return { outcome: 'updated', pointsDelta };
  })();
}

/**
 * حذف رسالة. يخصم نقطتها تلقائيًا دايمًا (لا خيار تعطيل) - رسالة انحذفت
 * معناها الصورة ما عادت موجودة، فلا مبرر لبقاء نقطتها.
 */
function recordMessageDelete(messageId, channelId) {
  if (!isTargetChannel(channelId)) return { outcome: 'ignored_wrong_channel', pointsDelta: 0 };

  const config = cfg();

  return db.transaction(() => {
    const existing = db.prepare('SELECT * FROM processed_messages WHERE message_id = ?').get(messageId);
    if (!existing || existing.deleted_at) return { outcome: 'not_found', pointsDelta: 0 };

    const now = Date.now();
    db.prepare('UPDATE processed_messages SET deleted_at = ?, updated_at = ? WHERE message_id = ?').run(now, now, messageId);

    const pointsDelta = -existing.points_awarded;
    const keys = { weekKey: existing.week_key, monthKey: existing.month_key, dayKey: existing.day_key, yearKey: existing.year_key };
    applyUserDelta(existing.user_id, pointsDelta, -existing.image_count, currentPeriodsFor(keys, config));

    recordAudit({
      actionType: 'MESSAGE_DELETE_ADJUSTED',
      userId: existing.user_id,
      messageId,
      channelId,
      pointsDelta,
      details: { removedImages: existing.image_count },
    });

    return { outcome: 'removed', pointsDelta };
  })();
}

/** تعديل يدوي من المنصة (owner) - يؤثر دايمًا على كل الفترات الحالية، بخلاف نقاط الرسائل. */
function adjustPointsManually(userId, username, displayName, pointsDelta, actorId, actionType, reason) {
  return db.transaction(() => {
    upsertUserProfile(userId, username, displayName);
    applyUserDelta(userId, pointsDelta, 0, { weekly: true, monthly: true, daily: true, yearly: true });
    recordAudit({ actionType, userId, actorId, pointsDelta, details: reason ? { reason } : null });
    return getUser(userId);
  })();
}

function resetUserPoints(userId, actorId) {
  return db.transaction(() => {
    const existing = getUser(userId);
    if (!existing) return undefined;
    const now = Date.now();
    db.prepare(
      `UPDATE users SET total_points = 0, weekly_points = 0, monthly_points = 0, daily_points = 0, yearly_points = 0,
                         total_images = 0, weekly_images = 0, monthly_images = 0, daily_images = 0, yearly_images = 0,
                         updated_at = ?
       WHERE discord_user_id = ?`
    ).run(now, userId);
    recordAudit({
      actionType: 'MANUAL_ADJUSTMENT',
      userId,
      actorId,
      pointsDelta: -existing.total_points,
      details: { reason: 'reset', previousTotal: existing.total_points },
    });
    return getUser(userId);
  })();
}

module.exports = {
  pointsForImageCount,
  isTargetChannel,
  recordNewMessage,
  recordMessageEdit,
  recordMessageDelete,
  adjustPointsManually,
  resetUserPoints,
  getUser,
  recordAudit,
  cfg,
};
