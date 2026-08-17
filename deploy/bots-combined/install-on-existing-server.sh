#!/usr/bin/env bash
# Installs both Discord bots (Enclave welcome/tracking bot + LSPD bot) on a
# server that ALREADY runs something else -- specifically written for the
# same box described in deploy/enclave-panel/EXISTING-SERVER.md: user
# `enclave` owns /opt/enclave/app (Enclave-RP-Store), and usually user
# `enclave-admin` owns /opt/enclave-admin (the admin panel, if its own
# install-on-existing-server.sh already ran).
#
# This is NOT deploy/bots-combined/setup.sh. That one assumes a fresh
# machine: APP_DIR defaults to /opt/enclave (the SAME path the store's own
# /opt/enclave/app lives under), and its fetch_code() does `rm -rf
# "$APP_DIR"` before a fresh clone if that path isn't already a git repo --
# on this box that would delete the live store. RUN_USER defaults to
# `enclave` too -- the store's own user. Running the generic installer here
# would be destructive; this script exists so that never happens.
#
# Two different trust models, on purpose:
#
#   - The Enclave bot and the admin panel already share ONE Discord bot
#     token and ONE guild -- see admin-panel/README.md, which documents
#     that on the old Railway setup they ran "بنفس سيرفس welcome-bot...
#     يستخدمون نفس DISCORD_TOKEN و GUILD_ID". They also need to share two
#     files on disk: server-events.db (bot writes, panel reads, for the
#     "آخر المغادرين"/"الأكثر تفاعلًا" status-page widgets) and
#     message-templates.json (panel writes when an owner edits the welcome
#     message, bot reads when it sends one). Since they already trust each
#     other with the same token, this script runs the Enclave bot as the
#     SAME `enclave-admin` user the panel uses (creating it if the panel
#     isn't installed yet), in the SAME /opt/enclave-admin checkout,
#     sharing its data/ folder directly. That's not a new trust boundary --
#     it's the one that already existed on Railway -- so there is no
#     cross-user group/permission plumbing to get right.
#
#   - The LSPD bot is a fully separate Discord bot on a fully separate
#     Discord server: different token, different guild, no shared data.
#     It gets its own user, its own checkout, its own env file -- full
#     isolation, since it shares nothing with the Enclave side to begin
#     with.
#
# Neither bot opens an inbound port: PORT is left unset in both units (see
# welcome-bot/bot.js -- the optional health-check server only starts if
# PORT is set). So, like the panel's own installer, this script never
# touches ufw/iptables, and never forces a system Node upgrade if a
# version >=20 is already on the box.
#
# Run as root on the target server (sudo -i, then run this script).

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/vzjRR/discord-rp-builder.git}"
MIN_NODE_MAJOR=20

