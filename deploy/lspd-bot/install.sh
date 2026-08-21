#!/usr/bin/env bash
# خطوات بوت سيرفر LSPD وحده. تفترض أن الأساس المشترك رُكِّب سلفًا.
#
# ملف أسرار مستقل: توكنه وسيرفره غير اللذين لـ Enclave رغم تطابق أسماء
# المتغيرات — ومشاركة ملف Enclave تجعله يرحّب في السيرفر الخطأ.
install_lspd_bot() {
  local DIR="$1"
  write_env_template /etc/enclave/lspd-bot.env 'DISCORD_TOKEN=
GUILD_ID='

  install_deps lspd-welcome-bot
  install_unit "$DIR/lspd-bot.service"

  # لوقات LSPD تشتغل بنفس هوية بوت الترحيب (نفس /etc/enclave/lspd-bot.env)
  # عمدًا — عملية Node منفصلة، لكن نفس تطبيق ديسكورد، بدل بوت لوقات مستقل.
  install_deps logs-bot
  install_unit "$DIR/lspd-logs-bot.service"
}
