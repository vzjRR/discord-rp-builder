#!/usr/bin/env bash
# Installs the admin panel on a server that is ALREADY running something
# else -- specifically written for a box already running Enclave-RP-Store
# (user `enclave`, app at /opt/enclave/app, env at /etc/enclave.env,
# service `enclave.service`, Caddy bound to ports 80/443, app listening on
# 127.0.0.1:3000). Every name and path below is chosen to collide with
# none of that.
#
# This script is intentionally NOT the same as deploy/enclave-panel/setup.sh.
# That one assumes it owns the whole machine: it resets the firewall,
# installs system-wide packages, and claims /opt/enclave and port 3000
# outright. Doing any of that here would risk the store that is already
# live on this box. This script instead:
#
#   - never touches ufw, iptables, or any firewall/security-list rule --
#     the panel reaches the internet only via an outbound Cloudflare
#     tunnel, so no inbound port ever needs opening for it
#   - never installs or reconfigures Node system-wide if a version that
#     already satisfies the panel's >=20.9.0 requirement is present --
#     the store's own installer already put Node 20 on this box
#   - uses its own user (enclave-admin), its own directory tree
#     (/opt/enclave-admin), its own env file (/etc/enclave-admin.env),
#     and its own systemd unit (enclave-admin-panel.service) -- nothing
#     it creates shares a name or a path with anything the store owns
#   - probes for a free port starting at 3001, since 3000 is already the
#     store's
#
# Run as root on the target server (sudo -i, then run this script).

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/vzjRR/discord-rp-builder.git}"
APP_DIR="/opt/enclave-admin"
DATA_DIR="/opt/enclave-admin/data"
ENV_FILE="/etc/enclave-admin.env"
RUN_USER="enclave-admin"
UNIT_NAME="enclave-admin-panel"
MIN_NODE_MAJOR=20

log() { echo -e "\n\033[1;35m> $*\033[0m"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run this as root: sudo bash $0" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script only supports Debian/Ubuntu (needs apt-get)." >&2
  echo "Your store's own setup.sh assumes the same, so this host should qualify." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ── 1) Node ──────────────────────────────────────────────────────────
# Reuse whatever Node is already on the box if it's new enough. The
# store's installer put Node 20 here; that satisfies the panel's
# >=20.9.0 requirement, so there is no reason to touch it and risk
# disturbing whatever the store expects from the system Node install.
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

# ── 2) Build tools for the one native module the panel needs ──────────
# better-sqlite3 ships prebuilt binaries for common targets; these are
# only needed as a fallback if node-gyp has to compile from source.
log "Installing build dependencies (only if missing)"
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl git build-essential python3 pkg-config

# ── 3) Dedicated user -- not the store's `enclave` user ────────────────
if ! id -u "$RUN_USER" >/dev/null 2>&1; then
  log "Creating user $RUN_USER"
  useradd --system --create-home --shell /usr/sbin/nologin "$RUN_USER"
fi

# ── 4) Code ──────────────────────────────────────────────────────────
log "Fetching code into $APP_DIR"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch origin master --quiet
  git -C "$APP_DIR" reset --hard origin/master --quiet
else
  mkdir -p "$APP_DIR"
  git clone --depth 1 "$REPO_URL" "$APP_DIR" --quiet
fi
chown -R "$RUN_USER:$RUN_USER" "$APP_DIR"

# ── 5) Data directory -- distinct from the store's /opt/enclave/data ──
mkdir -p "$DATA_DIR"
chown -R "$RUN_USER:$RUN_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"

