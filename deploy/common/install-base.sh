#!/usr/bin/env bash
# الأساس المشترك بين كل النشرات: الحزم، وNode، ومستخدم التشغيل، والكود.
#
# لا يشغّل شيئًا بنفسه — كل خدمة تستدعيه ثم تكمل ما يخصّها وحدها.
# صالح لإعادة التنفيذ: كل خطوة تتحقق من الحالة قبل أن تغيّرها.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/vzjRR/discord-rp-builder.git}"
APP_DIR="${APP_DIR:-/opt/enclave}"
RUN_USER="${RUN_USER:-enclave}"
NODE_MAJOR="${NODE_MAJOR:-22}"

log() { echo -e "\n\033[1;35m▸ $*\033[0m"; }

install_packages() {
  log "تثبيت الحزم الأساسية"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  # build-essential وpython3 احتياطًا: الوحدات الأصلية (better-sqlite3،
  # sharp، ‏@napi-rs/canvas) لها ثنائيات جاهزة لمعمارية ARM، لكن إن غابت
  # لإصدار ما فالبناء من المصدر يحتاج هذه الأدوات — وغيابها يُفشل التثبيت
  # برسالة غامضة بعد دقائق من الانتظار.
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git \
    build-essential python3 pkg-config \
    fontconfig fonts-noto-core \
    ufw unattended-upgrades
}

install_node() {
  if command -v node >/dev/null 2>&1 && [[ "$(node -p 'process.versions.node.split(".")[0]')" == "$NODE_MAJOR" ]]; then
    log "Node.js $NODE_MAJOR موجود"
    return
  fi
  log "تثبيت Node.js $NODE_MAJOR"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
}

# الخدمات لا تعمل بصلاحية الجذر: خلل في أي منها يبقى محصورًا في ملفاتها.
create_user() {
  if ! id -u "$RUN_USER" >/dev/null 2>&1; then
    log "إنشاء مستخدم التشغيل $RUN_USER"
    useradd --system --create-home --shell /usr/sbin/nologin "$RUN_USER"
  fi
}

fetch_code() {
  log "جلب الكود"
  if [[ -d "$APP_DIR/.git" ]]; then
    git -C "$APP_DIR" fetch origin master --quiet
    git -C "$APP_DIR" reset --hard origin/master --quiet
  else
    rm -rf "$APP_DIR"
    git clone --depth 1 "$REPO_URL" "$APP_DIR" --quiet
  fi
  chown -R "$RUN_USER:$RUN_USER" "$APP_DIR"
}

# لا نفتح منفذًا واردًا للتطبيقات: ما يحتاج وصولًا من الخارج (المنصة) يصله
# عبر نفق Cloudflare، وهو اتصال صادر. فلا عنوان يُكتشف ولا منفذ يُفحص،
# ولا شهادة تُدار على الأصل.
harden_firewall() {
  log "ضبط الجدار الناري"
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow 22/tcp comment 'SSH' >/dev/null
  ufw --force enable >/dev/null
}

# خادم يُنسى بلا ترقيع يصير أضعف حلقة مهما أُحكم التطبيق نفسه.
enable_auto_updates() {
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
}

install_deps() {
  local svc_dir="$1"
  log "تثبيت اعتماديات $svc_dir"
  # --omit=dev: الخادم لا يحتاج أدوات التطوير، وتثبيتها يبطئ ويوسّع
  # مساحة الهجوم بلا مقابل.
  (cd "$APP_DIR/$svc_dir" && npm install --omit=dev --no-audit --no-fund)
  chown -R "$RUN_USER:$RUN_USER" "$APP_DIR/$svc_dir"
}

install_unit() {
  local unit_path="$1"
  log "تركيب خدمة $(basename "$unit_path")"
  cp "$unit_path" /etc/systemd/system/
  systemctl daemon-reload
}

# يكتب ملف أسرار بصلاحية الجذر وحده، ولا يمسّه إن كان موجودًا —
# فإعادة تشغيل السكربت بعد ملء القيم يجب ألا تمحوها.
write_env_template() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  if [[ -f "$path" ]]; then
    echo "   $path موجود — تُرك كما هو"
    return
  fi
  printf '%s\n' "$content" > "$path"
  chmod 600 "$path"
  chown root:root "$path"
  echo "   أُنشئ $path — املأ قيمه قبل التشغيل"
}

base_install() {
  install_packages
  install_node
  create_user
  fetch_code
  harden_firewall
  enable_auto_updates
}
