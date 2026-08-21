# بوت سيرفر LSPD

بوت واحد لكل ما يخصّ سيرفر LSPD — ترحيب ولوقات معًا، بهوية ديسكورد واحدة
("EN | LSPD BOT#3043")، كل واحد يعمل كعملية Node مستقلة.

| | |
|---|---|
| المجلد | `lspd-welcome-bot/` (ترحيب) + `logs-bot/` (لوقات) |
| الخدمة | `lspd-bot` + `lspd-logs-bot` |
| الأسرار | `/etc/enclave/lspd-bot.env` (يشتركان فيه عمدًا — نفس التوكن) |
| البيانات | لا شيء |

## النشر

الصق `cloud-init.yaml` عند إنشاء الخادم، ثم من Cloud Shell:

```bash
sudo -i
nano /etc/enclave/lspd-bot.env
systemctl enable --now lspd-bot lspd-logs-bot
journalctl -u lspd-bot -f
```

## ⚠️ توكن مستقل

يقرأ `DISCORD_TOKEN` و`GUILD_ID` بالاسمين نفسيهما اللذين يقرأهما بوت
Enclave، **لكنهما لبوت آخر وسيرفر آخر**. ولهذا ملف أسرار مستقل: مشاركة
ملف Enclave تجعله يرحّب في السيرفر الخطأ بالبوت الخطأ.

## ما يحتاجه من ديسكورد

- **Server Members Intent** مفعّلة لبوت LSPD في Developer Portal.
- صلاحية **Manage Server**، ليعرف من دعا العضو الجديد. بدونها يعمل
  الترحيب لكن يظهر كل عضو وكأنه دخل عبر رابط السيرفر العام.

## الأصول

`assets/welcome_template.png` خلفية الترحيب، و`assets/font-bold.ttf` خطها.
الشيفرة تتوقّع قالبًا بمقاس **1536×688**، وموضع الصورة الدائرية للعضو عند
(1211, 338) بنصف قطر 180، ومربّع الاسم بين (190, 375) و(567, 515).
تغيير القالب بمقاس مختلف يستلزم تعديل هذه الأرقام في
`lib/composeWelcomeImage.js`.
