// كل التخصيص هنا — عدّل النص واللون والصورة بدون لمس welcome-bot.js
//
// المتغيرات المتاحة داخل title / description / footer:
//   {member}       → منشن العضو (يشعره بإشعار)
//   {memberTag}    → اسم العضو (بدون منشن)
//   {memberCount}  → ترتيب العضو (رقم 1, 2, 3...)
//   {serverName}   → اسم السيرفر
//   {rulesChannel} → منشن قناة #rules تلقائيًا (لازم تكون موجودة بنفس الاسم بالأسفل)

module.exports = {
  // اسم القناة اللي ترسل فيها رسالة الترحيب (لازم تطابق اسم القناة بالضبط)
  channelName: '👋・welcome',

  // اسم قناة القوانين (تُستخدم مع {rulesChannel} بالأسفل)
  rulesChannelName: '📜・rules',

  // لون شريط الـ Embed الجانبي (Hex)
  color: '#2ECC71',

  title: '👋 أهلاً وسهلاً بك!',

  description:
    'يا هلا {member}!\n' +
    'فخورين نشوفك معنا بـ **{serverName}** — أنت العضو رقم **#{memberCount}**.\n\n' +
    '📜 ابدأ بقراءة القوانين: {rulesChannel}\n' +
    '🎮 بعدها روح لقسم Player Center عشان تسوي شخصيتك.\n\n' +
    'استمتع بوقتك معنا! 🎉',

  footer: '{serverName} • RP Server',

  // صورة مصغّرة تظهر بزاوية الرسالة — اتركها 'avatar' لعرض صورة العضو تلقائيًا، أو حط رابط صورة ثابت
  thumbnail: 'avatar',

  // بانر مخصص (تصميمك الخاص) — حط مسار صورة محلية هنا، مثال: './assets/welcome-banner.png'
  // اتركه null إذا ما تبي بانر
  bannerImagePath: null,

  // رول يُعطى تلقائيًا لكل عضو جديد فور دخوله (null لتعطيل هذي الخاصية)
  // القيمة الافتراضية تطابق رول '⏳ Pending Verification' من config/roles.js
  autoAssignRole: '⏳ Pending Verification',

  // إرسال رسالة خاصة (DM) للعضو بالإضافة لرسالة القناة
  sendDM: false,
  dmMessage: 'يا هلا فيك بسيرفر {serverName}! تفضل زور قناة welcome داخل السيرفر.',
};
