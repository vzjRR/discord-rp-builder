// كشف الصور برسالة ديسكورد — لا نعتمد على وجود رابط بالنص وحده، فقط
// مرفقات صور حقيقية أو embed صورة تحقق منه ديسكورد نفسه.

const IMAGE_CONTENT_TYPES = new Set([
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/webp',
  'image/gif',
  'image/bmp',
  'image/tiff',
]);

const IMAGE_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'tif', 'tiff']);

function extensionOf(filename) {
  const match = /\.([a-zA-Z0-9]+)(?:\?.*)?$/.exec(filename || '');
  return match ? match[1].toLowerCase() : undefined;
}

function isImageAttachment(attachment) {
  const contentType = attachment.contentType?.toLowerCase().split(';')[0]?.trim();
  if (contentType && IMAGE_CONTENT_TYPES.has(contentType)) return true;

  // احتياط: أحيانًا ديسكورد ما يرسل contentType. نستخدم الامتداد فقط مع
  // width/height (تُملأ فقط لملفات صورة/فيديو فعلية) - لا نثق بامتداد وحده.
  const ext = extensionOf(attachment.name);
  return Boolean(ext && IMAGE_EXTENSIONS.has(ext) && attachment.height !== null && attachment.width !== null);
}

// embed يُحتسب فقط لو ديسكورد صنّفه بنفسه كـ "image" (رابط مباشر لصورة
// تم فك تشفيره تلقائيًا) - وليس أي embed فيه thumbnail (معاينة مقالة، يوتيوب...).
function isVerifiedImageEmbed(embed) {
  return embed.data?.type === 'image' && Boolean(embed.image?.url);
}

function countImages(message) {
  const attachmentImageCount = message.attachments.filter((a) => isImageAttachment(a)).size;
  const embedImageCount = message.embeds.filter((e) => isVerifiedImageEmbed(e)).length;
  return { count: attachmentImageCount + embedImageCount, attachmentImageCount, embedImageCount };
}

module.exports = { countImages, isImageAttachment, isVerifiedImageEmbed };
