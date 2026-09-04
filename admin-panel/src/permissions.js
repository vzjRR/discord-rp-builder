// صلاحيات الحسابات — المالك يختار لكل حساب ما يستطيع فعله.
//
// المالك يملك كل شيء ضمنًا ولا تُطبَّق عليه هذه القائمة؛ إدارة الحسابات
// نفسها تبقى للمالك وحده مهما مُنح غيره.
//
// حساب أُنشئ قبل وجود هذه الميزة تكون خانته فارغة (NULL)، ونعامله على أنه
// يملك كل الصلاحيات: من كان يعمل بالأمس لا يصح أن يستيقظ اليوم محجوبًا عن
// عمله بلا قرار من المالك. أما الحسابات الجديدة فصلاحياتها صريحة دائمًا.

const ALL = {
  'messages.dm': 'إرسال الرسائل الخاصة (للجميع أو لرتبة أو لعضو)',
  'messages.announce': 'نشر الإعلانات في القنوات',
  'moderation.kick': 'طرد الأعضاء',
  'moderation.ban': 'الحظر ورفعه',
  'moderation.timeout': 'الإسكات المؤقت (Timeout)',
  'moderation.warn': 'إرسال التحذيرات',
  'moderation.purge': 'حذف الرسائل بالجملة',
  'moderation.lock': 'قفل القنوات وفتحها',
  'server.manage': 'إدارة القنوات والفئات والرتب',
  'templates.manage': 'تعديل الرسائل الثابتة',
  'logs.view': 'الاطّلاع على سجل النشاط',
  'status.view': 'عرض حالة السيرفر',
  'points.view': 'عرض ترتيب نقاط الدعم (لوحة الصدارة والسجل)',
  'points.manage': 'تعديل نقاط الدعم يدويًا (إضافة/خصم/تصفير) وإعادة مسح الأرشيف',
};

const KEYS = Object.keys(ALL);

// ما يُمنح افتراضيًا لحساب جديد حين لا يختار المالك شيئًا: الاطّلاع فقط.
// الأصل ألا يملك الحساب الجديد أثرًا على السيرفر حتى يُمنح ذلك صراحة.
const DEFAULT_KEYS = ['logs.view', 'status.view'];

function normalize(list) {
  if (!Array.isArray(list)) return [];
  return KEYS.filter((k) => list.includes(k));
}

function serialize(list) {
  return JSON.stringify(normalize(list));
}

function parse(stored) {
  if (stored === null || stored === undefined || stored === '') return null; // حساب قديم
  try {
    const parsed = JSON.parse(stored);
    return normalize(parsed);
  } catch {
    return [];
  }
}

/**
 * صلاحيات فعلية لحساب: المالك كل شيء، والحساب القديم كل شيء، وغيرهما
 * ما خُزِّن له صراحة.
 *
 * ولا شيء إطلاقًا لمن لا جلسة له. هذا الشرط أول ما يُفحص عمدًا: بدونه
 * كان الغياب (null/undefined) يمرّ على شرط "الحساب القديم" فيُمنح كل
 * الصلاحيات. لا يُستغَلّ اليوم لأن requireAuth يسبق كل حارس صلاحية، لكن
 * مسارًا واحدًا يُكتب غدًا بلا requireAuth كان سيفتح المنصة للعالم.
 */
function effective(admin) {
  if (!admin || typeof admin !== 'object') return [];

  // التمييز بين حالتين تتشابهان في الظاهر ويفترقان في المعنى:
  //
  //   permissions === null       صفّ قديم سابق للميزة — كامل الصلاحيات
  //   permissions === undefined  ليس وصفَ حسابٍ أصلًا — لا صلاحية
  //
  // لذلك يجب على كل مُستدعٍ أن يمرّر permissions صراحةً (ولو null).
  // الخلط بينهما هو ما يجعل جلسةً معدومة تُقرأ "حسابًا قديمًا" فتُمنح
  // كل شيء — وهي الثغرة التي كان هذا الشرط موضوعًا لسدّها.
  if (admin.permissions === undefined) return [];
  if (admin.isOwner) return [...KEYS];
  if (admin.permissions === null) return [...KEYS];
  return admin.permissions;
}

function can(admin, key) {
  return effective(admin).includes(key);
}

/** حارس مسار: يمنع الطلب ما لم يملك صاحب الجلسة الصلاحية المطلوبة. */
function requirePermission(key) {
  return (req, res, next) => {
    if (can(req.admin, key)) return next();
    if (req.path.startsWith('/api/')) {
      return res.status(403).json({ error: 'ليست لديك صلاحية لهذا الإجراء' });
    }
    return res.redirect('/');
  };
}

/** حارس صفحة: يكفي أن يملك صاحب الجلسة واحدة من الصلاحيات المذكورة. */
function requireAnyPermission(keys) {
  return (req, res, next) => {
    if (keys.some((k) => can(req.admin, k))) return next();
    if (req.path.startsWith('/api/')) {
      return res.status(403).json({ error: 'ليست لديك صلاحية لهذا الإجراء' });
    }
    return res.redirect('/');
  };
}

module.exports = {
  ALL,
  KEYS,
  DEFAULT_KEYS,
  normalize,
  serialize,
  parse,
  effective,
  can,
  requirePermission,
  requireAnyPermission,
};
