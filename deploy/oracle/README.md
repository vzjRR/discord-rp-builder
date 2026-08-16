# الانتقال إلى Oracle Cloud

دليل تشغيل بوتات السيرفر ومنصة الإدارة على خادم Oracle Cloud المجاني،
بديلًا عن الاستضافة السابقة.

كُتب ليُنفَّذ من متصفح على الآيباد: لا يحتاج حاسوبًا ولا برنامج SSH.

---

## قبل أن تبدأ — ترتيب لا يجوز عكسه

**لا تُلغِ حساب الاستضافة القديم قبل أن تتأكد أن كل شيء يعمل هنا.**
ما إن يُلغى حتى يضيع ما لم تُخرجه منه، وهذان أمران لا يُستردّان:

1. **بيانات المنصة** — الحسابات وصلاحياتها وسجل النشاط وأحداث السيرفر.
   تُخرَج من المنصة نفسها: «إدارة الحسابات» ← **تنزيل النسخة الاحتياطية**.
2. **صور بوت LSPD وخطه** — `welcome_template.png` و`font-bold.ttf`.
   هذان الملفان لم يُرفعا إلى المستودع قط، ويوجدان على الاستضافة القديمة
   وحدها. بدونهما لا يستطيع بوت LSPD توليد صورة الترحيب إطلاقًا.

---

## ١) أنشئ الخادم

من لوحة Oracle Cloud: **Compute ← Instances ← Create instance**

| الخيار | القيمة |
|---|---|
| Image | Ubuntu 24.04 |
| Shape | `VM.Standard.A1.Flex` — ٢ من المعالجات و١٢ غيغابايت ذاكرة |

هذه الشريحة ضمن «Always Free» دائمًا. المتاح مجانًا ٤ معالجات و٢٤
غيغابايت، فيمكنك رفعها، لكن ما فوق ذلك يُحاسَب. ولا تختر شريحة
`E2.1.Micro` ذات الغيغابايت الواحد: أربع عمليات Node مع توليد الصور
تضيق بها.

ثم: **Advanced options ← Management ← Paste cloud-init script**، والصق
محتوى الملف [`cloud-init.yaml`](./cloud-init.yaml) كاملًا.

احفظ مفتاح SSH الذي تعرضه الصفحة — لن تحتاجه غالبًا، لكن فقدانه يعني
فقدان الطريق الوحيد إلى الخادم إن تعطّل شيء.

اضغط **Create**. يهيّئ الخادم نفسه خلال خمس إلى عشر دقائق: يجلب الكود،
ويثبّت Node والاعتماديات وcloudflared، ويركّب الخدمات.

---

## ٢) افتح نفق Cloudflare

النفق يجعل الخادم يتصل بـ Cloudflare اتصالًا **صادرًا**، فلا يُفتح فيه
منفذ وارد ولا يُكشف عنوانه. وهذا يخدم شرطك الأساسي: لا أحد يرى إلا
دوميك، ولا يوجد أصلًا رابط استضافة خام يمكن أن يتسرّب.

من لوحة Cloudflare: **Zero Trust ← Networks ← Tunnels ← Create a tunnel**

1. اختر **Cloudflared**، وسمِّ النفق `enclave`.
2. انسخ **رمز التثبيت** (سطر طويل يبدأ بـ `eyJ...`).
3. أضف Public hostname:
   - **Subdomain:** `enclave-admin` — **Domain:** `tsh87.com`
   - **Service:** `HTTP` ← `localhost:3000`

Cloudflare ينشئ سجلّ الـ DNS تلقائيًا. بعدها احذف أي سجلّ قديم لهذا
الاسم كان يشير إلى الاستضافة السابقة، وكذلك الـ Worker السابق إن وُجد —
لم تعد له وظيفة.

---

## ٣) اتصل بالخادم مرة واحدة

