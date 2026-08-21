#!/usr/bin/env bash
# نشر بوت سيرفر LSPD وحده على هذا الخادم.
#
# توكنه وسيرفره غير توكن Enclave وسيرفره، رغم أنه يقرأ اسمي المتغيرين
# نفسيهما — ولهذا ملف أسرار مستقل (شرحه في install.sh).
#
# للنشر المجمّع مع المنصة وبوت Enclave على خادم واحد: deploy/all-in-one/
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../common/install-base.sh"
source "$DIR/install.sh"

base_install
install_lspd_bot "$DIR"

log "جاهز"
cat <<'DONE'
  ١. املأ الأسرار: nano /etc/enclave/lspd-bot.env
  ٢. التشغيل:      systemctl enable --now lspd-bot lspd-logs-bot
DONE
