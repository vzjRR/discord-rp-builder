// الدومين الخاص يمر عبر بروكسي Cloudflare قبل Railway (بروكسيين، مو وحد)،
// فـ req.ip (المبني على X-Forwarded-For مع trust proxy=1) يطلع IP إيدج
// Railway/Cloudflare نفسه مو زوّار حقيقيين — يكسر حدود المحاولات (rate
// limit) لأن الكل يشترك بنفس الـ IP تقريبًا. Cloudflare يضيف هيدر
// CF-Connecting-IP فيه IP الزائر الحقيقي دايمًا.
//
// ما نثق بهذا الهيدر أعمى — أي حد يقدر يزوّره لو طلب مباشرة من رابط
// Railway الخام (welcome-bot-production-*.up.railway.app) ويكسر حد
// المحاولات كليًا. نثق فيه بس لو الطلب جاي فعليًا على الدومين الخاص
// (اللي محمي خلف Cloudflare)، مو أي دومين ثاني يوصل نفس السيرفس.
const CLOUDFLARE_HOSTNAME = 'enclave-admin.tsh87.com';

function clientIp(req) {
  if (req.hostname === CLOUDFLARE_HOSTNAME && req.headers['cf-connecting-ip']) {
    return req.headers['cf-connecting-ip'];
  }
  return req.ip;
}

module.exports = { clientIp };
