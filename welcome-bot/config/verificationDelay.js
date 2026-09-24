// نظام تأجيل رول Citizen — تفعيله/إيقافه من منصة الإدارة (راجع lib/verificationDelay.js).
// افتراضيًا مطفّي حتى لو الملف موجود؛ الحالة الفعلية تُقرأ من ملف الإعدادات
// المشترك مع المنصة، لا من هنا.

module.exports = {
  // لازم يطابق اسم الرول بـ config/roles.js بجذر المستودع بالضبط
  pendingRoleName: '⏳ Pending Verification',

  // مدة الانتظار: عضو جديد كليًا لم يدخل السيرفر من قبل
  newMemberDelayMs: 5 * 60 * 1000,
  // عضو عائد: غادر السيرفر مرة على الأقل قبل هذا الانضمام
  returningMemberDelayMs: 15 * 60 * 1000,

  // قناة صفر التسامح (نفس channelId في config/zeroTolerance.js) — الوحيدة
  // التي يبقى العضو المعلَّق قادرًا على رؤيتها أثناء الانتظار. تطبيق هذا
  // القيد على القنوات فعليًا يتم مرة واحدة عبر: node build.js verification-gate
  zeroToleranceChannelId: require('./zeroTolerance').channelId,

  // رسالة الانتظار — تُرسل خاصًا فور الانضمام لو الميزة مفعّلة
  pendingMessage: (guild) =>
    `مرحبًا بك في **${guild.name}**! 👋\n` +
    `حسابك قيد التحقق حاليًا وسيُفعَّل تلقائيًا خلال دقائق قليلة — يرجى الانتظار قليلًا.\n\n` +
    `Welcome to **${guild.name}**! 👋\n` +
    `Your account is currently being verified and will be activated automatically within a few minutes — please wait.`,

  // رسالة التحقق — تُرسل خاصًا فور انتهاء مدة الانتظار ومنح رول Citizen
  verifiedMessage: (guild) =>
    `✅ تم التحقق من حسابك في **${guild.name}** — استمتع بكامل السيرفر الآن!\n\n` +
    `✅ Your account in **${guild.name}** has been verified — enjoy the full server now!`,
};
