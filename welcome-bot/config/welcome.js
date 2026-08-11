// كل التخصيص هنا — عدّل النص والصورة بدون لمس welcome-bot.js
//
// المتغيرات المتاحة داخل contentTemplate / dmMessage:
//   {member}       → منشن العضو (يشعره بإشعار)
//   {memberTag}    → يوزرنيم العضو (بدون منشن)
//   {displayName}  → الاسم المعروض للعضو (اللقب بالسيرفر إن وجد)
//   {memberCount}  → ترتيب العضو (رقم 1, 2, 3...)
//   {serverName}   → اسم السيرفر
//   {rulesChannel} → منشن قناة #rules تلقائيًا (لازم تكون موجودة بنفس الاسم بالأسفل)
//   {inviter}      → منشن العضو اللي دعاه (يحتاج صلاحية "Manage Server" للبوت — راجع القسم 6.5 بالـ README)
//
//   القنوات — لكل وحدة صيغتين:
//     {welcomeChannel} {rulesChannel} {ticketChannel}          → منشن <#id> (للرسائل داخل السيرفر)
//     {welcomeChannelUrl} {rulesChannelUrl} {ticketChannelUrl} → رابط كامل قابل للضغط (للـ DM)
//   داخل رسالة الخاص استخدم صيغة ...Url — المنشن ما ينضغط برّا السيرفر.

module.exports = {
  // اسم القناة اللي ترسل فيها رسالة الترحيب (لازم تطابق اسم القناة بالضبط)
  channelName: '✈️・enclave-airport',

  // اسم قناة القوانين (تُستخدم مع {rulesChannel} بالأسفل)
  rulesChannelName: '📜・rules',

  // اسم قناة فتح التذاكر (تُستخدم مع {ticketChannel} / {ticketChannelUrl})
  // خلّيها null لو ما تبي تذكرها بالرسالة
  ticketChannelName: '🎫・create-ticket',

  // نص الرسالة (عادي، مو Embed) — يُرسل مع الصورة المولّدة تلقائيًا
  contentTemplate:
    '✦ | 𝑾𝒆𝒍𝒄𝒐𝒎𝒆 𝒕𝒐 𝑬𝒏𝒄𝒍𝒂𝒗𝒆 𝑹𝑷\n' +
    '✦ | {member} !\n' +
    '✦ | 𝑷𝒍𝒆𝒂𝒔𝒆 𝒈𝒐 𝒂𝒏𝒅 𝒓𝒆𝒂𝒅 𝒕𝒉𝒆 𝒓𝒖𝒍𝒆𝒔: {rulesChannel}\n' +
    '✦ | 𝒀𝒐𝒖 𝒂𝒓𝒆 𝒕𝒉𝒆 𝒖𝒔𝒆𝒓 𝒏𝒖𝒎𝒃𝒆𝒓 #{memberCount} 𝒊𝒏 𝒐𝒖𝒓 𝒔𝒆𝒓𝒗𝒆𝒓\n' +
    '✦ | 𝑰𝒏𝒗𝒊𝒕𝒆𝒅 𝒃𝒚 : {inviter}',

  // يولّد صورة الترحيب تلقائيًا لكل عضو جديد من assets/welcome_template.png
  // عبر lib/composeWelcomeImage.js — يركّب عليها:
  //   • صورة العضو داخل الدائرة اليمنى
  //   • الاسم المعروض تحت كلمة WELCOME
  //   • اليوزرنيم (@username) بالصندوق تحت الأفاتار
  //   • عدد أعضاء السيرفر بصندوق CURRENT MEMBERS تحت اليسار
  // لتعديل مواقع/أحجام/ألوان النصوص: LAYOUT بداخل lib/composeWelcomeImage.js
  // خليها false لو تبي ترجع لصورة ثابتة بدل الصورة المولّدة
  generateWelcomeImage: true,

  // اسم ملف الصورة المرفقة (يظهر بالرابط attachment://<اسمه>)
  generatedImageFilename: 'welcome.png',

  // تتبع الدعوات (Invite Tracking) لمعرفة مين دعا العضو الجديد لتعبئة {inviter}
  // يحتاج صلاحية "Manage Server" (Manage Guild) للبوت — بدونها يطلع {inviter} فاضي
  trackInvites: true,

  // رول يُعطى تلقائيًا لكل عضو جديد فور دخوله (null لتعطيل هذي الخاصية)
  // القيمة الافتراضية تطابق رول '⏳ Pending Verification' من config/roles.js
  autoAssignRole: '👤 Citizen',

  // إرسال رسالة خاصة (DM) للعضو بالإضافة لرسالة القناة
  sendDM: true,
  // ملاحظة: رسالة من أكثر من سطر لازم تكون بين backticks (`) مو بين ' — نص
  // بين علامتي اقتباس عاديين ما يقدر ينكسر على أسطر ويطلع SyntaxError والبوت ما يشتغل.
  //
  // الروابط: نستخدم {…ChannelUrl} مو {…Channel} داخل الـ DM.
  // النسخة القديمة كانت تكتب اسم القناة كنص عادي — وهذا أكيد ما ينضغط.
  // ومنشن <#id> نتيجته تعتمد على العميل وعلى عضوية المستخدم بالسيرفر، أما الرابط
  // الكامل discord.com/channels/... فمضمون ينضغط وينقل العضو مباشرة بكل الحالات.
  dmMessage: `أهلًا وسهلًا فيك في **{serverName}** 🎉
صرت معنا العضو رقم **#{memberCount}** — نورت السيرفر!

📜 **أول خطوة — اقرأ القوانين:**
{rulesChannelUrl}

✈️ **ثاني خطوة — رُح لقناة الطيران وابدأ رحلتك:**
{welcomeChannelUrl}

🎫 **واجهتك مشكلة أو عندك اقتراح؟** افتح تذكرة وفريق الدعم بيوصلك:
{ticketChannelUrl}

نتمنى لك وقتًا ممتعًا معنا 🚀`,
};
