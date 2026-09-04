# 🎮 قسم FiveM

هذا القسم مستقل تمامًا عن بوتات Discord في جذر المستودع — لا يشترك معها في
`package.json` ولا في متغيرات البيئة. موارد Lua تُنسخ لسيرفر FiveM.

## المحتويات

| المجلد | الوصف |
|---|---|
| [`PLAN.md`](PLAN.md) | خطة المشروع: البحث في معايير FiveM، المعمارية، الميزات، خارطة التنفيذ |
| [`enclave_icecream/`](enclave_icecream/) | 🍦 مورد مطعم/محل المثلجات — وظيفة كاملة قابلة للعب |

## enclave_icecream باختصار

مورد وظيفة لمحل مثلجات: تصنيع بمكونات حقيقية على 4 محطات، طلبات زبائن NPC،
كاشير وفوترة، توريد بالجملة وجولات شاحنة، عربة مثلجات متنقلة، حساب شركة
ومنيو بوس، رواتب دورية، ونظام ذوبان يخفّض قيمة المثلجات مع الوقت.

- **يشتغل على:** Qbox • QBCore • ESX • standalone
- **يتطلب:** `ox_lib` (إلزامي) — و`ox_inventory` + `ox_target` + `oxmysql` (موصى بها بشدة)
- **دليل التركيب من الألف للياء:** [`enclave_icecream/README.md`](enclave_icecream/README.md)

```
resources/[jobs]/enclave_icecream/     ← انسخ المجلد هنا
```

```cfg
# server.cfg — الترتيب مهم
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure qbx_core
ensure enclave_icecream
```

## التوثيق

- [دليل الاستخدام الكامل](enclave_icecream/README.md) — تركيب، لعب، إعداد، أمان
- [التركيب حسب الفريمويرك](enclave_icecream/docs/INSTALL.md)
- [شرح كل خيار في الإعدادات](enclave_icecream/docs/CONFIG.md)
- [الأحداث والـ callbacks والـ exports](enclave_icecream/docs/API.md)
- [حل المشاكل](enclave_icecream/docs/TROUBLESHOOTING.md)
