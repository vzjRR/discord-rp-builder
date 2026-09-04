# شرح الإعدادات

كل ما يلي في `config/config.lua` ما لم يُذكر غير ذلك.

---

## اللغة والاكتشاف

| الخيار | الافتراضي | الشرح |
|---|---|---|
| `Config.Locale` | `'ar'` | لازم يوجد `locales/<القيمة>.json` |
| `Config.Framework` | `'auto'` | `auto`/`qbx`/`qb`/`esx`/`standalone` |
| `Config.Inventory` | `'auto'` | `auto`/`ox`/`qb`/`esx`/`none` |
| `Config.Target` | `'auto'` | `auto`/`ox`/`qb` |
| `Config.UseDatabase` | `true` | `false` = كل شيء في الذاكرة ويضيع عند الريستارت |

> غيّر `auto` فقط لو الاكتشاف فشل. القيمة المكتشفة تظهر في الكونسول عند التشغيل.

---

## الوظيفة

```lua
Config.Job.name = 'icecream'     -- لازم يطابق اسم الوظيفة عند فريمويركك بالحرف
Config.Job.hireGrade = 0         -- رتبة التوظيف من منيو البوس
Config.Job.maxPromoteGrade = 3   -- أعلى رتبة يقدر البوس يعطيها (يمنع صنع بوسات)
```

### الرتب والصلاحيات
كل رتبة جدول فيه خمس صلاحيات:

| الصلاحية | تفتح |
|---|---|
| `canCraft` | محطات العمل |
| `canRegister` | الكاشير، الطلبات، الفوترة |
| `canFreezer` | فتح الفريزر |
| `canSupply` | المورّد وجولة التوريد |
| `isBoss` | منيو الإدارة |

لإضافة رتبة سادسة: أضف `[5] = {...}` هنا **وأضفها عند فريمويركك أيضًا**، وأضف
راتبها في `Config.Paycheck.amounts[5]`.

| الخيار | الافتراضي | الشرح |
|---|---|---|
| `Config.RequireDuty` | `true` | `false` = كل الميزات تشتغل لأي موظف بلا دوام |
| `Config.BlockOffDutyWithStock` | `false` | يمنع الخروج من الدوام وهو حامل منتجات المحل |

---

## الاقتصاد

```lua
Config.Economy.playerAccount = 'bank'   -- وين يستلم الموظف بقشيشه: cash أو bank
Config.Economy.billAccount   = 'bank'   -- من وين يدفع الزبون فاتورته
Config.Economy.societyShare  = 0.75     -- نصيب الشركة
Config.Economy.employeeTip   = 0.25     -- بقشيش الموظف
Config.Economy.maxTipPerOrder = 250     -- سقف البقشيش للطلب الواحد
Config.Economy.startingBalance = 25000  -- رصيد أول تشغيل فقط
Config.Economy.allowNegativeBalance = false
```

> ⚠️ `societyShare + employeeTip` **لازم يساوي 1.0** — المورد يحذّرك في الكونسول لو لا.
> `maxTipPerOrder` هو الحماية من طلب ضخم يعطي بقشيشًا مبالغًا فيه.

### الرواتب
```lua
Config.Paycheck.enabled = true
Config.Paycheck.intervalMinutes = 30
Config.Paycheck.amounts = { [0]=250, [1]=400, [2]=600, [3]=850, [4]=1200 }
Config.Paycheck.minBalance = 0      -- لا تُصرف لو الرصيد بعد الصرف ينزل تحت هذا
Config.Paycheck.requireDuty = true
```
الرواتب **تُخصم من حساب الشركة**. لو الرصيد ما يكفي، تُتخطى الدورة بلا خطأ.

> **إذا فريمويركك يصرف رواتب أيضًا** (Qbox/QBCore عبر `payment` في jobs.lua)،
> الموظف بياخذ راتبين. اطفِ واحدًا منهما.

---

## التصنيع

