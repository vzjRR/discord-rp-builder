#!/usr/bin/env bash
# نشر منصة الإدارة وحدها.
#
# تقرأ /data/server-events.db الذي يكتبه بوت Enclave. فإن نُشرا على
# خادمين مختلفين تعمل المنصة كاملةً عدا "آخر المغادرين" و"الأكثر تفاعلًا"
# في صفحة حالة السيرفر — فتلك بيانات لا يملكها إلا البوت.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../common/install-base.sh"

base_install
mkdir -p /data && chown -R "$RUN_USER:$RUN_USER" /data && chmod 750 /data

write_env_template /etc/enclave/panel.env 'DISCORD_TOKEN=
GUILD_ID=
SESSION_SECRET=

PUBLIC_BASE_URL=https://enclave-admin.tsh87.com
CLOUDFLARE_SECRET=
REQUIRE_CLOUDFLARE=true
OWNER_NOTIFY_USER_ID=

SQLITE_PATH=/data/admin.db
EVENTS_DB_PATH=/data/server-events.db
ONBOARDING_MESSAGE_PATH=/data/onboarding-message.json
REVOCATION_MESSAGE_PATH=/data/revocation-message.json
MESSAGE_TEMPLATES_PATH=/data/message-templates.json'

install_deps admin-panel
install_unit "$DIR/enclave-panel.service"

# cloudflared: يفتح اتصالًا صادرًا إلى Cloudflare، فلا يحتاج الخادم منفذًا
# واردًا ولا عنوانًا عامًا ولا شهادة — ولا يُكتشف أصلًا.
if ! command -v cloudflared >/dev/null 2>&1; then
  log "تثبيت cloudflared"
  ARCH="$(dpkg --print-architecture)"
  curl -fsSL -o /tmp/cloudflared.deb \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
  dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
  rm -f /tmp/cloudflared.deb
fi

log "جاهز"
cat <<'DONE'
  ١. املأ الأسرار:   nano /etc/enclave/panel.env
  ٢. استعد النسخة:   node /opt/enclave/admin-panel/scripts/restore-backup.js ~/backup.json /data
                     chown -R enclave:enclave /data
  ٣. النفق:          cloudflared service install <TOKEN>
  ٤. التشغيل:        systemctl enable --now enclave-panel
DONE
