// الشكل الموحّد لكل رسالة تخرج من المنصة: إطار (Embed) يحمل أيقونة السيرفر
// في الأعلى، ثم نص الرسالة، ثم توقيع الإدارة في الأسفل.
//
// نستخدم Embed لا نصًا عاديًا لأن ديسكورد لا يسمح بوضع صورة في أعلى رسالة
// نصية؛ الصورة في الأعلى والتوقيع في الأسفل لا يتحققان إلا بهذه الطريقة.
//
// أيقونة السيرفر تُجلب مرة واحدة وتُخزَّن مؤقتًا: كل رسالة تحتاجها، ولو
// طلبناها من ديسكورد في كل مرة لأبطأنا البث الجماعي بلا فائدة.

const discord = require('./discord');

const BRAND_COLOR = 0xa855f7; // البنفسجي المعتمد في هوية Enclave
const FOOTER_TEXT = 'مع تحيات إدارة ديسكورد سيرفر ENCLAVE RP';
const CACHE_TTL_MS = 10 * 60 * 1000;

let cached = { at: 0, name: null, iconUrl: null };

async function guildBranding() {
  if (Date.now() - cached.at < CACHE_TTL_MS && cached.name) return cached;
  try {
    const guild = await discord.getGuild();
    cached = { at: Date.now(), name: guild.name, iconUrl: discord.iconUrl(guild, 256) };
  } catch (err) {
    // لا نُفشل إرسال الرسالة لمجرد تعذّر جلب الأيقونة
    console.error('branding fetch failed:', err.message);
    cached = { at: Date.now(), name: cached.name || 'ENCLAVE RP', iconUrl: cached.iconUrl };
  }
  return cached;
}

/**
 * يبني الإطار الموحّد.
 * @param {object} o
 * @param {string} o.content  نص الرسالة (يدعم تنسيق ماركداون الخاص بديسكورد)
 * @param {string} [o.title]  عنوان اختياري يظهر أعلى النص
 */
async function brandedEmbed({ content, title }) {
  const brand = await guildBranding();
  const embed = {
    color: BRAND_COLOR,
    description: String(content || '').slice(0, 4096),
    footer: { text: FOOTER_TEXT, ...(brand.iconUrl ? { icon_url: brand.iconUrl } : {}) },
    timestamp: new Date().toISOString(),
    author: { name: brand.name || 'ENCLAVE RP', ...(brand.iconUrl ? { icon_url: brand.iconUrl } : {}) },
  };
  if (title) embed.title = String(title).slice(0, 256);
  return embed;
}

async function sendBrandedDM(userId, { content, title }) {
  const embed = await brandedEmbed({ content, title });
  return discord.sendDMEmbed(userId, embed);
}

async function sendBrandedChannel(channelId, { content, title }) {
  const embed = await brandedEmbed({ content, title });
  return discord.sendChannelEmbed(channelId, embed);
}

module.exports = { brandedEmbed, sendBrandedDM, sendBrandedChannel, FOOTER_TEXT, BRAND_COLOR };
