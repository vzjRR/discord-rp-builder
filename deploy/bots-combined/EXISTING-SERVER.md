# تشغيل البوتين على خادمك الحالي (مع Enclave-RP-Store والمنصة)

هذا لمن نشر المنصة بالفعل على خادمه الحالي عبر
[`enclave-panel/EXISTING-SERVER.md`](../enclave-panel/EXISTING-SERVER.md)
ويريد إضافة البوتين على نفس الخادم بدل خادم `bots-combined` منفصل. كل
شيء — المتجر والمنصة والبوتان — على صندوق واحد، وبلا حاجة لخادم Oracle
ثانٍ إطلاقًا.

## لماذا هذا آمن على خادم فيه تطبيقان حيّان بالفعل

هذا **ليس** نفس سكربت `setup.sh` المعتاد. ذاك يفترض خادمًا فارغًا: مساره
الافتراضي `/opt/enclave` هو نفس المسار الذي يقع تحته تطبيق المتجر
(`/opt/enclave/app`)، ولو شغّلته هنا فسيمسح المتجر الحيّ عن طريق الخطأ.
هذا السكربت مختلف كليًّا، وبمسارات لا تتقاطع مع أي شيء قائم:

| | المتجر (موجود) | المنصة (إن نُشرت) | بوت Enclave (يضيفه هذا السكربت) | بوت LSPD (يضيفه هذا السكربت) |
|---|---|---|---|---|
| المستخدم | `enclave` | `enclave-admin` | `enclave-admin` (**نفسه**) | `lspd-bot` |
| المجلد | `/opt/enclave/app` | `/opt/enclave-admin` | `/opt/enclave-admin/welcome-bot` | `/opt/lspd-bot` |
| ملف الأسرار | `/etc/enclave.env` | `/etc/enclave-admin.env` | `/etc/enclave-admin-bot.env` | `/etc/lspd-bot.env` |
| خدمة systemd | `enclave.service` | `enclave-admin-panel.service` | `enclave-admin-bot.service` | `lspd-bot.service` |

**السكربت لا يلمس الجدار الناري إطلاقًا** — لا `ufw`، ولا `iptables`. ولا
بوت من الاثنين يفتح منفذًا واردًا أصلًا: خادم الفحص الاختياري داخل كل بوت
لا يعمل إلا إذا كان `PORT` معرَّفًا، وهذا السكربت يتركه فارغًا عمدًا.

Node أيضًا لا يُعاد تثبيته إن وُجد إصدار ٢٠ أو أحدث على الخادم أصلًا.

## لماذا بوت Enclave بمستخدم المنصة نفسه — وبوت LSPD لا

بوت Enclave والمنصة **كانا أصلًا** توأمين على Railway: نفس الخدمة، ونفس
`DISCORD_TOKEN` و`GUILD_ID` (بوت ديسكورد واحد يخدم الاثنين معًا — راجع
`admin-panel/README.md`). ويحتاجان أيضًا مشاركة ملفين على القرص:
`server-events.db` (يكتبه البوت، تقرأه المنصة لعدّاديّ «آخر المغادرين»
و«الأكثر تفاعلًا» بصفحة حالة السيرفر) و`message-templates.json` (تكتبه
المنصة حين يعدّل المالك رسالة الترحيب، يقرأه البوت حين يرسلها). بما أنهما
يتشاركان التوكن نفسه أصلًا، فتشغيلهما بمستخدم لينكس واحد لا يفتح حدود ثقة
جديدة — إنها الحدود نفسها التي كانت قائمة على Railway، فقط بخدمتين
منفصلتين بدل عملية واحدة مدموجة.

بوت LSPD مختلف كليًّا: توكن آخر، سيرفر ديسكورد آخر، ولا بيانات مشتركة مع
أي شيء آخر على هذا الخادم. فله مستخدمه ومجلده وملفه الخاص تمامًا — عزل
كامل، إذ لا شيء يُخسَر بإبعاده عن دائرة ثقة Enclave.

> إن لم تكن نشرت المنصة بعد، لا بأس: يُنشئ هذا السكربت مستخدم
> `enclave-admin` ومجلد `/opt/enclave-admin` بنفسه إن لم يكونا موجودين.
> نشرك للمنصة لاحقًا عبر `install-on-existing-server.sh` الخاص بها سيجد
> المسار جاهزًا ويكمل عليه دون تعارض.

## التشغيل

اتصل بخادمك كما تفعل عادةً:

```bash
ssh -i /path/to/your-key ubuntu@YOUR_SERVER_IP
sudo -i
```

نفّذ:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vzjRR/discord-rp-builder/master/deploy/bots-combined/install-on-existing-server.sh)
```

ثم:

**١) املأ ملفَّي الأسرار — منفصلان بتوكنين مختلفين:**

```bash
nano /etc/enclave-admin-bot.env
nano /etc/lspd-bot.env
```

> ⚠️ **`DISCORD_TOKEN` و`GUILD_ID` في `/etc/enclave-admin-bot.env` يجب أن
> يطابقا ما في `/etc/enclave-admin.env`** (ملف المنصة) — بوت ديسكورد واحد
> لسيرفر Enclave يخدم الاثنين معًا. أما `/etc/lspd-bot.env` فتوكن وسيرفر
> مختلفان تمامًا؛ خلطهما يجعل أحد البوتين يرحّب في السيرفر الخطأ بهوية
> البوت الخطأ.

**٢) شغّلهما:**

```bash
systemctl enable --now enclave-admin-bot lspd-bot
systemctl status enclave-admin-bot lspd-bot --no-pager
journalctl -u enclave-admin-bot -f
```

## تحقّق أن المتجر والمنصة لم يتأثرا

```bash
systemctl status enclave --no-pager              # المتجر ما زال يعمل؟
systemctl status enclave-admin-panel --no-pager   # المنصة ما زالت تعمل؟ (إن نُشرت)
curl -s localhost:3000/api/health                 # المتجر ما زال يردّ؟
```

## ما يحتاجه كل بوت من ديسكورد

لكل واحد على حدة، في Developer Portal الخاص بتطبيقه:

- **Server Members Intent** مفعّلة، وإلا لم يصله حدث انضمام عضو أصلًا.
- صلاحية **Manage Server** في سيرفره، ليقرأ قائمة الدعوات فيعرف من دعا
  العضو الجديد.
- بوت Enclave وحده يحتاج `GuildMessages` أيضًا (لعدّاد النشاط في صفحة
  حالة السيرفر) — غير مميّزة ولا تحتاج تفعيلًا.

## التشغيل اليومي

```bash
cd /opt/enclave-admin && git pull && systemctl restart enclave-admin-bot
cd /opt/lspd-bot && git pull && systemctl restart lspd-bot
journalctl -u enclave-admin-bot -f
```

## ميزة إضافية بهذا الترتيب

بوت Enclave والمنصة على نفس الخادم يعنى صفحة «حالة السيرفر» تعمل
**كاملةً بلا أي نقص** — بعكس نشر البوتين على خادم `bots-combined` منفصل،
حيث تُفقد بيانات «آخر المغادرين» و«الأكثر تفاعلًا» لأنها تعيش في ملف على
خادم آخر لا تراه المنصة.