```lua
Config.Crafting.timeMultiplier = 1.0   -- 0.5 = أسرع بمرتين، 2.0 = أبطأ بمرتين
Config.Crafting.maxDistance = 3.0      -- إلغاء التصنيع لو ابتعد
Config.Crafting.maxBatch = 10          -- أقصى دفعات في العملية الواحدة
Config.Crafting.cooldownMs = 750       -- أقل فاصل بين عمليتين (حماية سيرفرية)

Config.Crafting.skillCheck.enabled = true
Config.Crafting.skillCheck.minDifficulty = 2   -- الوصفات بصعوبة ≥ 2 تطلب اختبار مهارة
```

### الوصفات — `config/recipes.lua`
```lua
{
    id = 'scoop_vanilla',              -- معرّف فريد (يُستخدم في التحقق السيرفري)
    label = 'كرة فانيليا',
    result = { item = 'ic_scoop_vanilla', count = 2 },
    ingredients = { { item = 'ic_milk', count = 1 }, ... },
    time = 6000,                       -- ملي ثانية
    grade = 0,                         -- أقل رتبة
    difficulty = 1,                    -- 1..5 → صعوبة اختبار المهارة
    anim = { dict = '...', clip = '...' },
    icon = 'ice-cream',                -- أيقونة Font Awesome
    sellPrice = 45,                    -- سعر البيع للزبون
    perishable = true,                 -- يخضع للذوبان؟
}
```

**المكوّن الخاص `ic_scoop_any`** يقبل أي كرة من `Recipes.ScoopItems`.
المورد يحجز ذكيًا: المكونات الصريحة أولًا، ثم الوايلدكارد من الباقي — فما يستهلك
كرة مطلوبة صراحةً في نفس الوصفة.

> عند إضافة وصفة، تأكد أن كل مكوّن **إما** في `Config.Supply.catalog` **أو** ناتج
> من وصفة أخرى. المورد يفحص هذا تلقائيًا ويحذّرك.

---

## طلبات الزبائن

```lua
Config.Orders.enabled = true
Config.Orders.maxPending = 5                        -- أقصى طلبات معلّقة للفرع
Config.Orders.spawnDelay = { min = 45, max = 120 }  -- ثوانٍ بين طلب وآخر
Config.Orders.expiry = 300                          -- عمر الطلب بالثواني
Config.Orders.minEmployeesOnDuty = 1                -- لا طلبات بلا موظفين
Config.Orders.expirePenalty = 0                     -- خصم من الشركة عند فوات طلب

Config.Orders.multipliers.dayTime = 1.25   -- 10ص–8م
Config.Orders.multipliers.hotWeather = 1.35 -- EXTRASUNNY / CLEAR
Config.Orders.multipliers.night = 0.85     -- 10م–6ص
```

المضاعفات تتراكم: نهار + جو حار = ×1.69.
**ما يطلبه الزبائن** يُضبط في `Recipes.OrderPool` (وزن الاحتمالية + أقصى كمية).

---

## الفوترة

```lua
Config.Register.enabled = true
Config.Register.maxAmount = 5000        -- سقف الفاتورة الواحدة
Config.Register.maxDistance = 5.0       -- أقصى مسافة للفوترة
Config.Register.acceptTimeout = 30      -- ثوانٍ لموافقة اللاعب
```

---

## التوريد

```lua
Config.Supply.payFrom = 'society'   -- 'society' أو 'player'
Config.Supply.maxQuantity = 100     -- سقف الشراء الواحد
Config.Supply.catalog = { { item = 'ic_milk', label = 'حليب', price = 12, max = 100 }, ... }
```

**سعر البيع الإجمالي يُحسب على السيرفر من هذا الكتالوج** — الرقم القادم من العميل
هو الكمية فقط، ومحدود بـ `max` و `maxQuantity`.

### جولة التوريد
```lua
Config.Supply.run.enabled = true
Config.Supply.run.vehicle = 'boxville2'
Config.Supply.run.payout = { min = 900, max = 1600 }   -- يُدفع للاعب مباشرة
Config.Supply.run.pickups = 3                          -- عدد النقاط
Config.Supply.run.cooldownMinutes = 10
```
النقاط تُختار عشوائيًا بلا تكرار من `Locations.SupplyPickups`.
المبلغ عشوائي بين الحدين ويُحسب على السيرفر.

