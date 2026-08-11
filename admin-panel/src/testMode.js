// وضع التجربة: أثناء الإعداد، كل رسالة خاصة أو إعلان يطلع من المنصة —
// بغض النظر عن الهدف الحقيقي (الكل / رول معيّن / عضو / قناة) — يروح
// لهذا العضو فقط. لإيقاف وضع التجربة والبدء الفعلي، احذف المتغير
// TEST_MODE_REDIRECT_USER_ID بالكامل من متغيرات البيئة بـ Railway.

function testRedirectUserId() {
  return process.env.TEST_MODE_REDIRECT_USER_ID || null;
}

function isTestMode() {
  return Boolean(testRedirectUserId());
}

module.exports = { testRedirectUserId, isTestMode };