# ── 6) Pick a free port -- 3000 is already the store's ─────────────────
# Uses bash's own /dev/tcp rather than ss/netstat: those aren't
# guaranteed present on every minimal image, and a failed TCP connect is
# exempt from `set -e` here only because it's a while-condition, not a
# standalone command.
port=3001
while (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; do
  exec 3>&- 3<&- 2>/dev/null || true
  port=$((port + 1))
done
log "Panel will listen on 127.0.0.1:${port} (not 3000 -- that's the store's)"

# ── 7) Secrets file -- distinct from the store's /etc/enclave.env ──────
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<ENVEOF
# Panel secrets. Fill these in, then: systemctl restart $UNIT_NAME

DISCORD_TOKEN=
GUILD_ID=
SESSION_SECRET=

PUBLIC_BASE_URL=https://enclave-admin.tsh87.com
CLOUDFLARE_SECRET=
REQUIRE_CLOUDFLARE=true
OWNER_NOTIFY_USER_ID=

# This is the port picked at install time -- it's what the systemd unit
# expects and what your Cloudflare tunnel's "Service" field must target
# (http://localhost:${port}). Change it only if you also update both.
PORT=${port}

SQLITE_PATH=${DATA_DIR}/admin.db
EVENTS_DB_PATH=${DATA_DIR}/server-events.db
ONBOARDING_MESSAGE_PATH=${DATA_DIR}/onboarding-message.json
REVOCATION_MESSAGE_PATH=${DATA_DIR}/revocation-message.json
MESSAGE_TEMPLATES_PATH=${DATA_DIR}/message-templates.json
ENVEOF
  chmod 600 "$ENV_FILE"
  chown root:root "$ENV_FILE"
  log "Created $ENV_FILE -- fill it in before starting the service"
else
  log "$ENV_FILE already exists -- left untouched"
fi

# ── 8) Dependencies ──────────────────────────────────────────────────
log "Installing panel dependencies"
# runuser rather than sudo: we're already root, and runuser is part of
# base util-linux so it's guaranteed present without depending on sudo
# being configured for this fresh system user.
runuser -u "$RUN_USER" -- bash -c "cd '$APP_DIR/admin-panel' && npm install --omit=dev --no-audit --no-fund"

# ── 9) systemd unit -- named and scoped so it can't be confused with
#       the store's enclave.service ─────────────────────────────────
log "Installing $UNIT_NAME.service"
cat > "/etc/systemd/system/${UNIT_NAME}.service" <<EOF
[Unit]
Description=Enclave RP admin panel
After=network-online.target
Wants=network-online.target
# Give up only if it fails repeatedly in a short window, so a bad deploy
# does not spin forever. (These two belong in [Unit], not [Service] --
# systemd silently ignores them in the wrong section rather than erroring,
# which is easy to miss without running `systemd-analyze verify`.)
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${APP_DIR}/admin-panel
EnvironmentFile=${ENV_FILE}
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

# This box already runs a production app. These caps mean a runaway
# panel process gets restarted, never lets it pressure the store or the
# rest of the host for memory.
MemoryHigh=256M
MemoryMax=384M

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DATA_DIR}
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
SyslogIdentifier=${UNIT_NAME}

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

# ── 10) cloudflared -- only if this box doesn't already run one.
#        A second `cloudflared service install` would overwrite an
#        existing tunnel's config, which this box does not appear to
#        have (it uses Caddy + ACME for the store), but we check anyway
#        rather than assume. ────────────────────────────────────────
if systemctl list-unit-files 2>/dev/null | grep -q '^cloudflared\.service'; then
  log "cloudflared already runs on this host -- not touching it"
  echo "   Add a second Public hostname to your EXISTING tunnel instead:"
  echo "   Service = http://localhost:${port}"
elif command -v cloudflared >/dev/null 2>&1; then
  log "cloudflared binary present, no service installed yet -- leaving as is"
else
  log "Installing cloudflared"
  ARCH="$(dpkg --print-architecture)"
  curl -fsSL -o /tmp/cloudflared.deb \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
  dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
  rm -f /tmp/cloudflared.deb
fi

log "Done. No firewall rule was touched -- the panel needs none."
cat <<DONE

Remaining steps:

  1. Fill in secrets (PORT is already set to ${port}):

       nano ${ENV_FILE}

  2. Restore your panel data backup:

       node ${APP_DIR}/admin-panel/scripts/restore-backup.js ~/enclave-backup.json ${DATA_DIR}
       chown -R ${RUN_USER}:${RUN_USER} ${DATA_DIR}

  3. Cloudflare tunnel (skip if one already runs on this host -- see above):

       cloudflared service install <TOKEN-FROM-CLOUDFLARE>

     Public hostname -> Service must be:  http://localhost:${port}

  4. Start it:

       systemctl enable --now ${UNIT_NAME}
       systemctl status ${UNIT_NAME} --no-pager
       journalctl -u ${UNIT_NAME} -f

The store's service, user, ports, and firewall rules were not touched by
any of this.
DONE