**الشاحنة تُخرج لك تلقائيًا** عند بدء الجولة من `branch.supplyVehicle.spawn`
في `config/locations.lua`، ولازم تكون واقفة قريبة منك (12 مترًا) عند تحميل كل شحنة.
تُحذف تلقائيًا عند إنهاء الجولة أو إلغائها أو الخروج من الدوام.
لو حذفت `supplyVehicle` من تعريف الفرع، الجولة تشتغل بلا شاحنة.

---

## عربة المثلجات

```lua
Config.Truck.enabled = true
Config.Truck.model = 'taco'          -- موديل متوفر بالأساس في GTA V
Config.Truck.rentalFee = 500         -- تُخصم من حساب الشركة
Config.Truck.requireGrade = 1
Config.Truck.priceMultiplier = 1.4   -- سعر أعلى مقابل الوقت والمخاطرة
Config.Truck.saleCooldown = 20       -- ثوانٍ بين بيعة وأخرى
Config.Truck.maxDistance = 8.0       -- أقصى بُعد عن العربة للبيع
```

نقاط البيع في `Locations.TruckSpots` — كل نقطة لها `radius` و `weight`.
لو عندك موديل عربة مثلجات مخصص (addon)، غيّر `model` لاسمه.

---

## الذوبان

```lua
Config.Melting.enabled = true
Config.Melting.checkInterval = 60    -- كل كم ثانية يُفحص ما بيدك (تحذير فقط)
Config.Melting.freshMinutes = 15     -- القيمة كاملة قبل هذا
Config.Melting.minValueRatio = 0.35  -- أقل نسبة يوصلها الذائب
Config.Melting.ruinMinutes = 45      -- بعدها غير صالح (0 = لا يتلف أبدًا)
```

**يتطلب `ox_inventory`** — يعتمد على metadata لكل خانة. مع حقائب أخرى يُتجاهل تلقائيًا.

عند البيع، المورد يسحب **الأطزج أولًا** ويحسب متوسطًا موزونًا للنضارة.
لتعطيله كليًا: `Config.Melting.enabled = false`.

> نصيحة: خلِّ `degrade` في `ox_inventory/data/items.lua` يساوي `ruinMinutes`
> حتى يتطابق سلوك الحقيبة مع منطق التسعير عندنا.

---

## الواجهة والتصحيح

```lua
Config.UI.notify = 'ox'                -- 'ox' أو 'framework'
Config.UI.contextPosition = 'top-right'
Config.UI.blips = true
Config.UI.textUI = true       -- تلميح [E] عند نقطة الدوام وعند البيع المتنقل

Config.Debug = false        -- تفاصيل إضافية في الكونسول
Config.DebugZones = false   -- يرسم صناديق ox_target داخل اللعبة (لضبط المواقع)
```

---

## إعدادات السيرفر — `server/config.server.lua`

⚠️ **ليست في `config/config.lua`.** ذاك الملف `shared` — أي شيء فيه **ينزل لجهاز
اللاعب كملف يقدر يفتحه ويقرأه**. لذلك رابط الويبهوك وإعدادات اللوقات في ملف
سيرفري بحت لا ينزل للعملاء إطلاقًا.

```lua
-- server/config.server.lua
Config.Server.webhook = ''             -- اتركه فاضيًا واستخدم convar بدلًا منه
Config.Server.logEverySale = false     -- مطفأ: كثيف على سيرفر مزدحم
Config.Server.logMoney = true
Config.Server.logEmployees = true
Config.Server.logExploits = true
```

**الويبهوك يُقرأ من `server.cfg` أولًا:**
```cfg
set icecream_webhook "https://discord.com/api/webhooks/..."
```
هذه الطريقة الآمنة — الرابط ما يدخل المستودع.
