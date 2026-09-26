const T = require('./constants');

// ⚠️ محدّث بتاريخ 2026-08-08 ليطابق وضع السيرفر الفعلي (server-snapshot.json)
// الأقسام والقنوات التالية هي فقط اللي موجودة فعليًا بسيرفرك الحين.
// الأقسام المحذوفة من الدوكيومنت الأصلي (city-life, government, reports-appeals,
// design-creative, qa-testing, voice-lounge) أُزيلت من هذا الملف بالكامل.
//
// ⚠️ 2026-09-26 — نمط التسمية الجديد (طلب المستخدم: تصميم القنوات بشكل الصورة
// المرجعية، بنفس الكلمات الإنجليزية الحالية):
//   القنوات النصية:  ⌈{إيموجي}⌋⁞{الاسم}          (بدون مسافات)
//   الأقسام:         EN│───⌈ {الاسم القديم} ⌋───   (٣ شرطات ثابتة كل جهة)
//   القنوات الصوتية: بلا تغيير — الصورة المرجعية أصلًا قنوات نصية فقط،
//                    وأسماء الصوتية الحالية فيها مسافات/حروف كبيرة لا تطابق النمط.
// طُبِّق هذا حيًا عبر: node build.js channel-style — راجع build.js.
// عدد شرطات الأقسام أدناه (٧ ثابتة بمعظمها) قديم من أول محاولة ولم يُحدَّث
// بالكامل — هذا الملف أصلًا معروف أنه لا يطابق القنوات الحيّة (انظر التحذير
// أعلاه)، فلا تثق باسم القسم هنا حرفيًا لأي غرض غير التوثيق.
// أي تعديل هنا يجب أن يطابق بالضبط ما ينتجه ذاك السكربت (logs-bot/config/logs.js
// وwelcome-bot/config/welcome.js وlogs-bot/find-deleter.js تحدّثوا بنفس النمط).

