# Discord RP Builder — دليل الاستخدام من الألف للياء

سكربت Node.js يبني هيكل السيرفر (الرولات → الأقسام → القنوات) تلقائيًا عبر Discord API،
اعتمادًا على `Discord Server Architecture.md`. **آمن للسيرفر الموجود عندك**: كل عملية تتحقق أولًا
هل الرول/الكاتيجوري/القناة موجودة بالاسم، وإذا موجودة يتخطاها — فما راح يكرر ولا يحذف شيء.

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

بعكس `build.js` اللي يشتغل مرة وحدة ويطلع، هذا بوت **يبقى شغّال باستمرار** ويرد على كل عضو جديد لحظة دخوله.

### أ) فعّل الصلاحية المطلوبة (خطوة إلزامية، مرة وحدة)

1. روح https://discord.com/developers/applications → افتح تطبيقك (`RP Builder`) → **Bot**.
2. تحت **Privileged Gateway Intents** فعّل: **SERVER MEMBERS INTENT** ✅
3. احفظ.

بدون هذي الخطوة، حدث "عضو جديد انضم" ما يوصل للبوت أبدًا ولو الكود صحيح 100%.

### ب) صمّم رسالة الترحيب

افتح `config/welcome.js` وعدّل:
- `title` / `description` / `footer` — النص، تقدر تستخدم `{member}` `{memberCount}` `{serverName}` `{rulesChannel}`.
- `color` — لون شريط الرسالة.
- `bannerImagePath` — لو عندك تصميم بانر خاص بك (PNG/JPG)، حطه بمجلد `assets/` وأشّر لمساره هنا، مثلاً:
  ```js
  bannerImagePath: './assets/welcome-banner.png',
  ```
- `autoAssignRole` — الرول اللي يُعطى تلقائيًا للعضو الجديد (افتراضيًا `⏳ Pending Verification`). خليه `null` لو ما تبي إعطاء رول تلقائي.
- `sendDM` — `true` لو تبي رسالة خاصة كمان بالإضافة لرسالة القناة.

### ج) شغّله

```bash
node welcome-bot.js
```

اترك الترمنال مفتوح — هذا طبيعي، البوت لازم يبقى شغّال عشان يرد. جرّبه بحساب ثاني (أو خلي صديق) ينضم للسيرفر وشوف النتيجة بقناة `👋・welcome`.

### د) التشغيل الدائم (يوم ينتقل لـ VPS)

على جهازك الشخصي الحين، البوت يشتغل بس وقت الترمنال مفتوح. لما تنتقل لـ VPS لاحقًا، شغّله بأداة زي [pm2](https://pm2.keymetrics.io) عشان يبقى شغّال حتى لو أعدت تشغيل السيرفر:

```bash
npm install -g pm2
pm2 start welcome-bot.js --name welcome-bot
pm2 save
pm2 startup   # يطبع لك أمر تشغّله مرة وحدة عشان يبدأ تلقائيًا مع تشغيل الجهاز
```

### بديل: بوتات جاهزة (بدون كود إطلاقًا)

لو حاب تجرب بدون تشغيل أي شي بنفسك، فيه بوتات عامة جاهزة تعمل نفس الفكرة بإعدادات Dashboard فقط (بدون كود، وهي مستضافة عندهم مو عندك):
- **Welcomer** (welcomer.gg) — يدعم بانرات ترحيب مصممة بصورة العضو تلقائيًا.
- **MEE6** (mee6.xyz) — رسائل ترحيب + رولات تلقائية.

الفرق: هذي بوتات طرف ثالث (بياناتهم عندهم مو عندك)، وميزاتها المتقدمة غالبًا مدفوعة. البوت المخصص اللي بنيناه مجاني بالكامل وتتحكم فيه 100%.

---

## 7) بعد الانتهاء

- اسحب صلاحية `Administrator` من رول البوت وأبقِ فقط `Manage Roles` + `Manage Channels` إذا بتحتاجه لاحقًا لأتمتة أخرى (تسجيل، تذاكر...).
- راجع Permission Matrix بالدوكيومنت وقارنها بالنتيجة الفعلية على الأقسام الحساسة (Police / CIA / Security & Logs) قبل ما تفتح السيرفر للأعضاء.
- اربط لاحقًا Verification Bot / Ticket Bot / Moderation Bot حسب قسم "Bot Architecture" بالدوكيومنت — هذا السكربت يبني الهيكل فقط، مو منطق البوتات التشغيلية.
