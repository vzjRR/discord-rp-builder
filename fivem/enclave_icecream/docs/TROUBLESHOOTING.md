# حل المشاكل

---

## المورد لا يبدأ

### `Could not find dependency ox_lib for resource enclave_icecream`
`ox_lib` غير مشتغل أو يبدأ **بعد** موردنا. في `server.cfg`:
```cfg
ensure ox_lib             # 👈 قبل
ensure enclave_icecream   # 👈 بعد
```

### `attempt to index a nil value (global 'lib')`
نفس السبب أعلاه — `@ox_lib/init.lua` ما تحمّل.

### `attempt to index a nil value (global 'Config')`
ملف `config/config.lua` فيه خطأ صياغة فما تحمّل. اقرأ الكونسول فوق هذا الخطأ —
بيكون فيه سطر `SCRIPT ERROR` يحدد رقم السطر.

---

## مشاكل الاكتشاف

الكونسول يطبع عند التشغيل:
```
[enclave_icecream] جاهز — framework=qbx inventory=ox target=ox db=true branches=1
```

| القيمة | المعنى | الحل |
|---|---|---|
| `framework=standalone` وعندك QBCore | الفريمويرك بدأ بعد موردنا | رتّب `server.cfg` |
| `inventory=none` | ما في حقيبة مكتشفة | ركّب `ox_inventory` أو اضبط `Config.Inventory` يدويًا |
| `db=false` | `oxmysql` ما اشتغل | `ensure oxmysql` قبل موردنا |
| `branches=0` | `locations.lua` فاضي/معطوب | راجع الملف |

**الإجبار اليدوي** في `config/config.lua`:
```lua
Config.Framework = 'qb'
Config.Inventory = 'ox'
Config.Target = 'ox'
```

---

## مشاكل داخل اللعبة

### ما يظهر خيار تفاعل عند المحطات
بالترتيب:
1. أنت موظف؟ → `/ic_setjob <رقمك> 4`
2. مسجّل دوام؟ → التفاعل عند نقطة الدوام أولًا
3. رتبتك تسمح؟ → راجع جدول الصلاحيات في README
4. الإحداثيات صحيحة؟ → `Config.DebugZones = true` وشوف الصناديق

### المناطق في الهواء أو داخل الجدار
إحداثيات محلك مختلفة. استخدم `/ic_coords` عند كل نقطة وبدّل القيم في
`config/locations.lua`. راجع [README القسم 6](../README.md#6-تغيير-المواقع-لمحلك-أنت).

### ما تجي طلبات زبائن
- تحتاج **موظفًا واحدًا على الأقل على الدوام** (`Config.Orders.minEmployeesOnDuty`)
- انتظر بين 45 و 120 ثانية (`Config.Orders.spawnDelay`)
- تأكد `Config.Orders.enabled = true`
- الزبون NPC يظهر فقط لو كنت على بُعد أقل من 60 مترًا من مركز الفرع

### الفريزر ما يفتح
الفريزر ستاش `ox_inventory`. لو تستخدم `qb-inventory` أو حقيبة ESX الافتراضية،
الفريزر معطّل. الحل: ركّب `ox_inventory`.

### التصنيع يقول «ناقصك» وأنا معي المكونات
- أسماء العناصر لازم تطابق **بالضبط** بين `config/recipes.lua` وملف عناصر فريمويركك
- تأكد أن العنصر أُضيف فعلًا (افتح حقيبتك وشوفه)
- مع الحقائب غير ox، عدّ العناصر يعتمد على `PlayerData.items` — لو حقيبتك مخصصة قد لا يعمل

### المكونات تنخصم لكن ما أستلم المنتج
هذا **مقصود عند الفشل**: المكونات تُخصم عند بدء التصنيع، وتضيع لو فشلت في اختبار
المهارة أو ألغيت. لتعطيل اختبار المهارة:
```lua
Config.Crafting.skillCheck.enabled = false
```

### الفاتورة ما توصل اللاعب
- المسافة لازم أقل من `Config.Register.maxDistance` (5 متر افتراضيًا)
- رقم اللاعب لازم يكون **server id** الصحيح (اللي يظهر بقائمة اللاعبين)

### العربة ما تطلع
- المكان أمامها مشغول بمركبة ثانية → حرّكها
- رصيد الشركة أقل من `Config.Truck.rentalFee`
- رتبتك أقل من `Config.Truck.requireGrade`

### العربة تطلع بس ما أقدر أبيع
- لازم تكون داخل نقطة ساخنة (`Locations.TruckSpots`) — بلبس خضراء على الخريطة
- ولازم تكون على بُعد `Config.Truck.maxDistance` من عربتك
- ولازم معك منتجات فعلًا

---

## مشاكل الاقتصاد

### رصيد الشركة يرجع 25000 بعد كل ريستارت
`oxmysql` ما يشتغل أو `Config.UseDatabase = false`. تحقق من `db=true` في رسالة التشغيل.

### الموظف ياخذ راتبين
فريمويركك يصرف رواتب أيضًا (`payment` في `jobs.lua`). اطفِ واحدًا:
```lua
Config.Paycheck.enabled = false     -- عندنا
-- أو payment = 0 في jobs.lua عند فريمويركك
```

### `societyShare + employeeTip = 0.90 (يفترض 1.0)` في الكونسول
مجموع النسبتين لازم يساوي 1.0 بالضبط، وإلا فقد جزء من قيمة كل بيعة.

---

## رسائل فحص الإعدادات

المورد يفحص إعداداتك عند كل تشغيل. الرسائل الشائعة:

| الرسالة | المعنى |
|---|---|
| `المحطة "X" في الفرع "Y" ما لها وصفات` | `station.id` في `locations.lua` ما يطابق أي مفتاح في `recipes.lua` |
| `الوصفة "X" تحتاج "Y" وهو غير موجود...` | مكوّن ليس في `Config.Supply.catalog` ولا ينتج من وصفة |
| `منتج الطلبات "X" ما ينتج من أي وصفة` | عنصر في `Recipes.OrderPool` بلا وصفة تنتجه |
| `معرّف وصفة مكرر "X"` | وصفتان بنفس `id` — لازم يكون فريدًا على مستوى المورد كله |

كلها **تحذيرات لا توقف المورد**، لكن الميزة المتأثرة لن تعمل صح.

---

## لوقات ديسكورد لا تصل

1. الرابط صحيح؟ لازم يبدأ بـ `https://discord.com/api/webhooks/`
2. الأفضل عبر `server.cfg`: `set icecream_webhook "..."`
3. النوع مفعّل؟ راجع `Config.Server.logMoney` / `logEmployees` / `logExploits`
4. البيع مطفأ افتراضيًا: `Config.Server.logEverySale = false`

اللوقات تُحفظ في جدول `icecream_logs` بأي حال — استعلم منه مباشرة.

---

## تصحيح متقدم

```lua
Config.Debug = true        -- تفاصيل كل عملية في الكونسول
Config.DebugZones = true   -- رسم صناديق التفاعل داخل اللعبة
```

في الكونسول:
```
refresh
restart enclave_icecream
```

للاطلاع على محاولات الغش المسجّلة:
```sql
SELECT * FROM icecream_logs WHERE action = 'exploit' ORDER BY created_at DESC LIMIT 50;
```

---

## ما زالت المشكلة قائمة؟

اجمع هذه المعلومات قبل السؤال:
1. سطر `[enclave_icecream] جاهز — ...` كاملًا
2. أي تحذيرات ظهرت تحته
3. الخطأ الحرفي من كونسول السيرفر أو F8 عند العميل
4. فريمويركك وإصداره + حقيبتك
