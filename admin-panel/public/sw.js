// Service Worker بسيط — غرضه الوحيد إثبات إمكانية التثبيت (PWA installable).
// ما نخزّن أي بيانات أو نتدخل بالطلبات — كل صفحة تنجلب دايمًا من السيرفر
// لأنها تحتوي بيانات حساسة (رسائل/moderation) ما نبي نكاشها بالمتصفح.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {}); // pass-through — بدون كاش
