#!/usr/bin/env bash
# Installs the image-points bot on a server that ALREADY runs the admin
# panel (and usually Enclave-RP-Store too) — the same box described in
# deploy/enclave-panel/EXISTING-SERVER.md and deploy/bots-combined/EXISTING-SERVER.md.
#
# Like deploy/bots-combined/install-on-existing-server.sh (the "Enclave"
# welcome/tracking bot), this bot uses the SAME Discord application/token as
# the panel and welcome-bot (app id 1535663542420643880) -- Discord allows
# one bot token to power multiple simultaneous gateway connections, so
# there's no conflict. It gets its own secrets file and its own systemd
# unit anyway (so it can be restarted/stopped independently), but the
# DISCORD_TOKEN value inside should be copied from /etc/enclave-admin-bot.env
# (or any other file using the same Enclave application). What it also
# shares with the panel: the `enclave-admin` Linux user and the
# /opt/enclave-admin checkout + data/ folder, because points.db must be
# readable AND writable by both processes (the bot counts image messages
# automatically; the panel's "points.manage" permission writes manual
# adjustments/resets directly into the same file -- there's no REST bridge
# between the two, same reasoning as server-events.db in bots-combined).
# WAL mode makes that safe.
#
# This bot needs zero Discord server-management permissions and no
# privileged intent beyond MESSAGE CONTENT (to read attachments/embeds on
# non-bot messages) — it never kicks, bans, or manages roles/channels. It
# doesn't open an inbound port either (PORT is left unset in its unit).
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

# build-essential/python3: better-sqlite3 falls back to compiling from
# source if no prebuilt binary matches this Node/OS/arch combo.
log "Installing build dependencies (only if missing)"
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl git build-essential python3 pkg-config

##############################################################################
# points-bot -- shares the admin panel's user, checkout, and data/ folder
##############################################################################
ENCLAVE_DIR="/opt/enclave-admin"
ENCLAVE_DATA="${ENCLAVE_DIR}/data"
ENCLAVE_USER="enclave-admin"
POINTS_ENV="/etc/enclave-points-bot.env"

log "points-bot: user, checkout, data dir"
if ! id -u "$ENCLAVE_USER" >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin "$ENCLAVE_USER"
fi

# Same "dubious ownership" issue as the other installers in this repo: root
# running git against a checkout owned by enclave-admin.
git config --global --add safe.directory "$ENCLAVE_DIR"

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

# DISCORD_TOKEN can be pre-supplied by exporting it before running this
# script (DISCORD_TOKEN='...' bash <(curl ...)). If it's not supplied, fall
# back to copying it from the existing Enclave-bot secrets file, since this
# bot uses the same application/token as welcome-bot/logs-bot/the panel --
# no separate Discord application needed. Never printed or logged below.
if [[ -z "${DISCORD_TOKEN:-}" && -f /etc/enclave-admin-bot.env ]]; then
  DISCORD_TOKEN="$(grep -oP '^DISCORD_TOKEN=\K\S+' /etc/enclave-admin-bot.env || true)"
  [[ -n "$DISCORD_TOKEN" ]] && log "No DISCORD_TOKEN supplied -- reusing the one from /etc/enclave-admin-bot.env (same Enclave application)"
fi

if [[ ! -f "$POINTS_ENV" ]]; then
  cat > "$POINTS_ENV" <<EOF
# points-bot secrets. Uses the SAME Discord application/token as
# welcome-bot/logs-bot/the panel (app id 1535663542420643880) -- Discord
# allows one bot token to run several gateway connections at once, so this
# is expected, not a bug. Kept in its own file so this service can be
# restarted independently of the others.

DISCORD_TOKEN=${DISCORD_TOKEN:-}
IMAGE_POINTS_CHANNEL_ID=1535680167576608910

EVENTS_DB_PATH=${ENCLAVE_DATA}/server-events.db
AUDIT_LOG_FILE_PATH=/var/log/enclave/audit.log

TIMEZONE=Asia/Muscat
WEEK_START_DAY=MONDAY
REMOVE_POINTS_ON_MESSAGE_DELETE=false
ADJUST_POINTS_ON_MESSAGE_EDIT=true
EOF
  chmod 600 "$POINTS_ENV"
  chown root:root "$POINTS_ENV"
  if [[ -n "${DISCORD_TOKEN:-}" ]]; then
    log "Created $POINTS_ENV with the supplied DISCORD_TOKEN"
  else
    log "Created $POINTS_ENV -- fill in DISCORD_TOKEN before starting the service"
  fi
elif [[ -n "${DISCORD_TOKEN:-}" ]] && grep -q '^DISCORD_TOKEN=$' "$POINTS_ENV"; then
  # File exists from a previous run but the token was never filled in --
  # patch just that line in place, don't touch anything else in the file.
  sed -i "s|^DISCORD_TOKEN=\$|DISCORD_TOKEN=${DISCORD_TOKEN}|" "$POINTS_ENV"
  log "$POINTS_ENV already existed -- filled in the supplied DISCORD_TOKEN, left everything else untouched"
else
  log "$POINTS_ENV already exists -- left untouched"
fi

log "Installing points-bot dependencies"
runuser -u "$ENCLAVE_USER" -- bash -c "cd '$ENCLAVE_DIR/points-bot' && npm install --omit=dev --no-audit --no-fund"

log "Installing enclave-points-bot.service"
cat > /etc/systemd/system/enclave-points-bot.service <<EOF
[Unit]
Description=Enclave image-points bot
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=${ENCLAVE_USER}
Group=${ENCLAVE_USER}
WorkingDirectory=${ENCLAVE_DIR}/points-bot
EnvironmentFile=${POINTS_ENV}
Environment=NODE_ENV=production
Environment=PORT=
ExecStart=/usr/bin/node bot.js
Restart=always
RestartSec=5

MemoryHigh=192M
MemoryMax=320M

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${ENCLAVE_DATA}
ReadWritePaths=/var/log/enclave
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
SyslogIdentifier=enclave-points-bot
CacheDirectory=enclave-points-bot

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

log "Done. No firewall rule was touched -- the bot doesn't need one (no inbound port)."

if grep -q '^DISCORD_TOKEN=$' "$POINTS_ENV"; then
  TOKEN_STEP="  1. DISCORD_TOKEN is empty in ${POINTS_ENV} -- copy it from the
     existing Enclave bot's secrets, e.g.:

       TOKEN=\$(grep -oP '^DISCORD_TOKEN=\K\S+' /etc/enclave-admin-bot.env)
       sed -i \"s|^DISCORD_TOKEN=.*|DISCORD_TOKEN=\${TOKEN}|\" ${POINTS_ENV}
"
else
  TOKEN_STEP="  1. DISCORD_TOKEN is already set in ${POINTS_ENV} -- nothing to fill in.
"
fi

cat <<DONE

Remaining steps:

${TOKEN_STEP}
  2. Message Content Intent: this bot shares the Enclave application, and
     logs-bot already requires MESSAGE CONTENT INTENT on it, so it's likely
     already enabled. Double check under Discord Developer Portal -> your
     Enclave application -> Bot -> Privileged Gateway Intents if unsure.

  3. Start it:

       systemctl enable --now enclave-points-bot
       systemctl status enclave-points-bot --no-pager
       journalctl -u enclave-points-bot -f

The store's, panel's, and Enclave-bot's services, users, ports, and
firewall rules were not touched by any of this. If admin-panel is already
running on this box, restart it too so it picks up the new /points page:

       systemctl restart enclave-admin-panel
DONE
