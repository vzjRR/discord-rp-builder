#!/usr/bin/env bash
# نشر بوت سيرفر Enclave وحده على هذا الخادم.
# للنشر المجمّع مع المنصة وبوت LSPD على خادم واحد: deploy/all-in-one/
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../common/install-base.sh"
source "$DIR/install.sh"

base_install
install_enclave_bot "$DIR"

log "جاهز"
cat <<'DONE'
  ١. املأ الأسرار: nano /etc/enclave/enclave-bot.env
  ٢. التشغيل:      systemctl enable --now enclave-bot
DONE
