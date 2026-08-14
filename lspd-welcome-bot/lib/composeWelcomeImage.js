// Composites the LSPD welcome banner: member avatar in the neon circle frame (right side),
// and the member's display name under the "WELCOME" word (left side) on a light translucent
// highlight pill so it stays readable over the police-car artwork.
//
// The template's avatar hole is a solid opaque black circle (not a real transparency), so we
// punch a transparent hole into a copy of the template ourselves (via a circular mask + the
// 'dest-out' blend), rather than relying on pre-cut alpha like the old template used.
//
// Text is rendered with @napi-rs/canvas (not sharp's SVG text) because sharp's bundled SVG
// renderer here doesn't reliably load @font-face/system fonts — @napi-rs/canvas registers and
// rasterizes the embedded font file consistently on both Windows (dev) and Linux (Railway).

const path = require('path');
const sharp = require('sharp');
const { createCanvas, GlobalFonts } = require('@napi-rs/canvas');

const TEMPLATE_PATH = path.join(__dirname, '..', 'assets', 'welcome_template.png');
const FONT_PATH = path.join(__dirname, '..', 'assets', 'font-bold.ttf');

const CANVAS = { width: 1536, height: 688 };

// Avatar hole — radius reaches the ring's inner edge (measured by ray-casting outward from
// center to the first bright/neon pixel in every direction) so the photo fills the frame with
// no dark gap, slightly overlapping under the ring's inner glow rather than falling short of it.
const AVATAR_CENTER = { x: 1211, y: 338 };
const AVATAR_RADIUS = 180;

// Name pill target box (per the user's markup on the police-car area, to the right of the
// headlight/hood so it doesn't crowd the "WELCOME" word or the car's front).
const NAME_BOX = { left: 190, right: 567, top: 375, bottom: 515 };
const NAME_COLOR = '#EAE0EE'; // matches the WELCOME word's light lavender-white
const NAME_FONT_SIZE = 38;
const NAME_MAX_WIDTH = NAME_BOX.right - NAME_BOX.left;

let fontRegistered = false;
function ensureFont() {
  if (fontRegistered) return;
  GlobalFonts.registerFromPath(FONT_PATH, 'WelcomeFont');
  fontRegistered = true;
}

function circleMaskSvg(cx, cy, r) {
  return Buffer.from(
    `<svg width="${CANVAS.width}" height="${CANVAS.height}" xmlns="http://www.w3.org/2000/svg">` +
      `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/></svg>`
  );
}

function roundRectPath(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// Renders the name pill (highlight background + text) as a transparent PNG the size of the canvas.
function renderNamePillLayer(displayName) {
  ensureFont();

  const canvas = createCanvas(CANVAS.width, CANVAS.height);
  const ctx = canvas.getContext('2d');
  ctx.font = `${NAME_FONT_SIZE}px WelcomeFont`;
  ctx.textBaseline = 'alphabetic';

  const hPad = 22;
  const maxTextWidth = NAME_MAX_WIDTH - hPad * 2;

  let text = displayName;
  while (text.length > 1 && ctx.measureText(text).width > maxTextWidth) {
    text = text.slice(0, -1);
  }
  if (text !== displayName) text = text.replace(/.{1}$/, '…');

  const textWidth = ctx.measureText(text).width;
  const pillWidth = Math.min(NAME_MAX_WIDTH, textWidth + hPad * 2);
  const pillHeight = NAME_FONT_SIZE + 30;
  const boxCenterX = (NAME_BOX.left + NAME_BOX.right) / 2;
  const boxCenterY = (NAME_BOX.top + NAME_BOX.bottom) / 2;
  const pillX = boxCenterX - pillWidth / 2;
  const pillY = boxCenterY - pillHeight / 2;

  roundRectPath(ctx, pillX, pillY, pillWidth, pillHeight, 14);
  ctx.fillStyle = 'rgba(255,255,255,0.16)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(216,180,255,0.55)';
  ctx.lineWidth = 1.5;
  ctx.stroke();

  ctx.fillStyle = NAME_COLOR;
  ctx.fillText(text, pillX + hPad, pillY + pillHeight / 2 + NAME_FONT_SIZE * 0.35);

  return canvas.toBuffer('image/png');
}

async function composeWelcomeImage(avatarUrl, displayName) {
  const avatarResp = await fetch(avatarUrl);
  if (!avatarResp.ok) {
    throw new Error(`فشل تحميل صورة العضو (${avatarResp.status})`);
  }
  const avatarBuffer = Buffer.from(await avatarResp.arrayBuffer());

  const size = AVATAR_RADIUS * 2;
  const resizedAvatar = await sharp(avatarBuffer).resize(size, size, { fit: 'cover' }).png().toBuffer();

  const mask = circleMaskSvg(AVATAR_CENTER.x, AVATAR_CENTER.y, AVATAR_RADIUS);

  // Avatar clipped to a circle, placed on a full-size transparent canvas.
  const avatarLayer = await sharp({
    create: { width: CANVAS.width, height: CANVAS.height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .composite([
      { input: resizedAvatar, left: AVATAR_CENTER.x - AVATAR_RADIUS, top: AVATAR_CENTER.y - AVATAR_RADIUS },
      { input: mask, blend: 'dest-in' },
    ])
    .png()
    .toBuffer();

  // Template with a transparent hole punched where the avatar goes (it ships as opaque black there).
  const holedTemplate = await sharp(TEMPLATE_PATH).composite([{ input: mask, blend: 'dest-out' }]).png().toBuffer();

  const namePillLayer = displayName ? renderNamePillLayer(displayName) : null;

  const composites = [{ input: holedTemplate, left: 0, top: 0 }];
  if (namePillLayer) composites.push({ input: namePillLayer, left: 0, top: 0 });

  const finalImage = await sharp(avatarLayer).composite(composites).png().toBuffer();

  return finalImage;
}

module.exports = { composeWelcomeImage, CANVAS, AVATAR_CENTER, AVATAR_RADIUS };
