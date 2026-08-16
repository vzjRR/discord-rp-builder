#!/usr/bin/env bash
# خطوات منصة الإدارة وحدها. تفترض أن الأساس المشترك رُكِّب سلفًا
# (install-base.sh ← base_install). تُستدعى من setup.sh أو من all-in-one.
install_enclave_panel() {
  local DIR="$1"
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

  # cloudflared: اتصال صادر إلى Cloudflare، فلا منفذ وارد ولا عنوان عام
  # ولا شهادة على الأصل — ولا يُكتشف الخادم أصلًا.
  if ! command -v cloudflared >/dev/null 2>&1; then
    log "تثبيت cloudflared"
    local ARCH; ARCH="$(dpkg --print-architecture)"
    curl -fsSL -o /tmp/cloudflared.deb \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
    dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
    rm -f /tmp/cloudflared.deb
  fi
}
