# البوتان معًا — منصة الإدارة على خادم منفصل

ينشر بوت سيرفر Enclave وبوت سيرفر LSPD معًا على خادم واحد، ومنصة
الإدارة على خادمها الخاص وحدها.

**بوت واحد لكل سيرفر** — كما هو مبني أصلًا. اجتماعهما هنا في خادم واحد
لا يعني دمجهما في عملية واحدة: كلٌّ يعمل بخدمة `systemd` مستقلة، وملف
أسرار مستقل بتوكن مختلف، ويتصل بسيرفر ديسكورد مختلف. تُشغَّل وتُوقَف
وتُحدَّث كلٌّ على حدة، وسقوط إحداها لا يُسقط الأخرى.

| | |
|---|---|
| الخدمات | `enclave-bot` و`lspd-bot` |
| الأسرار | `/etc/enclave/enclave-bot.env` و`/etc/enclave/lspd-bot.env` |
| البيانات | `/data/server-events.db` (لبوت Enclave وحده) |

## النشر

من لوحة Oracle Cloud: **Compute ← Instances ← Create instance**

| الخيار | القيمة |
|---|---|
| Image | Ubuntu 24.04 |
| Shape | `VM.Standard.A1.Flex` — يكفي معالج واحد و٤ غيغابايت لبوتين اثنين |

**Advanced options ← Management ← Paste cloud-init script**، والصق
[`cloud-init.yaml`](./cloud-init.yaml) **كما هو دون أي تعديل** — أي حرف
عربي يُضاف إلى تلك الخانة يُرجع خطأ «Incorrectly formatted request»
(الكونسول يُرمّز الحقل بـ base64 ويرفض غير ASCII).

احفظ مفتاح SSH الذي تعرضه الصفحة. يهيّئ الخادم نفسه خلال دقائق، ثم أكمل
من **Cloud Shell** (أيقونة الطرفية في لوحة Oracle — تعمل داخل المتصفح):

```bash
ssh ubuntu@<عنوان-هذا-الخادم>
sudo -i
```

**املأ ملفَّي الأسرار — منفصلان بتوكنين مختلفين:**

```bash
nano /etc/enclave/enclave-bot.env
nano /etc/enclave/lspd-bot.env
```

> ⚠️ **لا تخلط بينهما.** كلاهما يقرأ `DISCORD_TOKEN` و`GUILD_ID` بالاسمين
> نفسيهما، لكنهما بوتان مختلفان على سيرفرين مختلفين. وضع توكن Enclave في
> ملف LSPD (أو العكس) يجعل البوت يرحّب في السيرفر الخطأ بهوية البوت
> الخطأ.

**شغّلهما:**

```bash
systemctl enable --now enclave-bot lspd-bot
systemctl status enclave-bot lspd-bot --no-pager
journalctl -u enclave-bot -f
```

## ما يحتاجه كل بوت من ديسكورد

لكل واحد على حدة، في Developer Portal الخاص بتطبيقه:

- **Server Members Intent** مفعّلة، وإلا لم يصله حدث انضمام عضو أصلًا.
- صلاحية **Manage Server** في سيرفره، ليقرأ قائمة الدعوات فيعرف من دعا
  العضو الجديد. بدونها يعمل الترحيب، لكن يظهر كل عضو وكأنه دخل عبر رابط
  السيرفر العام لا عبر دعوة أحد.
- بوت Enclave وحده يحتاج `GuildMessages` أيضًا (لعدّاد النشاط في صفحة
  حالة السيرفر) — غير مميّزة ولا تحتاج تفعيلًا، ولا يُقرأ نص أي رسالة.

## منصة الإدارة على الخادم الآخر

انشرها من `deploy/enclave-panel/` على خادم منفصل. تقرأ
`/data/server-events.db` الذي يكتبه بوت Enclave، فإن بقيا على خادمين
مختلفين — كما هو الحال هنا — تعمل المنصة كاملةً **عدا** «آخر المغادرين»
و«الأكثر تفاعلًا» في صفحة حالة السيرفر؛ فتلك بيانات لا يملكها إلا البوت
نفسه على خادمه.

## التشغيل اليومي

```bash
cd /opt/enclave && git pull
systemctl restart enclave-bot lspd-bot   # الاثنان
systemctl restart lspd-bot               # واحد فقط
journalctl -u enclave-bot -f
```
