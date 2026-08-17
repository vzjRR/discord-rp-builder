// استرجاع الرقم السري لمن نسيه.
//
// الفكرة: من يملك حسابًا في المنصة يملك حساب ديسكورد مرتبطًا به، وهذا
// الحساب هو ما نثق به. يطلب صاحب الحساب رمزًا مؤقتًا، فيصله في رسالة خاصة
// من بوت السيرفر، ثم يدخله فتُفتح له جلسة مقيّدة تُجبره على وضع رقم سري
// جديد فورًا. من لا يملك حساب ديسكورد المسجّل لا يستطيع فعل شيء بهذا
// المسار، فلا حاجة لأي تدخّل خارجي أو وصول إلى لوحة الاستضافة.
//
// قيود الأمان المقصودة:
//   • الرمز يُخزَّن مُجزّأً (hash) لا نصًّا صريحًا — تسريب قاعدة البيانات
//     وحده لا يكفي لانتحال أحد.
//   • صلاحية 15 دقيقة، واستعمال واحد فقط، وطلب جديد يُبطل ما قبله.
//   • حدّ للمحاولات لكل حساب ولكل عنوان IP.
//   • الرد على الطلب واحد دائمًا سواء وُجد الحساب أو لا — حتى لا تُستعمل
//     الصفحة لمعرفة أي معرّف ديسكورد يملك صلاحية على المنصة.
//   • عند نجاح الاسترجاع تُحذف كل الجلسات القديمة لذلك الحساب.

const crypto = require('crypto');
const { db } = require('./db');
const auth = require('./auth');
const { logAction } = require('./audit');
const { sendBrandedDM } = require('./messageFormat');
const discord = require('./discord');

const CODE_TTL_MS = 15 * 60 * 1000;
const MAX_ACTIVE_PER_HOUR = 3;
const MIN_INTERVAL_MS = 5 * 60 * 1000; // مهلة بين طلبين متتاليين لنفس الحساب
const MAX_VERIFY_ATTEMPTS = 5; // تخمينات مسموحة للرمز الواحد قبل حرقه

function hashCode(code) {
  return crypto.createHash('sha256').update(String(code)).digest('hex');
}

// رمز من ستة أرقام: قصير بما يكفي لقراءته من رسالة ونقله، ومع صلاحية
// خمس عشرة دقيقة وحدّ محاولات صارم يبقى تخمينه غير عملي.
function generateCode() {
  return String(crypto.randomInt(100000, 1000000));
}

function adminByDiscordId(discordUserId) {
  return db
    .prepare('SELECT id, name, discord_user_id FROM admins WHERE discord_user_id = ? LIMIT 1')
    .get(String(discordUserId));
}

function recentRequestCount(adminId) {
  const { count } = db
    .prepare("SELECT COUNT(*) AS count FROM pin_resets WHERE admin_id = ? AND created_at > datetime('now', '-1 hour')")
    .get(adminId);
  return count;
}

// هل حصل طلب لهذا الحساب خلال المهلة الدنيا؟ يمنع إغراق شخص ما بثلاث
// رسائل خاصة متتالية دفعة واحدة، حتى لو كان ذلك ضمن حدّ الثلاثة بالساعة.
function requestedWithinCooldown(adminId) {
  const { count } = db
    .prepare(
      "SELECT COUNT(*) AS count FROM pin_resets WHERE admin_id = ? AND created_at > datetime('now', ?)"
    )
    .get(adminId, `-${MIN_INTERVAL_MS / 1000} seconds`);
  return count > 0;
}

/**
 * ينشئ رمز استرجاع ويرسله في الخاص لصاحب الحساب.
 * يرجع دائمًا { ok: true } بغضّ النظر عن وجود الحساب — عدا تجاوز الحدّ.
 */
