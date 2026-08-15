// الدومين الخاص (enclave-admin.tsh87.com) يمر عبر بروكسي Cloudflare قبل
// Railway، وCloudflare يعيد كتابة الـ Host لدومين Railway الشغّال (Origin
// Rule) عشان Railway يعرف يوجّه الطلب. النتيجة: من داخل التطبيق ما نقدر
// نميّز الطلب حسب الـ Host، وreq.ip يطلع IP إيدج Cloudflare مو الزائر —
// وهذا يخرّب حد محاولات الدخول لأن كل الزوّار يشتركون بنفس الـ IP.
//
// Cloudflare يضيف هيدر CF-Connecting-IP فيه IP الزائر الحقيقي. لكن ما نثق
// فيه أعمى: أي شخص يطلب مباشرة من رابط Railway الخام يقدر يزوّر الهيدر
// ويلغي حد المحاولات كليًا (ويصير تخمين رقم سري من ٤ خانات ممكن).
//
// فنتحقق إن الطلب جاي فعليًا من شبكة Cloudflare قبل ما نصدّق الهيدر —
// بمقارنة الـ IP المتصل مع نطاقات Cloudflare المعلنة رسميًا.
// المصدر: https://www.cloudflare.com/ips/

const net = require('net');

const CF_IPV4 = [
  '173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22',
  '141.101.64.0/18', '108.162.192.0/18', '190.93.240.0/20', '188.114.96.0/20',
  '197.234.240.0/22', '198.41.128.0/17', '162.158.0.0/15', '104.16.0.0/13',
  '104.24.0.0/14', '172.64.0.0/13', '131.0.72.0/22',
];

const CF_IPV6 = [
  '2400:cb00::/32', '2606:4700::/32', '2803:f800::/32', '2405:b500::/32',
  '2405:8100::/32', '2a06:98c0::/29', '2c0f:f248::/32',
];

function ipv4ToInt(ip) {
  const parts = ip.split('.');
  if (parts.length !== 4) return null;
  let n = 0;
  for (const p of parts) {
    const v = Number(p);
    if (!Number.isInteger(v) || v < 0 || v > 255) return null;
    n = n * 256 + v;
  }
  return n;
}

function inCidr4(ip, cidr) {
  const [range, bitsStr] = cidr.split('/');
  const bits = Number(bitsStr);
  const ipInt = ipv4ToInt(ip);
  const rangeInt = ipv4ToInt(range);
  if (ipInt === null || rangeInt === null) return false;
  // >>> 0 يخلي الإزاحة بدون إشارة (JS bitwise يشتغل على 32-bit موقّعة)
  const mask = bits === 0 ? 0 : (~0 << (32 - bits)) >>> 0;
  return ((ipInt & mask) >>> 0) === ((rangeInt & mask) >>> 0);
}

// يحوّل IPv6 (بأي اختصار) لعدد 128-bit عشان نقدر نقارن البادئة
function ipv6ToBigInt(ip) {
  let addr = ip;
  const zoneIdx = addr.indexOf('%');
  if (zoneIdx !== -1) addr = addr.slice(0, zoneIdx);

  // صيغة IPv4-mapped مثل ::ffff:1.2.3.4
  const v4 = addr.match(/(\d+\.\d+\.\d+\.\d+)$/);
  let tail = '';
  if (v4) {
    const n = ipv4ToInt(v4[1]);
    if (n === null) return null;
    tail = `${((n >>> 16) & 0xffff).toString(16)}:${(n & 0xffff).toString(16)}`;
    addr = addr.slice(0, v4.index) + tail;
  }

  const halves = addr.split('::');
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(':').filter(Boolean) : [];
  const rest = halves.length === 2 && halves[1] ? halves[1].split(':').filter(Boolean) : [];
  const fill = 8 - head.length - rest.length;
  if (fill < 0 || (halves.length === 1 && head.length !== 8)) return null;
  const groups = [...head, ...Array(halves.length === 2 ? fill : 0).fill('0'), ...rest];
  if (groups.length !== 8) return null;

  let n = 0n;
  for (const g of groups) {
    const v = parseInt(g, 16);
    if (Number.isNaN(v) || v < 0 || v > 0xffff) return null;
    n = (n << 16n) | BigInt(v);
  }
  return n;
}

function inCidr6(ip, cidr) {
  const [range, bitsStr] = cidr.split('/');
  const bits = BigInt(bitsStr);
  const ipInt = ipv6ToBigInt(ip);
  const rangeInt = ipv6ToBigInt(range);
  if (ipInt === null || rangeInt === null) return false;
  const shift = 128n - bits;
  return ipInt >> shift === rangeInt >> shift;
}

function isCloudflareIp(ip) {
  if (!ip) return false;
  let addr = String(ip);
  // Node أحيانًا يعطي IPv4 بصيغة IPv6-mapped
  if (addr.startsWith('::ffff:') && net.isIPv4(addr.slice(7))) addr = addr.slice(7);

  if (net.isIPv4(addr)) return CF_IPV4.some((c) => inCidr4(addr, c));
  if (net.isIPv6(addr)) return CF_IPV6.some((c) => inCidr6(addr, c));
  return false;
}

function clientIp(req) {
  const cfIp = req.headers['cf-connecting-ip'];
  if (cfIp && isCloudflareIp(req.ip)) return cfIp;
  return req.ip;
}

module.exports = { clientIp, isCloudflareIp };
