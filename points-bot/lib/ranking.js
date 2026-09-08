// قاعدة كسر التعادل بالترتيب (موثّقة هنا لأن السلوك يعتمد عليها):
//   ١. النقاط تنازليًا
//   ٢. عدد الصور المؤهِّلة تنازليًا
//   ٣. أقدم توقيت تحقيق تصاعديًا (الأسبق يفوز بالتعادل)
// عمليًا الثلاثة معًا لا تتساوى أبدًا لعضوين مختلفين، فالترتيب حتمي
// تمامًا بلا أي عشوائية.

function compareRankable(a, b) {
  if (b.points !== a.points) return b.points - a.points;
  if (b.images !== a.images) return b.images - a.images;
  return a.firstAchievedAt - b.firstAchievedAt;
}

function rank(entries) {
  return [...entries]
    .sort(compareRankable)
    .map((entry, index) => ({ rank: index + 1, entry }));
}

module.exports = { compareRankable, rank };
