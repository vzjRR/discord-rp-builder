#!/usr/bin/env bash
# Deploys the Enclave server bot on its own machine, separate from the
# admin panel. LSPD's bots (welcome, logs, tickets) are a fully separate
# Discord application on a fully separate server, with their own repo and
# deploy script now -- see https://github.com/vzjRR/ENCLAVE-LSPD.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$(dirname "$DIR")"

source "$DEPLOY/common/install-base.sh"
source "$DEPLOY/enclave-bot/install.sh"

base_install

install_enclave_bot "$DEPLOY/enclave-bot"

log "Enclave bot installed"
cat <<'DONE'

Remaining steps, in order:

  1. Fill in secrets:

       nano /etc/enclave/enclave-bot.env

  2. Start it:

       systemctl enable --now enclave-bot

  3. Watch:

       systemctl status enclave-bot --no-pager
       journalctl -u enclave-bot -f

Note: the admin panel is a separate deployment (deploy/enclave-panel/).
It reads /data/server-events.db, which the Enclave bot writes. If the
panel runs on a different machine than this one, recent-leavers and
activity-ranking on its status page will be empty -- everything else
works the same.
DONE
