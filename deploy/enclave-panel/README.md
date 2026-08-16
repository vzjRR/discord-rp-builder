# منصة الإدارة — Enclave

الواجهة التي يدير بها المسؤولون السيرفر. الخدمة الوحيدة التي تحتاج وصولًا
من الخارج، ويصلها عبر نفق Cloudflare لا عبر منفذ مفتوح.

| | |
|---|---|
| المجلد | `admin-panel/` |
| الخدمة | `enclave-panel` |
| الأسرار | `/etc/enclave/panel.env` |
| البيانات | `/data/admin.db` و`/data/server-events.db` |
| المنفذ | `3000` محليًّا فقط |

## النشر

الصق `cloud-init.yaml` عند إنشاء الخادم، ثم من Cloud Shell:

```bash
sudo -i
nano /etc/enclave/panel.env
```

**`SESSION_SECRET` يجب أن يبقى كما كان على الاستضافة السابقة.** تغييره
يُبطل جلسات كل المسؤولين فيُطالَبون بالدخول من جديد. وإن لم تعرفه فولّد
غيره واقبل بذلك — لا ضرر عدا إعادة الدخول.

ثم استعد بياناتك (ارفع ملف النسخة عبر زرّ الرفع في Cloud Shell):

```bash
node /opt/enclave/admin-panel/scripts/restore-backup.js ~/enclave-backup.json /data
chown -R enclave:enclave /data
```

السكربت يتحقق من بصمة كل ملف قبل كتابته، ويرفض الكتابة فوق موجود إلا
بـ `--force`.

ثم النفق والتشغيل:

```bash
cloudflared service install <رمز-النفق>
systemctl enable --now enclave-panel
journalctl -u enclave-panel -f
```

## ملاحظة

تقرأ `/data/server-events.db` الذي يكتبه بوت Enclave. فإن نُشرا على
خادمين مختلفين عملت المنصة كاملةً عدا «آخر المغادرين» و«الأكثر تفاعلًا».
