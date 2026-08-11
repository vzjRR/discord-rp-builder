#!/usr/bin/env bash
# يشغّل بوت الترحيب (welcome-bot) ومنصة الإدارة (admin-panel) بعملية Node
# منفصلة لكل وحدة، داخل نفس سيرفس Railway وحاوية وحدة — عشان ما نحتاج
# سيرفس Railway إضافي (وبالتالي ما نحتاج قاعدة بيانات منفصلة، المنصة تستخدم
# SQLite على نفس الـ Volume المرفق بهذا السيرفس).
#
# PORT= (فاضي) لعملية welcome-bot عشان سيرفر الـ health-check الاختياري
# فيها ما يحاول ياخذ نفس المنفذ اللي منصة الإدارة تحتاجه فعليًا للدومين
# العام — بدون هذا بيصير تعارض على نفس المنفذ.

set -e

(cd welcome-bot && PORT= npm start) &
WELCOME_PID=$!

(cd admin-panel && npm start) &
ADMIN_PID=$!

wait -n "$WELCOME_PID" "$ADMIN_PID"
EXIT_CODE=$?
echo "⚠️  إحدى العمليتين توقفت (كود $EXIT_CODE) — بنوقف الحاوية عشان Railway يعيد تشغيلها."
exit "$EXIT_CODE"
