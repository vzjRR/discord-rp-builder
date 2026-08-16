#!/usr/bin/env bash
# نشر بوت سيرفر LSPD وحده — بوت واحد لكل ما يخصّ ذلك السيرفر.
#
# توكنه وسيرفره غير توكن Enclave وسيرفره، رغم أنه يقرأ اسمي المتغيرين
# نفسيهما. ولهذا ملف أسرار مستقل: لو شارك ملف Enclave لرحّب في السيرفر
# الخطأ بالبوت الخطأ.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../common/install-base.sh"

base_install

write_env_template /etc/enclave/lspd-bot.env 'DISCORD_TOKEN=
GUILD_ID='

install_deps lspd-welcome-bot
install_unit "$DIR/lspd-bot.service"

log "جاهز"
cat <<'DONE'
  ١. املأ الأسرار: nano /etc/enclave/lspd-bot.env
  ٢. التشغيل:      systemctl enable --now lspd-bot
DONE
