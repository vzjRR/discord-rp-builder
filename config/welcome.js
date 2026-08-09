// كل التخصيص هنا — عدّل النص والصورة بدون لمس welcome-bot.js
//
// المتغيرات المتاحة داخل contentTemplate / dmMessage:
//   {member}       → منشن العضو (يشعره بإشعار)
//   {memberTag}    → اسم العضو (بدون منشن)
//   {memberCount}  → ترتيب العضو (رقم 1, 2, 3...)
//   {serverName}   → اسم السيرفر
//   {rulesChannel} → منشن قناة #rules تلقائيًا (لازم تكون موجودة بنفس الاسم بالأسفل)
//   {inviter}      → منشن العضو اللي دعاه (يحتاج صلاحية "Manage Server" للبوت — راجع القسم 6.5 بالـ README)

module.exports = {
  // اسم القناة اللي ترسل فيها رسالة الترحيب (لازم تطابق اسم القناة بالضبط)
  channelName: '👋・welcome',

  // اسم قناة القوانين (تُستخدم مع {rulesChannel} بالأسفل)
  rulesChannelName: '📜・rules',

  // نص الرسالة (عادي، مو Embed) — يُرسل مع الصورة المولّدة تلقائيًا
  contentTemplate:
    '✦ | 𝑾𝒆𝒍𝒄𝒐𝒎𝒆 𝒕𝒐 𝑬𝒏𝒄𝒍𝒂𝒗𝒆 𝑹𝑷\n' +
    '✦ | {member} !\n' +
    '✦ | 𝑷𝒍𝒆𝒂𝒔𝒆 𝒈𝒐 𝒂𝒏𝒅 𝒓𝒆𝒂𝒅 𝒕𝒉𝒆 𝒓𝒖𝒍𝒆𝒔: {rulesChannel}\n' +
    '✦ | 𝒀𝒐𝒖 𝒂𝒓𝒆 𝒕𝒉𝒆 𝒖𝒔𝒆𝒓 𝒏𝒖𝒎𝒃𝒆𝒓 #{memberCount} 𝒊𝒏 𝒐𝒖𝒓 𝒔𝒆𝒓𝒗𝒆𝒓\n' +
    '✦ | 𝑰𝒏𝒗𝒊𝒕𝒆𝒅 𝒃𝒚 : {inviter}',

  // يولّد صورة الترحيب (اللوقو + صورة العضو بالدائرة) تلقائيًا لكل عضو جديد
  // من assets/welcome_template.png عبر lib/composeWelcomeImage.js
  // خليها false لو تبي ترجع لصورة ثابتة بدل الصورة المولّدة
  generateWelcomeImage: true,

  // اسم ملف الصورة المرفقة (يظهر بالرابط attachment://<اسمه>)
  generatedImageFilename: 'welcome.png',

  // تتبع الدعوات (Invite Tracking) لمعرفة مين دعا العضو الجديد لتعبئة {inviter}
  // يحتاج صلاحية "Manage Server" (Manage Guild) للبوت — بدونها يطلع {inviter} فاضي
  trackInvites: true,

  // رول يُعطى تلقائيًا لكل عضو جديد فور دخوله (null لتعطيل هذي الخاصية)
  // القيمة الافتراضية تطابق رول '⏳ Pending Verification' من config/roles.js
  autoAssignRole: '⏳ Pending Verification',

  // إرسال رسالة خاصة (DM) للعضو بالإضافة لرسالة القناة
  sendDM: false,
  dmMessage: 'يا هلا فيك بسيرفر {serverName}! تفضل زور قناة welcome داخل السيرفر.',
};