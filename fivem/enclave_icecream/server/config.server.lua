---@diagnostic disable: lowercase-global
--[[
    enclave_icecream — إعدادات السيرفر فقط
    ---------------------------------------
    ⚠️ هذا الملف يُحمّل على السيرفر **فقط** (server_scripts في fxmanifest).
       اللاعبون لا يستطيعون قراءته — فهو المكان الصحيح لرابط الويبهوك.

    الأفضل مع ذلك: استخدم convar في server.cfg بدل كتابة الرابط هنا،
    حتى لا يدخل المستودع أصلًا:

        set icecream_webhook "https://discord.com/api/webhooks/..."
]]

Config = Config or {}

Config.Server = {
    -- يُقرأ من convar `icecream_webhook` أولًا، وإذا فاضي يستخدم القيمة هنا
    webhook = '',
    webhookName = 'Enclave Ice Cream',
    -- ألوان اللوقات (decimal)
    colors = {
        sale     = 3066993,   -- أخضر
        money    = 15844367,  -- ذهبي
        employee = 3447003,   -- أزرق
        warning  = 15158332,  -- أحمر
    },
    -- تسجيل كل عملية بيع (قد يكون كثيفًا على سيرفر مزدحم)
    logEverySale = false,
    -- تسجيل العمليات المالية والإدارية
    logMoney = true,
    logEmployees = true,
    -- تسجيل محاولات الغش المكتشفة
    logExploits = true,
}
