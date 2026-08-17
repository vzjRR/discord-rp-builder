#!/usr/bin/env bash
# Deploys both Discord bots on one machine, separate from the admin panel:
# the Enclave server bot, and the LSPD server bot. Each still runs as its
# own service with its own secrets file and its own token, and each talks
# to only its own Discord server -- one bot per server, same as before.
# Sharing a machine here is just where the two processes happen to run.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$(dirname "$DIR")"

source "$DEPLOY/common/install-base.sh"
source "$DEPLOY/enclave-bot/install.sh"
source "$DEPLOY/lspd-bot/install.sh"

base_install

install_enclave_bot "$DEPLOY/enclave-bot"
install_lspd_bot    "$DEPLOY/lspd-bot"

log "Both bots installed"
cat <<'DONE'

Remaining steps, in order:

  1. Fill in secrets -- two separate files, one token each:

       nano /etc/enclave/enclave-bot.env   # Enclave bot
       nano /etc/enclave/lspd-bot.env      # LSPD bot (different token and guild!)

  2. Start both:

       systemctl enable --now enclave-bot lspd-bot

  3. Watch:

       systemctl status enclave-bot lspd-bot --no-pager
       journalctl -u enclave-bot -f

Note: the admin panel is a separate deployment (deploy/enclave-panel/).
It reads /data/server-events.db, which the Enclave bot writes. If the
panel runs on a different machine than this one, recent-leavers and
activity-ranking on its status page will be empty -- everything else
works the same.
DONE
