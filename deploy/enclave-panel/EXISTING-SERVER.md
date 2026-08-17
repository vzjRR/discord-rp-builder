# تشغيل المنصة على خادمك الحالي (مع Enclave-RP-Store)

هذا لمن يملك خادم أوراكل يعمل عليه بالفعل — تحديدًا سيرفر يشغّل
Enclave-RP-Store — ويريد إضافة منصة الإدارة عليه بدل إنشاء خادم جديد.
لا حاجة لخادم منفصل للمنصة، ولا خطر على المتجر القائم.

## لماذا هذا آمن على خادم فيه تطبيق حيّ

فحصتُ إعداد المتجر (`deploy/enclave.service` و`DEPLOY.md` في مستودعه)
قبل كتابة هذا السكربت، ليكون كل اسم ومسار فيه بلا أي تقاطع معه:

| | المتجر (موجود) | المنصة (يضيفها هذا السكربت) |
|---|---|---|
| المستخدم | `enclave` | `enclave-admin` |
| المجلد | `/opt/enclave/app` | `/opt/enclave-admin` |
| ملف الأسرار | `/etc/enclave.env` | `/etc/enclave-admin.env` |
| خدمة systemd | `enclave.service` | `enclave-admin-panel.service` |
| المنفذ | `3000` (خلف Caddy) | يُكتشف تلقائيًا بدءًا من `3001` |

والأهم: **السكربت لا يلمس الجدار الناري إطلاقًا** — لا `ufw`، ولا
`iptables`، ولا قواعد VCN في أوراكل. المتجر يفتح المنفذين ٨٠ و٤٤٣ لأن
Caddy يستقبل حركة المرور مباشرة؛ أما المنصة فتخرج إلى الإنترنت عبر نفق
Cloudflare — وهو اتصال **صادر** فقط، فلا حاجة لفتح أي منفذ من أجلها،
ولا داعي لأي تغيير في قواعد الجدار التي يعتمد عليها المتجر.

Node أيضًا لا يُعاد تثبيته إن وُجد إصدار ٢٠ أو أحدث على الخادم أصلًا —
وهو ما ثبّته سكربت المتجر نفسه — فتستخدمه المنصة كما هو دون التدخّل في
إعداد Node النظامي الذي يعتمد عليه المتجر.

## التشغيل

اتصل بخادمك كما تفعل عادةً:

```bash
ssh -i /path/to/your-key ubuntu@YOUR_SERVER_IP
sudo -i
```

نفّذ:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vzjRR/discord-rp-builder/master/deploy/enclave-panel/install-on-existing-server.sh)
```

يطبع في نهايته المنفذ الذي اختاره فعليًا (على الأرجح `3001` إن لم يكن
مشغولًا). أكمل من هناك:

**١) املأ الأسرار** — `PORT` فيه مضبوط سلفًا بالقيمة الصحيحة، لا تغيّره
إلا إن غيّرت وجهة نفق Cloudflare معه بنفس الوقت:

```bash
nano /etc/enclave-admin.env
```

**٢) استعد نسخة المنصة الاحتياطية:**

```bash
node /opt/enclave-admin/admin-panel/scripts/restore-backup.js ~/enclave-backup.json /opt/enclave-admin/data
chown -R enclave-admin:enclave-admin /opt/enclave-admin/data
```

**٣) نفق Cloudflare** — إن كان الخادم لا يشغّل نفقًا أصلًا (وهذا متوقّع؛
المتجر يستعمل Caddy لا نفقًا)، أنشئ نفقًا مخصصًا للمنصة من لوحة
Cloudflare: **Zero Trust ← Networks ← Tunnels ← Create a tunnel**، ثم:

```bash
cloudflared service install <الرمز-من-لوحة-Cloudflare>
```

وفي إعداد Public hostname بلوحة Cloudflare، اجعل **Service** يشير إلى
`http://localhost:<المنفذ الذي طبعه السكربت>` — لا `3000`، فذاك للمتجر.

> إن كان الخادم يشغّل نفق Cloudflare بالفعل لسبب آخر، لن يُنشئ السكربت
> نفقًا ثانيًا — سيطبع تنبيهًا بذلك بدل الاستمرار. أضف عندها Public
> hostname جديدًا إلى ذلك النفق القائم يشير إلى المنفذ نفسه.

**٤) شغّل الخدمة:**

```bash
systemctl enable --now enclave-admin-panel
systemctl status enclave-admin-panel --no-pager
journalctl -u enclave-admin-panel -f
```

## تحقّق أن المتجر لم يتأثر

```bash
systemctl status enclave --no-pager     # ما زال يعمل؟
curl -s localhost:3000/api/health       # ما زال يردّ؟
enclave-verify                          # فاحص المتجر الخاص به، إن وُجد
```

## التشغيل اليومي

```bash
cd /opt/enclave-admin && git pull
systemctl restart enclave-admin-panel
journalctl -u enclave-admin-panel -f
```
