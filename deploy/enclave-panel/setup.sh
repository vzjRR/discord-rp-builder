#!/usr/bin/env bash
# نشر منصة الإدارة وحدها على هذا الخادم.
# للنشر المجمّع مع البوتات على خادم واحد: deploy/all-in-one/
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../common/install-base.sh"
source "$DIR/install.sh"

base_install
install_enclave_panel "$DIR"

log "جاهز"
cat <<'DONE'
  ١. املأ الأسرار: nano /etc/enclave/panel.env
  ٢. استعد النسخة: node /opt/enclave/admin-panel/scripts/restore-backup.js ~/backup.json /data
                   chown -R enclave:enclave /data
  ٣. النفق:        cloudflared service install <TOKEN>
  ٤. التشغيل:      systemctl enable --now enclave-panel
DONE