log() { echo -e "\n\033[1;35m> $*\033[0m"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run this as root: sudo bash $0" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script only supports Debian/Ubuntu (needs apt-get)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ── Node: reuse whatever is already on the box if it's new enough ──────
node_ok=false
if command -v node >/dev/null 2>&1; then
  have_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [[ "$have_major" -ge "$MIN_NODE_MAJOR" ]]; then
    node_ok=true
    log "Using existing Node $(node -v) -- not touching it"
  fi
fi
if [[ "$node_ok" != true ]]; then
  log "Installing Node ${MIN_NODE_MAJOR}.x (none found, or too old)"
  apt-get update -y
  curl -fsSL "https://deb.nodesource.com/setup_${MIN_NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi

# ── Shared build + font deps (the Enclave bot draws welcome images with
#    Arabic text via fontconfig; installing these is additive, nothing
#    existing depends on a specific absence of them) ────────────────────
log "Installing build and font dependencies (only if missing)"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl git build-essential python3 pkg-config \
  fontconfig fonts-noto-core

##############################################################################
# Enclave bot -- shares the admin panel's user, checkout, and data/ folder
##############################################################################
ENCLAVE_DIR="/opt/enclave-admin"
ENCLAVE_DATA="${ENCLAVE_DIR}/data"
ENCLAVE_USER="enclave-admin"
ENCLAVE_ENV="/etc/enclave-admin-bot.env"

log "Enclave bot: user, checkout, data dir"
if ! id -u "$ENCLAVE_USER" >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin "$ENCLAVE_USER"
fi

if [[ -d "$ENCLAVE_DIR/.git" ]]; then
  git -C "$ENCLAVE_DIR" fetch origin master --quiet
  git -C "$ENCLAVE_DIR" reset --hard origin/master --quiet
else
  mkdir -p "$ENCLAVE_DIR"
  git clone --depth 1 "$REPO_URL" "$ENCLAVE_DIR" --quiet
fi
chown -R "$ENCLAVE_USER:$ENCLAVE_USER" "$ENCLAVE_DIR"

mkdir -p "$ENCLAVE_DATA"
chown -R "$ENCLAVE_USER:$ENCLAVE_USER" "$ENCLAVE_DATA"
chmod 750 "$ENCLAVE_DATA"

if [[ ! -f "$ENCLAVE_ENV" ]]; then
  cat > "$ENCLAVE_ENV" <<EOF
# Enclave bot secrets. Use the SAME DISCORD_TOKEN and GUILD_ID as the admin
# panel's /etc/enclave-admin.env, if the panel is installed on this box --
# one Discord bot application, same as the old Railway setup.

DISCORD_TOKEN=
GUILD_ID=

EVENTS_DB_PATH=${ENCLAVE_DATA}/server-events.db
MESSAGE_TEMPLATES_PATH=${ENCLAVE_DATA}/message-templates.json
EOF
  chmod 600 "$ENCLAVE_ENV"
  chown root:root "$ENCLAVE_ENV"
  log "Created $ENCLAVE_ENV -- fill it in before starting the service"
else
  log "$ENCLAVE_ENV already exists -- left untouched"
fi

log "Installing Enclave bot dependencies"
runuser -u "$ENCLAVE_USER" -- bash -c "cd '$ENCLAVE_DIR/welcome-bot' && npm install --omit=dev --no-audit --no-fund"

log "Installing enclave-admin-bot.service"
cat > /etc/systemd/system/enclave-admin-bot.service <<EOF
[Unit]
Description=Enclave welcome/tracking bot
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=${ENCLAVE_USER}
Group=${ENCLAVE_USER}
WorkingDirectory=${ENCLAVE_DIR}/welcome-bot
EnvironmentFile=${ENCLAVE_ENV}
Environment=NODE_ENV=production
Environment=FONTCONFIG_PATH=${ENCLAVE_DIR}/welcome-bot/assets/fonts
Environment=PORT=
Environment=XDG_CACHE_HOME=/var/cache/enclave-admin-bot
ExecStart=/usr/bin/node bot.js
Restart=always
RestartSec=5

MemoryHigh=256M
MemoryMax=384M

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${ENCLAVE_DATA}
ReadWritePaths=${ENCLAVE_DIR}/welcome-bot/assets/fonts
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

StandardOutput=journal
StandardError=journal
SyslogIdentifier=enclave-admin-bot
CacheDirectory=enclave-admin-bot

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

##############################################################################
# LSPD bot -- fully independent: own user, own checkout, own everything
##############################################################################
LSPD_DIR="/opt/lspd-bot"
LSPD_USER="lspd-bot"
LSPD_ENV="/etc/lspd-bot.env"

log "LSPD bot: user, checkout"
if ! id -u "$LSPD_USER" >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin "$LSPD_USER"
fi

if [[ -d "$LSPD_DIR/.git" ]]; then
  git -C "$LSPD_DIR" fetch origin master --quiet
  git -C "$LSPD_DIR" reset --hard origin/master --quiet
else
  mkdir -p "$LSPD_DIR"
  git clone --depth 1 "$REPO_URL" "$LSPD_DIR" --quiet
fi
chown -R "$LSPD_USER:$LSPD_USER" "$LSPD_DIR"

if [[ ! -f "$LSPD_ENV" ]]; then
  cat > "$LSPD_ENV" <<EOF
# LSPD bot secrets -- its own Discord bot application, its own server. NOT
# the same token as the Enclave bot/panel above.

DISCORD_TOKEN=
GUILD_ID=
EOF
  chmod 600 "$LSPD_ENV"
  chown root:root "$LSPD_ENV"
  log "Created $LSPD_ENV -- fill it in before starting the service"
else
  log "$LSPD_ENV already exists -- left untouched"
fi

log "Installing LSPD bot dependencies"
runuser -u "$LSPD_USER" -- bash -c "cd '$LSPD_DIR/lspd-welcome-bot' && npm install --omit=dev --no-audit --no-fund"

log "Installing lspd-bot.service"
cat > /etc/systemd/system/lspd-bot.service <<EOF
[Unit]
Description=LSPD server bot
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=${LSPD_USER}
Group=${LSPD_USER}
WorkingDirectory=${LSPD_DIR}/lspd-welcome-bot
EnvironmentFile=${LSPD_ENV}
Environment=NODE_ENV=production
Environment=PORT=
Environment=XDG_CACHE_HOME=/var/cache/lspd-bot
ExecStart=/usr/bin/node bot.js
Restart=always
RestartSec=5

MemoryHigh=256M
MemoryMax=384M

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
RestrictNamespaces=true
LockPersonality=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

StandardOutput=journal
StandardError=journal
SyslogIdentifier=lspd-bot
CacheDirectory=lspd-bot

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

log "Done. No firewall rule was touched -- neither bot needs one (no inbound port)."
cat <<DONE

Remaining steps:

  1. Fill in secrets:

       nano ${ENCLAVE_ENV}
       nano ${LSPD_ENV}

     ⚠️  Enclave bot's DISCORD_TOKEN and GUILD_ID must match the admin
     panel's /etc/enclave-admin.env (same bot application). LSPD's must
     NOT match either -- it's a different bot on a different server.

  2. Start both:

       systemctl enable --now enclave-admin-bot lspd-bot
       systemctl status enclave-admin-bot lspd-bot --no-pager
       journalctl -u enclave-admin-bot -f

The store's and panel's services, users, ports, and firewall rules were
not touched by any of this.
DONE