من لوحة Oracle: **Cloud Shell** (أيقونة الطرفية أعلى الصفحة) — يعمل داخل
المتصفح ولا يحتاج برنامجًا على الآيباد.

```bash
ssh ubuntu@<عنوان-الخادم>
sudo -i
```

### أ) ضع الأسرار

```bash
nano /etc/enclave/enclave.env
```

املأ: `DISCORD_TOKEN` و`GUILD_ID` و`SESSION_SECRET` و`CLOUDFLARE_SECRET`
و`OWNER_NOTIFY_USER_ID`.

> **`SESSION_SECRET` يجب أن يبقى كما كان على الاستضافة القديمة.** تغييره
> يُبطل جلسات كل المسؤولين فيُطالَبون بالدخول من جديد. وإن لم تعرفه
> فولّد غيره واقبل بذلك — لا ضرر عدا إعادة الدخول.

ولبوت LSPD ملف منفصل، لأنه بوت آخر على سيرفر آخر رغم أنه يقرأ أسماء
المتغيرات نفسها:

```bash
nano /etc/enclave/lspd.env
```

### ب) استعد بيانات المنصة

ارفع ملف النسخة الاحتياطية إلى الخادم (Cloud Shell فيه زرّ رفع ملفات)،
ثم:

```bash
node /opt/enclave/admin-panel/scripts/restore-backup.js ~/enclave-backup.json /data
chown -R enclave:enclave /data
```

السكربت يتحقق من بصمة كل ملف قبل كتابته، ويرفض الكتابة فوق موجود إلا
بـ `--force`.

### ج) شغّل النفق والخدمات

```bash
cloudflared service install <الرمز-الذي-نسخته>

systemctl enable --now enclave-welcome enclave-panel
systemctl enable --now enclave-lspd enclave-logs   # إن أردتهما

systemctl status enclave-panel --no-pager
```

---

## ٤) تأكّد قبل أن تُلغي القديم

```bash
journalctl -u enclave-panel -n 30 --no-pager
journalctl -u enclave-welcome -n 30 --no-pager
```

ثم من المتصفح:

- [ ] `https://enclave-admin.tsh87.com` تفتح صفحة الدخول
- [ ] رقمك السري القديم يعمل (دليل أن الاستعادة نجحت)
- [ ] «إدارة الحسابات» تعرض المسؤولين الثمانية
- [ ] «سجل النشاط» يعرض القيود القديمة
- [ ] «حالة السيرفر» تعرض الأعضاء
- [ ] عضو جديد يدخل السيرفر فتصله صورة ترحيب

**عند اكتمال هذه كلها فقط** ألغِ الحساب القديم.

---

## بعد ذلك

**تحديث الكود:**

```bash
cd /opt/enclave && git pull
systemctl restart enclave-panel enclave-welcome
```

**نسخة احتياطية دورية** — من المنصة نفسها: «إدارة الحسابات» ← تنزيل
النسخة الاحتياطية. اجعلها عادة شهرية، واحفظها خارج الخادم؛ فنسخة تعيش
على الجهاز الذي تحميه ليست نسخة احتياطية.

**متابعة السجلات:**

```bash
journalctl -u enclave-panel -f
```

---

## إن تعطّل شيء

| العرَض | الفحص |
|---|---|
| التهيئة لم تكتمل | `cat /var/log/enclave-bootstrap.log` |
| خدمة لا تعمل | `journalctl -u enclave-panel -n 50 --no-pager` |
| الدومين لا يفتح | `systemctl status cloudflared` ثم راجع Public hostname في لوحة Cloudflare |
| المنصة ترد ٤٠٤ على كل شيء | `CLOUDFLARE_SECRET` لا يطابق قاعدة Cloudflare — أو عطّل `REQUIRE_CLOUDFLARE` مؤقتًا حتى تضبطه |
| صورة الترحيب بمربعات فارغة | `FONTCONFIG_PATH` في وحدة الخدمة لا يشير إلى مجلد الخطوط |
