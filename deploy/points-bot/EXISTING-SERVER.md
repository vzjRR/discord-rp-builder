# تشغيل بوت نقاط الصور على خادمك الحالي (مع المنصة)

هذا لمن نشر المنصة بالفعل على خادمه الحالي عبر
[`enclave-panel/EXISTING-SERVER.md`](../enclave-panel/EXISTING-SERVER.md)
(واختياريًا بوت Enclave عبر
[`bots-combined/EXISTING-SERVER.md`](../bots-combined/EXISTING-SERVER.md))
ويريد إضافة بوت نقاط الصور على نفس الخادم. كل شيء على صندوق واحد، وبلا
حاجة لخادم ثانٍ إطلاقًا.

## هذا نفس تطبيق Enclave — ليس تطبيقًا منفصلًا

بوت نقاط الصور **يستخدم نفس `DISCORD_TOKEN`** المستخدم بـ `welcome-bot`/
`logs-bot`/المنصة (تطبيق Enclave، App ID `1535663542420643880`) — نفس ما
يفعله `bots-combined`. Discord يسمح لتوكن واحد يشغّل عدة اتصالات gateway
بالتوازي، فما فيه أي تعارض. لا يحتاج تطبيق ديسكورد جديد ولا توكن جديد.

| | المتجر (موجود) | المنصة (إن نُشرت) | بوت Enclave (إن نُشر) | بوت نقاط الصور (يضيفه هذا السكربت) |
|---|---|---|---|---|
| تطبيق ديسكورد | Enclave-RP-Store | نفس تطبيق Enclave | نفس تطبيق Enclave | **نفس تطبيق Enclave** |
| المستخدم | `enclave` | `enclave-admin` | `enclave-admin` | `enclave-admin` (**نفسه**) |
| المجلد | `/opt/enclave/app` | `/opt/enclave-admin` | `/opt/enclave-admin/welcome-bot` | `/opt/enclave-admin/points-bot` |
| ملف الأسرار | `/etc/enclave.env` | `/etc/enclave-admin.env` | `/etc/enclave-admin-bot.env` | `/etc/enclave-points-bot.env` (**نفس `DISCORD_TOKEN`**) |
| خدمة systemd | `enclave.service` | `enclave-admin-panel.service` | `enclave-admin-bot.service` | `enclave-points-bot.service` |

بوت نقاط الصور يشارك مع المنصة **المستخدم والمجلد ومجلد البيانات** —
عشان `points.db` يقدر كل من البوت (كتابة تلقائية عند كل رسالة فيها صورة)
والمنصة (كتابة يدوية عند تعديل/تصفير نقاط من صلاحية `points.manage`) يوصلون
لنفس الملف مباشرة. ملف الأسرار منفصل عن `/etc/enclave-admin-bot.env` (خدمة
systemd خاصة بها، تُدار وتُعاد تشغيلها لحالها) لكن قيمة `DISCORD_TOKEN`
بداخله نفس القيمة.

**السكربت لا يلمس الجدار الناري إطلاقًا**، ولا يفتح البوت منفذًا واردًا
(البوت gateway فقط — لا يحتاج HTTP على الإطلاق ما لم تنشره على PaaS).

## التشغيل

```bash
ssh -i /path/to/your-key ubuntu@YOUR_SERVER_IP
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/vzjRR/discord-rp-builder/master/deploy/points-bot/install-on-existing-server.sh)
```

**١) املأ ملف الأسرار — نفس `DISCORD_TOKEN` المستخدم بـ `enclave-admin-bot.env`:**

```bash
TOKEN=$(grep -oP '^DISCORD_TOKEN=\K\S+' /etc/enclave-admin-bot.env)
sed -i "s|^DISCORD_TOKEN=.*|DISCORD_TOKEN=${TOKEN}|" /etc/enclave-points-bot.env
```

(لو `enclave-admin-bot.env` غير موجود على هذا الخادم، انسخه من أي ملف أسرار
آخر بنفس تطبيق Enclave — `/etc/enclave-admin.env` أو
`/opt/enclave-admin/logs-bot/.env` كلاهما بنفس التوكن.)

**٢) الصلاحية المميّزة المطلوبة:**

بما إن `logs-bot` بنفس التطبيق يحتاج أصلًا **MESSAGE CONTENT INTENT**، غالبًا
مفعّلة سلفًا. تأكد فقط من https://discord.com/developers/applications →
تطبيق `1535663542420643880` → **Bot** → Privileged Gateway Intents.

**٣) شغّله:**

```bash
systemctl enable --now enclave-points-bot
systemctl status enclave-points-bot --no-pager
journalctl -u enclave-points-bot -f
```

## تحقّق أن المتجر والمنصة وبوت Enclave لم يتأثروا

```bash
systemctl status enclave --no-pager              # المتجر ما زال يعمل؟
systemctl status enclave-admin-panel --no-pager   # المنصة ما زالت تعمل؟
systemctl status enclave-admin-bot --no-pager     # بوت Enclave ما زال يعمل؟ (إن نُشر)
```

## بعد التشغيل — منح صلاحية العرض

النقاط والقراءة تلقائية بالكامل ولا يوجد أي أمر ديسكورد لهذا الموضوع. من
يشوف صفحة "نقاط الصور" بالمنصة يتحكم فيه **المالك وحده**، من صفحة
"إدارة الحسابات" (`/admins`) → اختيار الحساب → الصلاحيات → فعّل
`points.view` (عرض فقط) أو `points.manage` (عرض + تعديل يدوي/تصفير) لأي
حساب تريده.

## التشغيل اليومي

```bash
cd /opt/enclave-admin && git pull && systemctl restart enclave-points-bot
journalctl -u enclave-points-bot -f
```

نفس `git pull` يحدّث المنصة أيضًا (نفس الـ checkout) — أعد تشغيل
`enclave-admin-panel` بعده لو عدّلت شيئًا يخص المنصة نفسها.