async function requestCode(discordUserId) {
  const admin = adminByDiscordId(discordUserId);
  if (!admin) return { ok: true }; // لا نكشف أن هذا المعرّف غير مسجّل

  // نتجاوز الحدّ بصمت لا برسالة خطأ: رسالة "طلبت كثيرًا" لا تظهر إلا
  // لمعرّف مسجّل، فتصير هي نفسها إجابةً على سؤال "هل لهذا الحساب صلاحية؟"
  if (recentRequestCount(admin.id) >= MAX_ACTIVE_PER_HOUR) {
    console.warn(`pin reset: تجاوز الحدّ للحساب ${admin.id}`);
    return { ok: true };
  }

  // مهلة بين الطلبات المتتالية: أي شخص يعرف معرّف حساب أحدهم يقدر يطلب له
  // رمزًا مسجَّل الحدّ الأقصى ثلاث مرات بالساعة دفعة واحدة — يزعجه برسائل
  // خاصة متتابعة لم يطلبها. هذا لا يفتح حسابه (الرمز يصله هو وحده، والرقم
  // السري الحالي لا يتغيّر إلا بإدخال الرمز الصحيح) لكنه إزعاج حقيقي.
  if (requestedWithinCooldown(admin.id)) {
    console.warn(`pin reset: طلب متكرر بسرعة للحساب ${admin.id}`);
    return { ok: true };
  }

  // طلب جديد يُبطل ما سبقه — حتى لا يبقى أكثر من رمز صالح في وقت واحد
  db.prepare("UPDATE pin_resets SET used_at = datetime('now') WHERE admin_id = ? AND used_at IS NULL").run(admin.id);

  const code = generateCode();
  const expiresAt = new Date(Date.now() + CODE_TTL_MS).toISOString();
  db.prepare('INSERT INTO pin_resets (admin_id, code_hash, expires_at) VALUES (?, ?, ?)').run(
    admin.id,
    hashCode(code),
    expiresAt
  );

  const text =
    `**رمز استرجاع الدخول إلى منصة الإدارة**\n\n` +
    `رمزك المؤقت هو: **${code}**\n\n` +
    `صالح لمدة خمس عشرة دقيقة ولاستعمال واحد فقط. أدخله في صفحة استرجاع ` +
    `الرقم السري، وستُطالب فورًا بوضع رقم سري جديد.\n\n` +
    `إن لم تكن أنت من طلب هذا الرمز فتجاهل هذه الرسالة، ولا تشاركها مع أحد ` +
    `مهما كان؛ من يملكها يملك الدخول إلى حسابك في المنصة.`;

  // فشل الإرسال لا يغيّر ردّنا: لو قلنا "تعذّر إرسال الرمز" لَما ظهرت
  // هذه الجملة إلا لمعرّف مسجّل فعلًا، فتحوّلت الصفحة إلى أداة يعرف بها
  // الغريب مَن يملك صلاحية على المنصة ومَن لا يملكها. الصفحة تُرشد من لم
  // تصله رسالة إلى فحص إعداد رسائله الخاصة.
  try {
    await sendBrandedDM(admin.discord_user_id, { content: text, title: 'استرجاع الرقم السري' });
    logAction({ id: admin.id, name: admin.name }, 'pin_reset.request', 'طلب رمز استرجاع الرقم السري');
  } catch (err) {
    console.error('pin reset DM failed:', err.message);
    logAction(
      { id: admin.id, name: admin.name },
      'pin_reset.request',
      'طُلب رمز استرجاع لكن تعذّر إيصاله في الخاص'
    );
  }

  // لا يملك هذا المسار أي طريقة للتأكد أن طالب الرمز هو صاحب الحساب فعلًا
  // (من طبيعة "نسيت رقمي" أن تكون قبل الدخول) — فمن يعرف معرّف أحدهم يقدر
  // يطلب له رمزًا هو لم يطلبه، وإن لم يفتح له حسابه (الرمز يصل لصاحبه هو
  // وحده) يبقى إزعاجًا متكررًا ممكنًا. نبلّغ المالك بكل طلب ليرى النمط
  // ويتصرف لو تكرر بشكل مريب — كما نفعل تمامًا مع طلبات الوصول الجديدة.
  const notifyId = process.env.OWNER_NOTIFY_USER_ID;
  if (notifyId && notifyId !== admin.discord_user_id) {
    discord
      .sendDM(notifyId, `🔑 طُلب رمز استرجاع الرقم السري لحساب **${admin.name}**. إن تكرر هذا بشكل مريب فقد يكون أحدهم يزعجه بمعرّفه فقط.`)
      .catch((err) => console.error('pin reset owner notify failed:', err.message));
  }

  return { ok: true };
}

