#!/usr/bin/env bash
# خطوات بوت سيرفر Enclave وحده. تفترض أن الأساس المشترك رُكِّب سلفًا.
install_enclave_bot() {
  local DIR="$1"
  mkdir -p /data && chown -R "$RUN_USER:$RUN_USER" /data && chmod 750 /data

  write_env_template /etc/enclave/enclave-bot.env 'DISCORD_TOKEN=
GUILD_ID=

EVENTS_DB_PATH=/data/server-events.db
MESSAGE_TEMPLATES_PATH=/data/message-templates.json'

  install_deps welcome-bot
  install_unit "$DIR/enclave-bot.service"
}
