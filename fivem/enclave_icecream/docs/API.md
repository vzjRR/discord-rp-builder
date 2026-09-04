# الأحداث والـ Callbacks والـ Exports

مرجع للمطورين الذين يريدون ربط المورد بموارد أخرى أو تعديله.

---

## Exports (السيرفر)

```lua
---رصيد حساب الشركة لفرع
---@param branchId? string  الافتراضي: أول فرع
---@return number
exports.enclave_icecream:getBalance(branchId)

---إضافة للرصيد (amount موجب فقط)
---@return number newBalance
exports.enclave_icecream:addBalance(branchId, amount)

---خصم من الرصيد
---@return boolean  false لو الرصيد لا يكفي
exports.enclave_icecream:takeBalance(branchId, amount)

---عدد الموظفين على الدوام
---@return number
exports.enclave_icecream:getOnDutyCount(branchId)

---تكامل ox_inventory: يمنع أكل المثلجات الذائبة
---يُستدعى تلقائيًا عبر  server = { export = 'enclave_icecream.consume' }
exports.enclave_icecream:consume(event, item, inventory, slot, data)
```

**مثال — نظام ضرائب يخصم من كل المحلات:**
```lua
CreateThread(function()
    while true do
        Wait(3600000)  -- كل ساعة
        local balance = exports.enclave_icecream:getBalance('vespucci')
        local tax = math.floor(balance * 0.02)
        if tax > 0 and exports.enclave_icecream:takeBalance('vespucci', tax) then
            print(('ضريبة محل المثلجات: $%s'):format(tax))
        end
    end
end)
```

---

## Callbacks (عميل ← سيرفر)

كلها عبر `lib.callback.await(name, false, ...)` من ox_lib.

| الاسم | الوسائط | يرجّع |
|---|---|---|
| `icecream:server:getJob` | — | `{ name, grade, onduty }` أو `nil` |
| `icecream:server:getBranchState` | `branchId` | `{ balance, onDuty, pendingOrders, grade, isBoss }` |
| `icecream:server:getStats` | `branchId` | `{ today, week, orders, yours, topItem, topEmployee, balance }` |
| `icecream:server:startCraft` | `{ branch, station, recipe, batch }` | `{ duration, skillCheck, difficulty, anim, label, resultCount }` أو `false` |
| `icecream:server:finishCraft` | `{ branch, station, recipe, batch, success }` | `boolean` |
| `icecream:server:getOrders` | `branchId` | `order[]` |
| `icecream:server:deliverOrder` | `branchId, orderId` | `boolean` |
| `icecream:server:createBill` | `{ branch, target, amount, reason }` | `boolean` |
| `icecream:server:getPriceList` | — | `{ item, label, price }[]` |
| `icecream:server:getCatalog` | `branchId` | `{ catalog, balance, payFrom }` |
| `icecream:server:buySupply` | `{ branch, item, quantity }` | `boolean` |
| `icecream:server:startSupplyRun` | `branchId` | `{ points, vehicle, total }` أو `false` |
| `icecream:server:collectSupply` | `pointIndex` | `{ collected, total }` أو `false` |
| `icecream:server:finishSupplyRun` | — | `boolean` |
| `icecream:server:takeTruck` | `branchId` | `{ model, spawn }` أو `false` |
| `icecream:server:storeTruck` | `branchId` | `{ netId }` أو `false` |
| `icecream:server:truckSell` | `{ spot, item, count }` | `boolean` |
| `icecream:server:getTruckSpots` | — | `spot[]` |
| `icecream:server:getBossData` | `branchId` | `{ balance, employees, stats, maxPromoteGrade, grades }` |
| `icecream:server:bossDeposit` | `branchId, amount` | `newBalance` أو `false` |
| `icecream:server:bossWithdraw` | `branchId, amount` | `newBalance` أو `false` |
| `icecream:server:bossHire` | `branchId, targetSrc` | `boolean` |
| `icecream:server:bossFire` | `branchId, citizenid` | `boolean` |
| `icecream:server:bossPromote` | `branchId, citizenid, grade` | `boolean` |

> كل واحد منها يعيد التحقق من: الوظيفة + الدوام + الرتبة + المسافة. الرفض يُسجَّل.

---

## أحداث الشبكة (عميل → سيرفر)

| الحدث | الوسائط | ملاحظة |
|---|---|---|
| `icecream:server:toggleDuty` | `branchId` | يبدّل الدوام (فحص مسافة) |
| `icecream:server:respondBill` | `billId, accepted` | فقط المستهدف يقدر يرد |
| `icecream:server:registerTruck` | `netId` | ربط العربة بمالكها |
| `icecream:server:cancelSupplyRun` | — | إلغاء الجولة |
| `icecream:server:reportWorld` | `hour, weather` | تجميلي — يؤثر على مضاعف السعر فقط |

---

## أحداث الشبكة (سيرفر → عميل)

