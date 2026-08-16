#!/usr/bin/env bash
# نشر بوت سيرفر Enclave وحده (الترحيب + تسجيل حركة الأعضاء).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../common/install-base.sh"

base_install
mkdir -p /data && chown -R "$RUN_USER:$RUN_USER" /data && chmod 750 /data

write_env_template /etc/enclave/enclave-bot.env 'DISCORD_TOKEN=
GUILD_ID=

EVENTS_DB_PATH=/data/server-events.db
MESSAGE_TEMPLATES_PATH=/data/message-templates.json'

install_deps welcome-bot
install_unit "$DIR/enclave-bot.service"

log "جاهز"
cat <<'DONE'
  ١. املأ الأسرار: nano /etc/enclave/enclave-bot.env
  ٢. التشغيل:      systemctl enable --now enclave-bot
DONE