/**
 * يتحقق من الرمز، وعند صحته يفتح جلسة مُلزَمة بتغيير الرقم السري.
 */
async function verifyCode(discordUserId, code) {
  const admin = adminByDiscordId(discordUserId);
  if (!admin) return { ok: false, error: 'الرمز غير صحيح أو انتهت صلاحيته' };

  // الرمز ستة أرقام، والحدّ لكل عنوان IP وحده لا يكفي: من يوزّع المحاولات
  // على عناوين كثيرة يلتفّ عليه. فنحصي المحاولات على الرمز نفسه، وبعد
  // MAX_VERIFY_ATTEMPTS يُحرق الرمز ويلزم طلب غيره — فيصير عدد التخمينات
  // المتاح لكل رمز محدودًا مهما تعدّدت العناوين.
  const active = db
    .prepare(
      `SELECT id, expires_at, attempts FROM pin_resets
        WHERE admin_id = ? AND used_at IS NULL
        ORDER BY created_at DESC LIMIT 1`
    )
    .get(admin.id);

  if (!active) return { ok: false, error: 'الرمز غير صحيح أو انتهت صلاحيته' };

  if (active.attempts >= MAX_VERIFY_ATTEMPTS) {
    db.prepare("UPDATE pin_resets SET used_at = datetime('now') WHERE id = ?").run(active.id);
    return { ok: false, error: 'محاولات كثيرة على هذا الرمز. اطلب رمزًا جديدًا' };
  }

  const row = db
    .prepare(
      `SELECT id, expires_at FROM pin_resets
        WHERE id = ? AND code_hash = ?`
    )
    .get(active.id, hashCode(String(code || '').trim()));

  if (!row) {
    db.prepare('UPDATE pin_resets SET attempts = attempts + 1 WHERE id = ?').run(active.id);
    return { ok: false, error: 'الرمز غير صحيح أو انتهت صلاحيته' };
  }
  if (new Date(row.expires_at).getTime() < Date.now()) {
    db.prepare("UPDATE pin_resets SET used_at = datetime('now') WHERE id = ?").run(row.id);
    return { ok: false, error: 'الرمز غير صحيح أو انتهت صلاحيته' };
  }

  db.prepare("UPDATE pin_resets SET used_at = datetime('now') WHERE id = ?").run(row.id);

  // من نسي رقمه لا يعرف رقمه الحالي، فلا يمكنه استعمال مسار التغيير
  // المعتاد. نضع بديلًا عشوائيًا لا يعرفه أحد ونُلزمه بتغييره فورًا:
  // كذا يبقى تغيير الرقم بيده هو وحده، ولا يمر رقم مؤقت عبر أي وسيط.
  const throwaway = crypto.randomBytes(24).toString('hex');
  const pinHash = await auth.hashPin(throwaway);
  db.prepare('UPDATE admins SET pin_hash = ?, must_change_pin = 1 WHERE id = ?').run(pinHash, admin.id);

  // كل جلسة قديمة تسقط — لو كان أحد قد دخل بالرقم المنسي، ينتهي وصوله هنا
  db.prepare('DELETE FROM sessions WHERE admin_id = ?').run(admin.id);

  const session = auth.createSessionFor(admin.id, { viaRecovery: true });
  logAction({ id: admin.id, name: admin.name }, 'pin_reset.complete', 'استرجاع الرقم السري عبر رمز الخاص');
  return { ok: true, ...session };
}

module.exports = { requestCode, verifyCode };
