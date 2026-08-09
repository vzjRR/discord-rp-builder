// يركّب صورة ترحيب Enclave RP: يحط صورة العضو (Avatar) داخل الدائرة اليمنى
// من assets/welcome_template.png، ويرجع Buffer لصورة PNG جاهزة للإرسال.
//
// الإحداثيات (CENTER / RADIUS) مضبوطة يدويًا حسب تصميم welcome_template.png
// الحالي. لو غيّرت التصميم أو مقاسه، لازم تحدّث هذي القيم بالتوافق مع
// assets/avatar_hole_mask.png الجديد.

const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const TEMPLATE_PATH = path.join(__dirname, '..', 'assets', 'welcome_template.png');
const MASK_PATH = path.join(__dirname, '..', 'assets', 'avatar_hole_mask.png');

const CANVAS = { width: 1698, height: 608 };
const CENTER = { x: 1409, y: 313 };
const RADIUS = 230;

async function composeWelcomeImage(avatarUrl) {
  const avatarResp = await fetch(avatarUrl);
  if (!avatarResp.ok) {
    throw new Error(`فشل تحميل صورة العضو (${avatarResp.status})`);
  }
  const avatarBuffer = Buffer.from(await avatarResp.arrayBuffer());

  const size = RADIUS * 2;
  const { data: avData } = await sharp(avatarBuffer)
    .resize(size, size, { fit: 'cover' })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  // كانفاس شفاف بحجم الصورة الكاملة، نحط فيه صورة العضو بمكان الدائرة
  const canvasBuf = Buffer.alloc(CANVAS.width * CANVAS.height * 4, 0);
  const startX = CENTER.x - RADIUS;
  const startY = CENTER.y - RADIUS;
  for (let y = 0; y < size; y++) {
    const destY = startY + y;
    if (destY < 0 || destY >= CANVAS.height) continue;
    for (let x = 0; x < size; x++) {
      const destX = startX + x;
      if (destX < 0 || destX >= CANVAS.width) continue;
      const srcIdx = (y * size + x) * 4;
      const destIdx = (destY * CANVAS.width + destX) * 4;
      canvasBuf[destIdx] = avData[srcIdx];
      canvasBuf[destIdx + 1] = avData[srcIdx + 1];
      canvasBuf[destIdx + 2] = avData[srcIdx + 2];
      canvasBuf[destIdx + 3] = avData[srcIdx + 3];
    }
  }

  // نقص صورة العضو بنفس شكل الدائرة بالضبط (avatar_hole_mask.png)
  const { data: maskData } = await sharp(MASK_PATH)
    .greyscale()
    .raw()
    .toBuffer({ resolveWithObject: true });

  for (let i = 0, p = 0; i < CANVAS.width * CANVAS.height; i++, p += 4) {
    if (maskData[i] < 128) canvasBuf[p + 3] = 0;
  }

  const avatarLayerPng = await sharp(canvasBuf, {
    raw: { width: CANVAS.width, height: CANVAS.height, channels: 4 },
  })
    .png()
    .toBuffer();

  // نحط تصميم البانر (الإطار) فوق صورة العضو
  const templateBuffer = fs.readFileSync(TEMPLATE_PATH);
  const finalImage = await sharp(avatarLayerPng)
    .composite([{ input: templateBuffer, left: 0, top: 0 }])
    .png()
    .toBuffer();

  return finalImage;
}

module.exports = { composeWelcomeImage, CANVAS, CENTER, RADIUS };