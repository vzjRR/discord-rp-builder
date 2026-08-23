# بوت Enclave — منصة الإدارة على خادم منفصل

ينشر بوت سيرفر Enclave على خادمه، ومنصة الإدارة على خادمها الخاص وحدها.

> **لديك خادم يعمل عليه Enclave-RP-Store أو منصة الإدارة بالفعل؟** استعمل
> [`EXISTING-SERVER.md`](./EXISTING-SERVER.md) بدلًا من هذه الصفحة —
> يضيف البوت على ذلك الخادم نفسه بلا خادم Oracle ثانٍ، وبمسارات لا
> تتقاطع مع ما هو قائم.

> بوتات سيرفر LSPD (ترحيب، لوقات، تذاكر) لها مستودع ونشرة منفصلان تمامًا
> الآن: [`vzjRR/ENCLAVE-LSPD`](https://github.com/vzjRR/ENCLAVE-LSPD).

| | |
|---|---|
| الخدمة | `enclave-bot` |
| الأسرار | `/etc/enclave/enclave-bot.env` |
| البيانات | `/data/server-events.db` |

## النشر

من لوحة Oracle Cloud: **Compute ← Instances ← Create instance**

| الخيار | القيمة |
|---|---|
| Image | Ubuntu 24.04 |
| Shape | `VM.Standard.A1.Flex` |

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

**املأ ملف الأسرار:**

```bash
nano /etc/enclave/enclave-bot.env
```

**شغّله:**

```bash
systemctl enable --now enclave-bot
systemctl status enclave-bot --no-pager
journalctl -u enclave-bot -f
```

## ما يحتاجه من ديسكورد

في Developer Portal الخاص بتطبيقه:

- **Server Members Intent** مفعّلة، وإلا لم يصله حدث انضمام عضو أصلًا.
- صلاحية **Manage Server** في سيرفره، ليقرأ قائمة الدعوات فيعرف من دعا
  العضو الجديد. بدونها يعمل الترحيب، لكن يظهر كل عضو وكأنه دخل عبر رابط
  السيرفر العام لا عبر دعوة أحد.
- `GuildMessages` أيضًا (لعدّاد النشاط في صفحة حالة السيرفر) — غير
  مميّزة ولا تحتاج تفعيلًا، ولا يُقرأ نص أي رسالة.

## منصة الإدارة على الخادم الآخر

انشرها من `deploy/enclave-panel/` على خادم منفصل. تقرأ
`/data/server-events.db` الذي يكتبه بوت Enclave، فإن بقيا على خادمين
مختلفين — كما هو الحال هنا — تعمل المنصة كاملةً **عدا** «آخر المغادرين»
و«الأكثر تفاعلًا» في صفحة حالة السيرفر؛ فتلك بيانات لا يملكها إلا البوت
نفسه على خادمه.

## التشغيل اليومي

```bash
cd /opt/enclave && git pull
systemctl restart enclave-bot
journalctl -u enclave-bot -f
```
