# تشغيل بوت نقاط الصور على خادمك الحالي (مع المنصة)

هذا لمن نشر المنصة بالفعل على خادمه الحالي عبر
[`enclave-panel/EXISTING-SERVER.md`](../enclave-panel/EXISTING-SERVER.md)
(واختياريًا بوت Enclave عبر
[`bots-combined/EXISTING-SERVER.md`](../bots-combined/EXISTING-SERVER.md))
ويريد إضافة بوت نقاط الصور على نفس الخادم. كل شيء على صندوق واحد، وبلا
حاجة لخادم ثانٍ إطلاقًا.

## هذا تطبيق ديسكورد مختلف تمامًا

⚠️ **بوت نقاط الصور ليس نفس بوت Enclave.** المتجر والمنصة وبوت Enclave
(`welcome-bot`) يتشاركون `DISCORD_TOKEN` واحد. بوت نقاط الصور تطبيق ديسكورد
منفصل بالكامل — **EN-Censorship** (App ID `1544434302308319293`) — بتوكنه
الخاص. لا تضع توكن الـ Enclave هنا، ولا العكس.

| | المتجر (موجود) | المنصة (إن نُشرت) | بوت Enclave (إن نُشر) | بوت نقاط الصور (يضيفه هذا السكربت) |
|---|---|---|---|---|
| تطبيق ديسكورد | Enclave-RP-Store | نفس تطبيق Enclave | نفس تطبيق Enclave | **EN-Censorship (منفصل)** |
| المستخدم | `enclave` | `enclave-admin` | `enclave-admin` | `enclave-admin` (**نفسه**) |
| المجلد | `/opt/enclave/app` | `/opt/enclave-admin` | `/opt/enclave-admin/welcome-bot` | `/opt/enclave-admin/points-bot` |
| ملف الأسرار | `/etc/enclave.env` | `/etc/enclave-admin.env` | `/etc/enclave-admin-bot.env` | `/etc/enclave-points-bot.env` |
| خدمة systemd | `enclave.service` | `enclave-admin-panel.service` | `enclave-admin-bot.service` | `enclave-points-bot.service` |

بوت نقاط الصور يشارك مع المنصة **المستخدم والمجلد ومجلد البيانات فقط** —
عشان `points.db` يقدر كل من البوت (كتابة تلقائية عند كل رسالة فيها صورة)
والمنصة (كتابة يدوية عند تعديل/تصفير نقاط من صلاحية `points.manage`) يوصلون
لنفس الملف مباشرة. لا يشارك التوكن ولا يشارك أي صلاحية إدارة سيرفر.

**السكربت لا يلمس الجدار الناري إطلاقًا**، ولا يفتح البوت منفذًا واردًا
(البوت gateway فقط — لا يحتاج HTTP على الإطلاق ما لم تنشره على PaaS).

## التشغيل

```bash
ssh -i /path/to/your-key ubuntu@YOUR_SERVER_IP
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/vzjRR/discord-rp-builder/master/deploy/points-bot/install-on-existing-server.sh)
```

**١) املأ ملف الأسرار (توكن EN-Censorship، ليس توكن Enclave):**

```bash
nano /etc/enclave-points-bot.env
```

**٢) فعّل الصلاحية المميّزة المطلوبة:**

في https://discord.com/developers/applications → تطبيق `1544434302308319293`
→ **Bot** → Privileged Gateway Intents → فعّل **MESSAGE CONTENT INTENT** ✅.
بدونها attachments/embeds ما توصل مع أحداث رسائل الأعضاء (غير-بوت) إطلاقًا.

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
