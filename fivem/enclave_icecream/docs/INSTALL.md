# التركيب المفصّل حسب الفريمويرك

> الدليل السريع في [`../README.md`](../README.md#3-التركيب--من-الألف-للياء).
> هنا التفاصيل الخاصة بكل فريمويرك ومشاكله المعروفة.

---

## Qbox (`qbx_core`) — الأسهل والأكمل

Qbox يستخدم `ox_lib` و `ox_inventory` و `ox_target` أصلًا، فما تحتاج تركّب شيئًا إضافيًا.

### 1. العناصر
`ox_inventory/data/items.lua` — الصق عناصر القسم 1 من `config/items.lua` داخل جدول `return`:
```lua
return {
    -- عناصر السيرفر الموجودة...

    ['ic_milk'] = { label = 'حليب', weight = 500, stack = true, close = false },
    ['ic_cream'] = { label = 'قشطة', weight = 400, stack = true, close = false },
    -- ... باقي الـ 27 عنصرًا
}
```

### 2. الوظيفة
`qbx_core/shared/jobs.lua`:
```lua
icecream = {
    label = 'محل المثلجات',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        [0] = { name = 'متدرب', payment = 250 },
        [1] = { name = 'موزّع', payment = 400 },
        [2] = { name = 'صانع مثلجات', payment = 600 },
        [3] = { name = 'مساعد مدير', payment = 850 },
        [4] = { name = 'المالك', isboss = true, bankAuth = true, payment = 1200 },
    },
},
```

> **ملاحظة الرواتب:** Qbox عنده نظام رواتب خاص فيه (`payment` أعلاه).
> لو خلّيت `Config.Paycheck.enabled = true` عندنا، **الموظف بياخذ راتبين**.
> اختر واحدًا: إما `payment = 0` في jobs.lua، أو `Config.Paycheck.enabled = false`.

### 3. server.cfg
```cfg
ensure oxmysql
ensure ox_lib
ensure qbx_core
ensure ox_inventory
ensure ox_target
ensure enclave_icecream
```

---

## QBCore (`qb-core`)

### 1. العناصر
`qb-core/shared/items.lua` — الصق القسم 2 من `config/items.lua`.

ثم ضع صور الأيقونات في `qb-inventory/html/images/` (أو `ox_inventory/web/images/`)
بنفس أسماء العناصر: `ic_scoop_vanilla.png` إلخ.

### 2. الوظيفة
`qb-core/shared/jobs.lua` — نفس تعريف Qbox أعلاه.

### 3. التارجت
لو تستخدم `qb-target` بدل `ox_target`، المورد يكتشفه تلقائيًا.
لو أردت الإجبار: `Config.Target = 'qb'` في `config/config.lua`.

### 4. الحقيبة
- **`ox_inventory`** (موصى به): كل الميزات تشتغل بما فيها الفريزر والذوبان.
- **`qb-inventory`**: يشتغل، لكن **الفريزر معطّل** (ستاشات ox فقط) و **الذوبان معطّل**
  (يحتاج metadata لكل خانة).

### 5. server.cfg
```cfg
ensure oxmysql
ensure ox_lib
ensure qb-core
ensure qb-inventory        # أو ox_inventory
ensure qb-target           # أو ox_target
ensure enclave_icecream
```

---

## ESX (`es_extended`)

### 1. العناصر
نفّذ استعلام القسم 3 من `config/items.lua` على قاعدة بياناتك.

مع `ox_inventory` على ESX: استخدم القسم 1 بدلًا من ذلك (ox_inventory ما يقرأ جدول `items`).

### 2. الوظيفة
نفّذ استعلامات `jobs` و `job_grades` من القسم 4.

### 3. ⚠️ الدوام في ESX
ESX **ما عنده نظام دوام أصلًا**. المورد يديره بنفسه في الذاكرة، وهذا يعني:
- الدوام **يضيع** عند إعادة تشغيل السيرفر أو خروج اللاعب.
- هذا سلوك مقصود ومقبول (يبدأ اللاعب مناوبته من جديد).
- لو ما تبي دوامًا أصلًا: `Config.RequireDuty = false`.

### 4. server.cfg
```cfg
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_inventory        # موصى به بقوة على ESX
ensure ox_target
ensure enclave_icecream
```

---

## standalone (بلا فريمويرك)

للسيرفرات المخصصة أو للتجربة. الفروقات:

| الميزة | الحالة |
|---|---|
| الوظائف والرتب | ✅ يديرها المورد ويحفظها في `icecream_standalone_jobs` |
| الدوام | ✅ يديره المورد (في الذاكرة) |
| التصنيع والوصفات | ✅ يشتغل لو `ox_inventory` موجود |
| الفلوس | ❌ لا يوجد نظام فلوس — الدفع والبقشيش يُطلقان حدثًا فقط |
| حساب الشركة | ✅ رقم محفوظ بقاعدة البيانات (لكن بلا ربط بفلوس اللاعبين) |

للتوظيف: `/ic_setjob <رقم اللاعب> <الرتبة>` (يتطلب `group.admin`).

لربط نظام فلوسك الخاص، اسمع الحدث:
```lua
RegisterNetEvent('icecream:client:moneyChanged', function(account, amount, reason)
    -- amount موجب = إضافة، سالب = خصم
end)
```

---

## التحقق من نجاح التركيب

بعد التشغيل، لازم تشوف في كونسول السيرفر:
```
[enclave_icecream] جاهز — framework=qbx inventory=ox target=ox db=true branches=1
```

اقرأ القيم:
- `framework=standalone` وأنت تستخدم QBCore؟ → `qb-core` ما بدأ قبل موردنا، أو الاسم مختلف
- `inventory=none`؟ → ما في حقيبة مكتشفة، التصنيع ما راح يعطي عناصر
- `db=false`؟ → `oxmysql` ما اشتغل، كل شيء في الذاكرة
- `branches=0`؟ → `config/locations.lua` فاضي أو فيه خطأ

لو ظهرت رسالة `وُجدت N مشكلة في الإعدادات` — اقرأ الأسطر تحتها، كل واحدة تحدد المشكلة بدقة.