| الحدث | الوسائط |
|---|---|
| `icecream:client:notify` | `localeKey, kind, args[]` |
| `icecream:client:syncOrders` | `branchId, order[]` |
| `icecream:client:receiveBill` | `{ id, from, amount, reason, shop, timeout }` |
| `icecream:client:closeBill` | `billId` |
| `icecream:client:setDuty` | `onduty` |
| `icecream:client:setJob` | `job` (standalone فقط) |
| `icecream:client:moneyChanged` | `account, amount, reason` (standalone فقط) |

---

## أحداث محلية (داخل العميل)

استمع لها من موردك لو تبي تتفاعل مع حالة اللاعب:

```lua
-- تغيّرت وظيفة/رتبة/دوام اللاعب
AddEventHandler('icecream:client:jobChanged', function(job)
    -- job = { name, grade, onduty, label }
end)

-- دخل/خرج من نطاق فرع
AddEventHandler('icecream:client:branchChanged', function(branchId)
    -- branchId = string أو nil
end)

-- تحدّثت قائمة الطلبات
AddEventHandler('icecream:client:ordersChanged', function(branchId) end)

AddEventHandler('icecream:client:playerLoaded', function() end)
AddEventHandler('icecream:client:playerUnloaded', function() end)
```

---

## دوال مفيدة داخل المورد

### مشتركة (`bridge/shared.lua`)
```lua
IC.hasResource(name)             -- هل المورد مشتغل؟
IC.money(1234567)                -- "1,234,567"
IC.toInt(value, min, max)        -- تحقق آمن من رقم صحيح، nil لو غير صالح
IC.weightedPick(pool)            -- اختيار موزون بحقل weight
IC.gradeInfo(grade)              -- تعريف الرتبة (لا يرجّع nil أبدًا)
IC.can(grade, 'canCraft')        -- فحص صلاحية
IC.resolveRecipe(id, stationId)  -- ترجمة معرّف لوصفة موثوقة، nil لو مزوّر
L('duty_on')                     -- الترجمة (ترجّع المفتاح لو ناقص بدل ما تنهار)
```

### السيرفر (`bridge/server.lua` + `server/main.lua`)
```lua
IC.getPlayer(src)                          -- { source, citizenid, name, job }
IC.validateWorker(src, permission)         -- player أو nil, reason
IC.server.gate(src, perm, coords, maxDist) -- التحقق الكامل + إشعار تلقائي
IC.isNear(src, coords, maxDistance)
IC.rateLimit(src, key, cooldownMs)
IC.addMoney / IC.removeMoney / IC.getMoney (src, account, amount, reason)
IC.addItem / IC.removeItem / IC.getItemCount / IC.canCarry
IC.hasIngredients(src, ingredients, batch) -- ok, missing[]
IC.consumeIngredients(src, ingredients, batch)
IC.setJob(src, grade) / IC.removeJob(src) / IC.setDuty(src, bool)
IC.server.freshness(metadata)              -- ratio, ruined
IC.server.takeProduct(src, item, count)    -- ok, ratio (يسحب الأطزج أولًا)
IC.society.getBalance/add/take/canAfford(branchId, amount)
IC.society.settleSale(branchId, src, player, total, item, qty, kind)
```

### العميل (`bridge/client.lua`)
```lua
IC.isEmployee() / IC.isWorking()
IC.hasPermission('canCraft')
IC.checkAccess('canCraft')       -- يتحقق ويعرض الإشعار المناسب
IC.notify(message, 'success')
IC.getItemCount(item) / IC.countWithWildcard(item)
IC.addBoxZone{...} / IC.removeZone(id)
IC.loadModel(model) / IC.loadAnimDict(dict)
IC.client.setBusy(bool)
```

---

## الأوامر

| الأمر | الصلاحية | الشرح |
|---|---|---|
| `/ic_coords` | `group.admin` | يطبع إحداثياتك بصيغة جاهزة للصق في `locations.lua` |
| `/ic_setjob <id> <grade>` | `group.admin` | يعيّن وظيفة المحل للاعب |

---

## جداول قاعدة البيانات

| الجدول | المحتوى |
|---|---|
| `icecream_business` | رصيد الشركة لكل فرع |
| `icecream_employees` | الموظفون + إحصائياتهم التراكمية |
| `icecream_sales` | كل عملية بيع (للإحصائيات والتقارير) |
| `icecream_logs` | العمليات المالية والإدارية ومحاولات الغش |
| `icecream_standalone_jobs` | الوظائف في الوضع standalone فقط |

**استعلامات مفيدة:**
```sql
-- أفضل 10 موظفين هذا الشهر
SELECT e.name, SUM(s.amount) AS total, COUNT(*) AS orders
FROM icecream_sales s JOIN icecream_employees e ON e.citizenid = s.citizenid
WHERE s.created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY s.citizenid, e.name ORDER BY total DESC LIMIT 10;

-- محاولات الغش آخر أسبوع
SELECT created_at, citizenid, detail FROM icecream_logs
WHERE action = 'exploit' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY created_at DESC;

-- أكثر المنتجات مبيعًا
SELECT item, SUM(qty) AS qty, SUM(amount) AS revenue
FROM icecream_sales WHERE item <> '' GROUP BY item ORDER BY qty DESC;
```
