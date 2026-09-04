# Discord RP Builder — دليل الاستخدام من الألف للياء

سكربت Node.js يبني هيكل السيرفر (الرولات → الأقسام → القنوات) تلقائيًا عبر Discord API،
اعتمادًا على `Discord Server Architecture.md`. **آمن للسيرفر الموجود عندك**: كل عملية تتحقق أولًا
هل الرول/الكاتيجوري/القناة موجودة بالاسم، وإذا موجودة يتخطاها — فما راح يكرر ولا يحذف شيء.

## هيكل المستودع — ثلاث قطع مستقلة تمامًا

```
discord-rp-builder/         ← أدوات بناء السيرفر (تشتغل مرة وتطلع، مو بوت دائم): build.js, organization.js, export.js
├── logs-bot/                ← مشروع Node مستقل، package.json خاص فيه — لوقات security-logs + أوامر رولات
├── welcome-bot/              ← مشروع Node مستقل، package.json خاص فيه — رسالة الترحيب للأعضاء الجدد
├── points-bot/               ← مشروع Node مستقل، package.json خاص فيه — نقاط الصور التلقائية (بلا أي أوامر، راجع points-bot/README.md)
└── admin-panel/              ← منصة الإدارة (Express) — لوحة صدارة نقاط الصور جزء منها بصفحة /points
```

كل مجلد فيه `package.json` و `.env.example` خاص فيه — `npm install` و `npm start` تسويها **داخل كل مجلد لحاله**،
مو من الجذر. الثلاثة يستخدمون نفس `DISCORD_TOKEN` و `GUILD_ID` (نفس تطبيق Discord)، لكنها عمليات Node منفصلة
تمامًا — تقدر تنشر `logs-bot/` و `welcome-bot/` كخدمتين منفصلتين على Railway (كل وحدة بـ Root Directory خاص فيها)،
وتوقف/تعيد تشغيل وحدة بدون ما تأثر على الثانية.

---

## 0) قبل ما تبدأ

- تأكد إن عندك **نسخة احتياطية** أو على الأقل **صورة كاملة** لهيكل السيرفر الحالي (سكرين شوت لقائمة الرولات والقنوات كافي كحد أدنى).
- الأفضل: جرّب السكربت أول مرة على **سيرفر تجريبي فاضي** (Server جديد تسويه بضغطة واحدة) عشان تشوف الشكل النهائي قبل ما تطبّقه على سيرفرك الحقيقي.

---

## 1) تجهيز البوت (مرة وحدة فقط)

1. روح إلى https://discord.com/developers/applications
2. **New Application** → سمّه مثلاً `RP Builder`
3. من القائمة الجانبية **Bot** → **Add Bot**
4. فعّل (Privileged Gateway Intents) — السكربت يحتاج فقط `Server Members Intent` إذا نويت تطويره لاحقًا، لكن للبناء الحالي غير مطلوب، اتركها كما هي.
5. اضغط **Reset Token** وانسخ الـ Token (بيُطلب مرة وحدة، خزّنه بمكان آمن).
6. من القائمة الجانبية **OAuth2 → URL Generator**:
   - Scopes: `bot`
   - Bot Permissions: `Administrator` (الأسهل والأضمن أثناء البناء — تقدر تسحبها بعدين من رول البوت)
7. انسخ الرابط الناتج بالأسفل وافتحه بالمتصفح، اختر سيرفرك، وادعُ البوت.
8. **مهم جدًا**: روح لسيرفرك → Server Settings → Roles → اسحب رول البوت (`RP Builder`) لأعلى القائمة، **فوق كل الرولات** ما عدا رولك الشخصي كـ Owner. لو رول البوت تحت، ما راح يقدر ينشئ/يعدّل رولات فوقه.

### الحصول على Server ID
فعّل **Developer Mode**: User Settings → Advanced → Developer Mode → ON
ثم كليك يمين على اسم السيرفر → **Copy Server ID**.

---

## 2) تجهيز الجهاز