module.exports = [
  {
    key: 'start-here',
    name: 'EN│───────⌈ 📌 START HERE ⌋───────',
    view: ['@everyone'],
    write: T.MANAGEMENT_UP,
    channels: ['⌈👋⌋⁞welcome', '⌈📢⌋⁞announcements', '⌈📜⌋⁞rules', '⌈🟢⌋⁞server-status', '⌈❓⌋⁞faq'],
  },
  {
    key: 'community',
    name: 'EN│───────⌈ 💬 COMMUNITY ⌋───────',
    view: ['@everyone'],
    write: [...T.VERIFIED, ...T.STAFF_UP],
    channels: ['⌈💬⌋⁞general', '⌈📷⌋⁞photos', '⌈📸⌋⁞media', '⌈💡⌋⁞suggestions', '⌈🎁⌋⁞giveaways'],
  },
  {
    key: 'player-center',
    name: 'EN│───────⌈ 🎮 PLAYER CENTER ⌋───────',
    view: ['@everyone'],
    write: T.MANAGEMENT_UP,
    channels: [
      '⌈🎮⌋⁞getting-started', '⌈🧑⌋⁞character-creation', '⌈📚⌋⁞roleplay-help',
      '⌈🏠⌋⁞property-guide', '⌈💼⌋⁞jobs-guide', '⌈📋⌋⁞player-information',
      { name: '⌈📝⌋⁞player-feedback', write: [...T.VERIFIED, ...T.STAFF_UP] },
    ],
  },
  {
    key: 'applications',
    name: 'EN│───────⌈ 📝 APPLICATIONS ⌋───────',
    view: ['@everyone'],
    write: T.MANAGEMENT_UP,
    channels: [
      '⌈📋⌋⁞applications', '⌈👮⌋⁞police-application', '⌈🏥⌋⁞ems-application',
      '⌈⚖️⌋⁞moj-application', '⌈🛡️⌋⁞staff-application', '⌈🎥⌋⁞creator-application',
    ],
  },
  {
    key: 'support-center',
    name: 'EN│───────⌈ 🎫 SUPPORT CENTER ⌋───────',
    view: ['@everyone'],
    write: T.STAFF_UP,
    channels: [
      { name: '⌈🎫⌋⁞create-ticket', write: [...T.VERIFIED, ...T.STAFF_UP] },
      '⌈📢⌋⁞support-info', '⌈📚⌋⁞support-faq',
      { name: '🔊・Support 01', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '🔊・Support 02', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '🔊・Support 03', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '🔊・Support 04', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '🔊・Support 05', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '🔊・support-06', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '⏳・Waiting Room', type: 'voice', write: [...T.VERIFIED, ...T.STAFF_UP] },
      { name: '✅・Completed', type: 'voice' },
      // غرف استراحة داخلية للستاف فقط
      { name: '⌛・break-01', type: 'voice', view: T.STAFF_UP, write: T.STAFF_UP },
      { name: '⌛・break-02', type: 'voice', view: T.STAFF_UP, write: T.STAFF_UP },
      { name: '⌛・break-03', type: 'voice', view: T.STAFF_UP, write: T.STAFF_UP },
    ],
  },
  {
    key: 'server-services',
    name: 'EN│───────⌈ 🛒 SERVER SERVICES ⌋───────',
    view: ['@everyone'],
    write: T.MANAGEMENT_UP,
    channels: ['⌈🛒⌋⁞store', '⌈📜⌋⁞store-rules', '⌈💳⌋⁞payments', '⌈📦⌋⁞purchases'],
  },
  {
    key: 'businesses',
    name: 'EN│───────⌈ 🏢 BUSINESSES ⌋───────',
    view: ['@everyone'],
    write: [...T.MANAGEMENT_UP, ...T.BUSINESS],
    channels: ['⌈📢⌋⁞business-ads', '⌈📢⌋⁞ads', '⌈🍔⌋⁞restaurants', '⌈🔧⌋⁞workshops', '⌈📦⌋⁞logistics'],
  },
  {
    key: 'police',
    name: 'EN│───────⌈ 🚔 POLICE DEPARTMENT ⌋───────',
    view: [...T.MANAGEMENT_UP, ...T.STAFF_UP, ...T.POLICE],
    write: [...T.MANAGEMENT_UP, ...T.STAFF_UP, ...T.POLICE],
    channels: ['⌈🚔⌋⁞police-announcements', '⌈📜⌋⁞police-rules'],
  },
  {
    key: 'ems',
    name: 'EN│───────⌈ 🏥 EMS / MEDICAL ⌋───────',
    view: [...T.MANAGEMENT_UP, ...T.STAFF_UP, ...T.EMS],
    write: [...T.MANAGEMENT_UP, ...T.STAFF_UP, ...T.EMS],
    channels: [
      '⌈🏥⌋⁞ems-announcements', '⌈📜⌋⁞ems-rules', '⌈📚⌋⁞ems-sop', '⌈🚑⌋⁞dispatch',
      '⌈🩺⌋⁞medical-reports', '⌈📋⌋⁞patient-services', '⌈📚⌋⁞medical-training',
    ],
  },
  {
    key: 'moj',
    name: 'EN│───────⌈ ⚖️ MINISTRY OF JUSTICE ⌋───────',
    view: [...T.MANAGEMENT_UP, ...T.STAFF_UP, ...T.MOJ],
    write: [...T.MANAGEMENT_UP, ...T.STAFF_UP, ...T.MOJ],
    channels: [
      { name: '⚖️・Courtroom 01', type: 'voice' },
      '⌈⚖️⌋⁞moj-announcements', '⌈📜⌋⁞laws', '⌈⚖️⌋⁞court-information',
      '⌈📋⌋⁞case-information', '⌈📝⌋⁞legal-applications',
      { name: '⌈🔒⌋⁞judges', view: [...T.MANAGEMENT_UP, ...T.MOJ_COMMAND], write: [...T.MANAGEMENT_UP, ...T.MOJ_COMMAND] },
      { name: '⌈🔒⌋⁞legal-staff', view: [...T.MANAGEMENT_UP, ...T.MOJ], write: [...T.MANAGEMENT_UP, ...T.MOJ] },
    ],
  },
  {
    key: 'cia',
    name: 'EN│───────⌈ 🕵️ CIA ⌋───────',
    view: [...T.MANAGEMENT_UP, ...T.CIA],
    write: [...T.MANAGEMENT_UP, ...T.CIA],
    channels: ['⌈🕵️⌋⁞cia-announcements', '⌈📜⌋⁞cia-rules'],
  },
  {
    key: 'criminal-organizations',
    name: 'EN│───────⌈ 🕶️ CRIMINAL ORGANIZATIONS ⌋───────',
    view: T.STAFF_UP,
    write: T.STAFF_UP,
    channels: ['⌈📜⌋⁞criminal-rules'],
  },
  {
    key: 'events',
    name: 'EN│───────⌈ 🎉 EVENTS ⌋───────',
    view: ['@everyone'],
    write: T.MANAGEMENT_UP,
    channels: ['⌈🎉⌋⁞events', '⌈📢⌋⁞event-announcements', '⌈🏆⌋⁞competitions', '⌈🎁⌋⁞event-rewards', '⌈📸⌋⁞event-media'],
  },
  {
    key: 'staff-center',
    name: 'EN│───────⌈ 🛡️ STAFF CENTER ⌋───────',
    view: T.STAFF_UP,
    write: T.STAFF_UP,
    channels: [
      '⌈📢⌋⁞staff-announcements', '⌈💬⌋⁞staff-chat', '⌈📋⌋⁞staff-tasks', '⌈🚨⌋⁞staff-reports',
      '⌈📋⌋⁞staff-vacation-resignation', '⌈📢⌋⁞staff-promotion',
      { name: '🔊・Staff 01', type: 'voice' },
      { name: '🔊・Staff 02', type: 'voice' },
      { name: '🔊・Staff Meeting', type: 'voice' },
    ],
  },
  {
    key: 'management',
    name: 'EN│───────⌈ 👑 MANAGEMENT ⌋───────',
    view: T.MANAGEMENT_UP,
    write: T.MANAGEMENT_UP,
    channels: [
      '⌈👑⌋⁞management', '⌈📢⌋⁞management-announcements', '⌈📝⌋⁞decisions',
      { name: '👑・Management Office', type: 'voice' },
      { name: '📊・Management Meeting', type: 'voice' },
    ],
  },
  {
    key: 'development',
    name: 'EN│───────⌈ 💻 DEVELOPMENT ⌋───────',
    view: T.DEV_UP,
    write: T.DEV_UP,
    channels: [
      '⌈💻⌋⁞development', '⌈💡⌋⁞feature-requests', '⌈🚀⌋⁞releases', '⌈🔐⌋⁞security',
      { name: '💻・Development', type: 'voice' },
      { name: '🎙️・Dev Meeting', type: 'voice' },
    ],
  },
  {
    // ⚠️ logs-bot يطابق أسماء هذه القنوات بالضبط. لا تُغيّر أي اسم هنا بدون
    // تحديث logs-bot/config/logs.js وlogs-bot/find-deleter.js معه بنفس الوقت.
    key: 'security-logs',
    name: 'EN│───⌈ 🔐 SECURITY & LOGS ⌋───',
    view: T.MANAGEMENT_UP,
    write: T.BOT,
    channels: [
      '⌈🔐⌋⁞security', '⌈📜⌋⁞audit-log', '⌈👤⌋⁞member-log', '⌈🛡️⌋⁞moderation-log', '⌈🎫⌋⁞ticket-log',
      '⌈🚨⌋⁞report-log', '⌈🤖⌋⁞bot-log', '⌈🔨⌋⁞punishment-log', '⌈📥⌋⁞join-log', '⌈📤⌋⁞leave-log',
    ],
  },
  {
    key: 'bot-system',
    name: 'EN│───────⌈ 🤖 BOT SYSTEM ⌋───────',
    view: T.DEV_UP,
    write: [...T.DEV_UP, ...T.BOT],
    channels: [
      { name: '⌈🤖⌋⁞bot-commands', view: ['@everyone'], write: [...T.VERIFIED, ...T.STAFF_UP, ...T.BOT] },
      '⌈🤖⌋⁞bot-status', '⌈⚙️⌋⁞bot-config',
      { name: '⌈📊⌋⁞bot-logs', write: T.BOT },
    ],
  },
  {
    key: 'afk',
    name: 'EN│───────⌈ AFK ⌋───────',
    view: ['@everyone'],
    write: [...T.VERIFIED, ...T.STAFF_UP, ...T.MANAGEMENT_UP],
    channels: [{ name: '💤・AFK', type: 'voice' }],
  },
];
