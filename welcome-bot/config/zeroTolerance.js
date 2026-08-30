// قناة صفر تسامح: أي رسالة تُنشر هنا (نص، صورة، إيموجي، أي شيء) تطرد كاتبها
// فورًا بدون أي تحذير، بغض النظر عن رتبته. خلّي channelId فارغًا (أو null)
// لتعطيل الميزة كاملة.
//
// أول وثاني مخالفة لنفس العضو = طرد (Kick)، وثالث مخالفة = حظر دائم (Ban).
// عدّاد المخالفات يبقى محفوظًا حتى لو العضو غادر وعاد، ولا يُصفَّر تلقائيًا.
//
// تنبيه مهم: ديسكورد نفسه يرفض لأي بوت طرد/حظر مالك السيرفر، أو أي عضو
// رتبته الأعلى بمستوى مساوٍ أو أعلى من رتبة البوت نفسه — بغض النظر عن أي
// صلاحيات ممنوحة للبوت. رتّب رول البوت في السيرفر أعلى من كل رتبة تريد
// لهذه الميزة أن تطالها فعليًا.

module.exports = {
  // معرّف القناة (Channel ID): يمين-كلك على القناة بديسكورد → نسخ المعرف
  channelId: '1543257776762003556',

  // عدد المخالفات الذي بلوغه يحوّل العقوبة من طرد إلى حظر دائم
  banAfter: 3,

  kickMessage: (guild, count, banAfter) =>
    `تم طردك من **${guild.name}** بسبب مخالفة قوانين إحدى القنوات. يمكنك الانضمام مجدداً، ` +
    `لكن الوصول إلى ${banAfter} مخالفات سيؤدي إلى حظرك نهائياً من السيرفر. (المخالفة ${count}/${banAfter})\n\n` +
    `You have been kicked from **${guild.name}** for breaking the rules in that channel. ` +
    `You may rejoin, but reaching ${banAfter} violations will get you permanently banned. (Violation ${count}/${banAfter})`,

  banMessage: (guild, count, banAfter) =>
    `تم حظرك نهائياً من **${guild.name}** بسبب تكرار مخالفة قوانين إحدى القنوات (المخالفة ${count}/${banAfter}).\n\n` +
    `You have been permanently banned from **${guild.name}** for repeatedly breaking the rules in that channel (violation ${count}/${banAfter}).`
};