يحتاج [Node.js](https://nodejs.org) نسخة 18 أو أحدث. تأكد بكتابة:

```bash
node --version
```

ثم داخل مجلد المشروع:

```bash
npm install
```

هذا يثبّت `discord.js` و `dotenv`.

---

## 3) تعبئة بيانات الاتصال

انسخ `.env.example` باسم `.env` واملأه:

```
DISCORD_TOKEN=التوكن_من_الخطوة_1
GUILD_ID=آيدي_السيرفر
```

**لا ترفع ملف `.env` لأي مكان عام (GitHub وغيره) — فيه توكن البوت الكامل.**

---

## 4) شغّل البناء — بالترتيب الصحيح

### أ) الرولات أولًا (دايمًا أول خطوة)

```bash
node build.js roles
```

ينشئ كل الرولات الناقصة (Owner, Executive, Police Chief... إلخ) بنفس ترتيب `Role Hierarchy` في الدوكيومنت.
الرولات الموجودة عندك بنفس الاسم بالضبط يتم تخطيها.

بعدها **راجع يدويًا** ترتيب الرولات في Server Settings → Roles، وتأكد إنها متسلسلة حسب القسم "Role Hierarchy النهائي" بالدوكيومنت (السكربت ينشئها لكن لا يضمن ترتيبها 100% إذا كان عندك رولات قديمة بينها).

### ب) الأقسام والقنوات — قسم قسم (الأسلوب المُوصى به لسيرفر موجود)

بدل ما تبني كل شي دفعة وحدة، انتقل تدريجيًا. اعرض المفاتيح المتاحة:

```bash
node build.js list
```

راح تشوف قائمة زي:

```
- start-here              📌 START HERE
- community                💬 COMMUNITY
- player-center            🎮 PLAYER CENTER
- applications              📝 APPLICATIONS
- support-center            🎫 SUPPORT CENTER
- server-services            🛒 SERVER SERVICES
- city-life                🏙️ CITY LIFE
- businesses                🏢 BUSINESSES
- government                🏛️ GOVERNMENT
- police                    🚔 POLICE DEPARTMENT
- ems                       🏥 EMS / MEDICAL
- moj                       ⚖️ MINISTRY OF JUSTICE
- cia                       🕵️ CIA
- criminal-organizations    🕶️ CRIMINAL ORGANIZATIONS
- events                    🎉 EVENTS
- reports-appeals           🚨 REPORTS & APPEALS
- staff-center              🛡️ STAFF CENTER
- management                👑 MANAGEMENT
- development                💻 DEVELOPMENT
- design-creative            🎨 DESIGN & CREATIVE
- qa-testing                🧪 QA / TESTING
- security-logs              🔐 SECURITY & LOGS
- bot-system                 🤖 BOT SYSTEM
- voice-lounge                🔊 VOICE LOUNGE
```

ثم ابنِ قسم واحد فقط في كل مرة، مثلًا ابدأ بالأقسام العامة أولًا:

```bash
node build.js categories start-here
node build.js categories community
node build.js categories player-center
```

بعد ما تتأكد كل قسم طلع صح، انتقل للي بعده. القنوات الحساسة (police, ems, moj, cia, staff-center, management, security-logs)
سوّها آخر شي بعد ما تتأكد الرولات المطلوبة لها موجودة فعلًا (مثلاً `🚔 Police Officer` لازم يكون موجود قبل ما تبني قسم `police`،
وهذا صار تلقائيًا لو نفذت خطوة "أ" فوق).

### ج) أو: كل شي دفعة وحدة (لسيرفر جديد فاضي)

```bash
node build.js all
```

---

## 5) المنظمات الإجرامية (ديناميكي، حسب الحاجة)

بدل إنشاء عصابات دائمة، شغّل هذا الأمر كل ما تتم الموافقة على منظمة جديدة:

```bash
node organization.js "Los Santos Cartel"
```

راح ينشئ لها رول خاص + كاتيجوري خاصة (chat / announcements / management / operations + صوت)
تظهر فقط لأعضائها وللـ Staff. أعطِ الرول الناتج (`🔒 Org: Los Santos Cartel`) لأعضاء المنظمة يدويًا من داخل Discord.

---

## 6) تخصيص الصلاحيات أو الأسماء

كل شي مركزي بثلاث ملفات:

- `config/roles.js` — قائمة الرولات، الألوان، صلاحيات Discord لكل رول
- `config/constants.js` — تجميعات الرولات (MANAGEMENT_UP, STAFF_UP, POLICE...) المستخدمة في الأقسام
- `config/categories.js` — كل قسم وقنواته، ومين يشوف/يكتب في كل قناة

عدّل القيم، احفظ، وشغّل `node build.js categories <key>` من جديد — القنوات الموجودة تبقى كما هي،
وأي قناة جديدة أضفتها بالكونفج تُنشأ تلقائيًا.

> ⚠️ السكربت لا يعدّل صلاحيات قناة موجودة مسبقًا حتى لو غيّرت الكونفج — فقط ينشئ الناقص.
> إذا تبي تحدّث صلاحيات قناة قديمة، سوّيها يدويًا من Discord أو احذف القناة وشغّل السكربت من جديد لينشئها بالصلاحيات الجديدة.

---

## 6.5) بوت الترحيب التلقائي (Welcome Bot)

مشروع مستقل بمجلد `welcome-bot/` — له `package.json` خاص فيه، ينفصل تمامًا عن أدوات البناء وعن `logs-bot/`.
بعكس `build.js` اللي يشتغل مرة وحدة ويطلع، هذا بوت **يبقى شغّال باستمرار** ويرد على كل عضو جديد لحظة دخوله.

### أ) فعّل الصلاحية المطلوبة (خطوة إلزامية، مرة وحدة)

1. روح https://discord.com/developers/applications → افتح تطبيقك (`RP Builder`) → **Bot**.
2. تحت **Privileged Gateway Intents** فعّل: **SERVER MEMBERS INTENT** ✅
3. احفظ.

بدون هذي الخطوة، حدث "عضو جديد انضم" ما يوصل للبوت أبدًا ولو الكود صحيح 100%.

### ب) جهّز المجلد (مرة وحدة)

```bash
cd welcome-bot
npm install
cp .env.example .env   # واملأ نفس DISCORD_TOKEN و GUILD_ID المستخدمين ببقية المشروع
```

### ج) صمّم رسالة الترحيب

افتح `welcome-bot/config/welcome.js` وعدّل:
- `title` / `description` / `footer` — النص، تقدر تستخدم `{member}` `{memberCount}` `{serverName}` `{rulesChannel}`.
- `color` — لون شريط الرسالة.
- `bannerImagePath` — لو عندك تصميم بانر خاص بك (PNG/JPG)، حطه بمجلد `welcome-bot/assets/` وأشّر لمساره هنا، مثلاً:
  ```js
  bannerImagePath: './assets/welcome-banner.png',
  ```
- `autoAssignRole` — الرول اللي يُعطى تلقائيًا للعضو الجديد (افتراضيًا `⏳ Pending Verification`). خليه `null` لو ما تبي إعطاء رول تلقائي.
- `sendDM` — `true` لو تبي رسالة خاصة كمان بالإضافة لرسالة القناة.

### د) شغّله محليًا (للتجربة)

```bash
cd welcome-bot
npm start
```

> ⚠️ **لازم `npm start` مو `node bot.js`.** السكربت يضبط `FONTCONFIG_PATH` قبل ما تبدأ العملية،
> وبدونه النصوص على الصورة تنرسم بخط احتياطي غلط. البوت يطبع تحذير واضح لو صار هذا.

للاختبار بدون ما ترسل شي لديسكورد:

```bash
npm test             # يشغّل test:names + test:templates مع بعض
npm run test:image   # يركّب الصورة لعضو ويحفظها بـ test-output.png
npm run test:names   # يفحص رسم الأسماء (عربي/مختلط/إيموجي/رياضي/عريض) بدون اتصال بديسكورد
npm run test:templates  # يفحص قوالب الرسائل وروابط القنوات
npm run dry-run      # محاكاة دخول عضو كاملة: يفحص القنوات والرول ويطبع الرسالة
```

`test:names` هو حارس الانحدار للأسماء — يتأكد إن الحروف العربية تتوصل فعلًا وإن الإيموجي
ما تطلع مربعات، ويحفظ صور معاينة بـ `test-names-output/`. شغّله بعد أي تعديل على الخطوط
أو على `composeWelcomeImage.js`. و`test:templates` يمسك أي متغيّر `{...}` ما ينتعبّى.

### هـ) التشغيل الدائم — Railway (الوضع الحالي)

البوت منشور كخدمة `welcome-bot` بمشروع `discord-rp-builder` على Railway، وشغّال ٢٤/٧
بشكل مستقل تمامًا عن جهازك.

**النشر تلقائي:** الخدمة مربوطة بفرع `master` من هذا المستودع — أي `git push` ينشر نسخة جديدة
لحاله بدون أي أمر منك.

الإعدادات اللي تخلّيه يشتغل:

| الإعداد | القيمة | ليه |
|---|---|---|
| `railway.json` | `cd welcome-bot && npm start` | بدونه Railway ينشر من جذر المستودع ويشغّل `build.js` بالغلط |
| `NIXPACKS_NODE_VERSION` | `22` | Node 18 الافتراضي ما يقدر يحمّل sharp 0.35 |
| `DISCORD_TOKEN` / `GUILD_ID` | متغيرات على الخدمة | ملف `.env` مستثنى من git عمدًا |

**الخطوط:** `assets/fonts/` فيها Barlow + Noto (Arabic / Emoji / Sans / Math) وكلها مرفوعة مع الكود.
ما نعتمد على خطوط النظام إطلاقًا لأن Railway لينكس. البوت يطبع عند التشغيل سطر تحقّق:

```
🔤 الخطوط المدمجة تمام (Barlow=317x41 NotoSans=364x44 عربي=147x63 وصل=0.64)
```

لو طلع `❌ الخطوط المدمجة ما انحمّلت` معناها `FONTCONFIG_PATH` مو مضبوط والنصوص بتطلع غلط.

> ⚠️ **ترتيب `FONT_STACK` مو عشوائي.** لازم `'Noto Naskh Arabic'` يجي **قبل** `'Noto Sans Math'`.
> السبب إن Noto Sans Math يغطي الحروف العربية المفردة بس بدون جداول الوصل، فلو جا أول
> يختاره Pango للعربي وتطلع الأسماء حروف مفكّكة (مثال حقيقي: `azبانيذا` انرسمت `azاذيناب`).
> السطر `وصل=` بفحص التشغيل يمسك هذا بالضبط: لازم يكون **أقل من 0.8**، ولو قرب من `1.04`
> معناها الترتيب انكسر. و`npm run test:names` يفشل فورًا بنفس الحالة.

**الإيموجي أحادية اللون بشكل مقصود.** cairo اللي جوّا sharp يرسم خطوط الإيموجي الملوّنة
(NotoColorEmoji بصيغة CBDT) كقناع alpha يتعبّى بلون النص — يعني ما تطلع ملوّنة أصلًا،
وفوق كذا تطلع أطول من السطر (١١٨px مقابل ٦٦) وتزحلق تنسيق الاسم. عشان كذا نستخدم
`NotoEmoji` الأحادي (٢MB بدل ١٠MB): رسمه نظيف، بنفس وزن النص، ويلتقط التوهّج البنفسجي.

**روابط رسالة الخاص:** داخل الـ DM استخدم `{welcomeChannelUrl}` مو `{welcomeChannel}`.
النسخة القديمة كانت تكتب اسم القناة كنص عادي فما ينضغط أبدًا، ومنشن `<#id>` نتيجته
تعتمد على العميل وعلى عضوية المستخدم بالسيرفر — أما الرابط الكامل
`discord.com/channels/<guild>/<channel>` فمضمون ينضغط وينقل العضو مباشرة بكل الحالات.

**متابعة الحالة:**

```bash
railway status              # Online / Crashed
railway logs --deployment   # لوقات آخر نشرة
```

**بديل VPS** بدل Railway — استخدم [pm2](https://pm2.keymetrics.io) مع نفس شرط `npm start`:

```bash
cd welcome-bot
npm install -g pm2
pm2 start npm --name welcome-bot -- start
pm2 save
pm2 startup   # يطبع لك أمر تشغّله مرة وحدة عشان يبدأ تلقائيًا مع تشغيل الجهاز
```

### بديل: بوتات جاهزة (بدون كود إطلاقًا)

لو حاب تجرب بدون تشغيل أي شي بنفسك، فيه بوتات عامة جاهزة تعمل نفس الفكرة بإعدادات Dashboard فقط (بدون كود، وهي مستضافة عندهم مو عندك):
- **Welcomer** (welcomer.gg) — يدعم بانرات ترحيب مصممة بصورة العضو تلقائيًا.
- **MEE6** (mee6.xyz) — رسائل ترحيب + رولات تلقائية.

الفرق: هذي بوتات طرف ثالث (بياناتهم عندهم مو عندك)، وميزاتها المتقدمة غالبًا مدفوعة. البوت المخصص اللي بنيناه مجاني بالكامل وتتحكم فيه 100%.

### و) قناة صفر تسامح (Zero-Tolerance Channel)

نفس عملية welcome-bot (`lib/zeroTolerance.js`)، تعمل بشكل مستقل تمامًا عن الترحيب والتتبّع: أي رسالة
تُنشر في القناة المحدّدة بـ `welcome-bot/config/zeroTolerance.js` (نص، صورة، إيموجي، أي شيء) تطرد
كاتبها فورًا بدون أي تحذير، بغض النظر عن رتبته.

- **أول وثاني مخالفة لنفس العضو → طرد (Kick).** يقدر يرجع ينضم للسيرفر.
- **ثالث مخالفة → حظر دائم (Ban).**

عدّاد المخالفات يُحفظ بقاعدة SQLite منفصلة صغيرة (`/data/zero-tolerance.db` افتراضيًا، أو
`ZERO_TOLERANCE_DB_PATH` لو تبي مسار مختلف) فيبقى محفوظًا عبر إعادة التشغيل وحتى لو العضو غادر
وعاد. الميزة معطّلة افتراضيًا: خلّي `channelId` بالملف فاضيًا أو `null` لتعطيلها.

**متطلبات إلزامية:**
1. صلاحيتا **Kick Members** و**Ban Members** للبوت بالسيرفر.
2. رول البوت لازم يكون **أعلى** من كل رتبة تريد لهذه الميزة أن تطالها فعليًا — ديسكورد نفسه يرفض
   لأي بوت طرد/حظر مالك السيرفر، أو أي عضو رتبته الأعلى بمستوى مساوٍ أو أعلى من رتبة البوت، بغض
   النظر عن أي صلاحيات ممنوحة له. لو رول شخص أعلى من رول البوت، الميزة لن تنجح ضده مهما كانت الإعدادات.

لتغيير القناة المستهدفة، عدد المخالفات قبل الحظر، أو نص إشعار الطرد/الحظر: عدّل مباشرة بـ
`welcome-bot/config/zeroTolerance.js`.

---

## 6.6) بوت اللوقات (Logs Bot)

مشروع مستقل بمجلد `logs-bot/` — له `package.json` خاص فيه، ينفصل تمامًا عن welcome-bot وعن أدوات البناء.
يبقى شغّال باستمرار (زي welcome-bot، بعكس `build.js`) ويكتب بقنوات قسم **🔐 SECURITY & LOGS**
(`join-log`, `leave-log`, `member-log`, `moderation-log`, `punishment-log`, `audit-log`, `bot-log`, `security`)،
ويوفر أوامر سلاش لإدارة الرولات: `/role-create` `/role-list` `/role-delete`.

### أ) صلاحيتان إلزاميتان (مرة وحدة)

1. **Message Content Intent** — https://discord.com/developers/applications → تطبيقك → **Bot** → Privileged Gateway Intents
   → فعّل **MESSAGE CONTENT INTENT** ✅ (بدونها ما يظهر نص الرسائل المحذوفة/المعدّلة بـ `moderation-log`).
2. **صلاحيات رول 🤖 Bot** — روح Server Settings → Roles → `🤖 Bot` بسيرفرك، وفعّل يدويًا:
   - **Manage Roles** (لازمة لـ `/role-create` و `/role-delete`)
   - **View Audit Log** (لازمة لمعرفة "مين نفّذ الإجراء" بـ `audit-log` و `punishment-log`)

   ⚠️ هذي خطوة يدوية إلزامية — `config/roles.js` بجذر المستودع يعرّف هالصلاحيات للرول، لكن `build.js` ما يعدّل
   رولات موجودة مسبقًا، فلازم تضيفها بنفسك من Discord مباشرة لو الرول already موجود بسيرفرك.
   وتأكد إن رول البوت لسا فوق كل الرولات اللي بيديره (نفس الملاحظة بخطوة 1.8 فوق).

### ب) جهّز المجلد وشغّله

```bash
cd logs-bot
npm install
cp .env.example .env   # نفس DISCORD_TOKEN و GUILD_ID المستخدمين ببقية المشروع
npm start
```

### ج) سجّل أوامر السلاش (مرة وحدة، وبعدها كل ما تعدّل commands/role.js)

```bash
cd logs-bot
npm run deploy-commands
```

هذا يسجّل `/role-create` `/role-list` `/role-delete` مباشرة بسيرفرك (guild-scoped) — يظهرون فورًا بدون انتظار.

### د) تخصيص أو تعطيل نوع لوق معيّن

كل شي بملف `logs-bot/config/logs.js` — لكل نوع `enabled` (شغّل/عطّل)، `channel` (لازم يطابق اسم القناة
بالضبط بـ `config/categories.js` بجذر المستودع)، و`color`. `ticket-log` و `report-log` معطّلة افتراضيًا
لعدم وجود نظام تذاكر/بلاغات بعد بالمشروع.

### هـ) النشر على Railway كخدمة منفصلة

سوّي خدمة Railway جديدة بنفس المستودع، وحطّ **Root Directory** = `logs-bot`. حط نفس `DISCORD_TOKEN` و `GUILD_ID`
بمتغيرات البيئة الخاصة بهالخدمة. هذي الخدمة تُبنى وتُعاد تشغيلها بشكل مستقل تمامًا عن welcome-bot.

---

## 6.7) بوت نقاط الصور (Points Bot)

مشروع مستقل بمجلد `points-bot/` — له `package.json` خاص فيه، وله تطبيق ديسكورد
منفصل تمامًا عن الثلاثة أعلاه (نفس تطبيق `EN-Censorship`، لا يشارك `DISCORD_TOKEN`
مع `build.js`/`logs-bot`/`welcome-bot`). يراقب قناة واحدة محددة ويحتسب نقطة تلقائية
لكل رسالة فيها صورة — **بلا أي أمر ديسكورد إطلاقًا**، لا slash ولا نصي. كل القراءة
والتعديل اليدوي تتم من `admin-panel` (صفحة "نقاط الصور"، صلاحيتا `points.view`
و`points.manage` يمنحهما المالك من صفحة "إدارة الحسابات").

التفاصيل الكاملة (القاعدة الحسابية، متغيرات البيئة، تشغيل محلي) بـ
[`points-bot/README.md`](points-bot/README.md)، والنشر على السيرفر بـ
[`deploy/points-bot/EXISTING-SERVER.md`](deploy/points-bot/EXISTING-SERVER.md).

---

## 7) بعد الانتهاء

- اسحب صلاحية `Administrator` من رول البوت وأبقِ فقط `Manage Roles` + `Manage Channels` إذا بتحتاجه لاحقًا لأتمتة أخرى (تسجيل، تذاكر...).
- راجع Permission Matrix بالدوكيومنت وقارنها بالنتيجة الفعلية على الأقسام الحساسة (Police / CIA / Security & Logs) قبل ما تفتح السيرفر للأعضاء.
- اربط لاحقًا Verification Bot / Ticket Bot / Moderation Bot حسب قسم "Bot Architecture" بالدوكيومنت — هذا السكربت يبني الهيكل فقط، مو منطق البوتات التشغيلية.
