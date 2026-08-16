#!/usr/bin/env bash
# نشر كل شيء على خادم واحد: المنصة، وبوت Enclave، وبوت LSPD.
#
# هذا هو الوضع الموصى به. الشريحة المجانية الواحدة تسعها بفائض كبير،
# والمنصة وبوت Enclave يتشاركان /data/server-events.db أصلًا — فبقاؤهما
# معًا يجعل صفحة حالة السيرفر كاملة دون ترتيب إضافي.
#
# الأساس المشترك (الحزم، Node، المستخدم، الكود، الجدار الناري) يُركَّب مرة
# واحدة، ثم تُضاف كل خدمة بما يخصّها: ملف أسرار مستقل، ووحدة تشغيل مستقلة.
# فتبقى الخدمات منفصلة في التشغيل والإيقاف والتحديث وإن جمعها خادم.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$(dirname "$DIR")"

source "$DEPLOY/common/install-base.sh"
source "$DEPLOY/enclave-panel/install.sh"
source "$DEPLOY/enclave-bot/install.sh"
source "$DEPLOY/lspd-bot/install.sh"

base_install

install_enclave_panel "$DEPLOY/enclave-panel"
install_enclave_bot   "$DEPLOY/enclave-bot"
install_lspd_bot      "$DEPLOY/lspd-bot"

log "رُكِّبت الخدمات الثلاث"
cat <<'DONE'

الخطوات المتبقية بالترتيب:

  ١. املأ الأسرار — ثلاثة ملفات منفصلة، ولكل بوت توكنه:

       nano /etc/enclave/panel.env        # المنصة
       nano /etc/enclave/enclave-bot.env  # بوت Enclave
       nano /etc/enclave/lspd-bot.env     # بوت LSPD (توكن وسيرفر مختلفان!)

  ٢. استعد بيانات المنصة (ارفع ملف النسخة عبر Cloud Shell أولًا):

       node /opt/enclave/admin-panel/scripts/restore-backup.js ~/enclave-backup.json /data
       chown -R enclave:enclave /data

  ٣. نفق Cloudflare بالرمز الذي نسخته من لوحته:

       cloudflared service install <TOKEN>

  ٤. شغّل الخدمات:

       systemctl enable --now enclave-panel enclave-bot lspd-bot

  ٥. تابع:

       systemctl status enclave-panel enclave-bot lspd-bot --no-pager
       journalctl -u enclave-panel -f

DONE
