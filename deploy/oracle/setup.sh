#!/usr/bin/env bash
# تهيئة خادم Oracle Cloud من الصفر لتشغيل بوتات السيرفر ومنصة الإدارة.
#
# يُنفَّذ مرة واحدة عند أول إقلاع (عبر cloud-init)، ويصلح لإعادة التنفيذ
# متى شئت: كل خطوة فيه تتحقق من الحالة قبل أن تغيّرها.
#
# لا يحوي هذا الملف أي سرّ. الأسرار تُوضع بعد التهيئة في
# /etc/enclave/enclave.env — لأن ما يُمرَّر إلى cloud-init يبقى مقروءًا في
# بيانات المثيل (metadata) لأي عملية على الخادم.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/vzjRR/discord-rp-builder.git}"
APP_DIR="/opt/enclave"
DATA_DIR="/data"
ENV_DIR="/etc/enclave"
ENV_FILE="$ENV_DIR/enclave.env"
RUN_USER="enclave"
NODE_MAJOR="22"

log() { echo -e "\n\033[1;35m▸ $*\033[0m"; }

# ── ١) الحزم الأساسية ────────────────────────────────────────────
log "تثبيت الحزم الأساسية"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# build-essential وpython3 احتياطًا: الوحدات الأصلية (better-sqlite3،
# sharp، @napi-rs/canvas) لها ثنائيات جاهزة لمعمارية ARM، لكن إن غابت
# لأي إصدار فالبناء من المصدر يحتاج هذه الأدوات — وغيابها يُفشل التثبيت
# برسالة غامضة بعد دقائق من الانتظار.
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git \
  build-essential python3 pkg-config \
  fontconfig fonts-noto-core \
  ufw

# ── ٢) Node.js ───────────────────────────────────────────────────
if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'process.versions.node.split(".")[0]')" != "$NODE_MAJOR" ]]; then
  log "تثبيت Node.js $NODE_MAJOR"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi
node -v

# ── ٣) مستخدم التشغيل ────────────────────────────────────────────
# الخدمات لا تعمل بصلاحية الجذر: خلل في أي منها يبقى محصورًا في ملفاتها.
if ! id -u "$RUN_USER" >/dev/null 2>&1; then
  log "إنشاء مستخدم التشغيل $RUN_USER"
  useradd --system --create-home --shell /usr/sbin/nologin "$RUN_USER"
fi

# ── ٤) الكود ─────────────────────────────────────────────────────
log "جلب الكود"
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch origin master --quiet
  git -C "$APP_DIR" reset --hard origin/master --quiet
else
  rm -rf "$APP_DIR"
  git clone --depth 1 "$REPO_URL" "$APP_DIR" --quiet
fi

# ── ٥) مجلد البيانات والأسرار ────────────────────────────────────
log "تحضير مجلد البيانات والإعدادات"
mkdir -p "$DATA_DIR" "$ENV_DIR"
chown -R "$RUN_USER:$RUN_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'ENVEOF'
# أسرار التشغيل — املأ القيم ثم: systemctl restart enclave-*.service
# هذا الملف لا يُرفع إلى المستودع ولا يظهر في بيانات المثيل.

DISCORD_TOKEN=
GUILD_ID=
SESSION_SECRET=

# المنصة
PUBLIC_BASE_URL=https://enclave-admin.tsh87.com
CLOUDFLARE_SECRET=
REQUIRE_CLOUDFLARE=true
OWNER_NOTIFY_USER_ID=

# مسارات البيانات (تطابق ما كان على الاستضافة السابقة)
SQLITE_PATH=/data/admin.db
EVENTS_DB_PATH=/data/server-events.db
ONBOARDING_MESSAGE_PATH=/data/onboarding-message.json
REVOCATION_MESSAGE_PATH=/data/revocation-message.json
MESSAGE_TEMPLATES_PATH=/data/message-templates.json

ENVEOF
  chmod 600 "$ENV_FILE"
  chown root:root "$ENV_FILE"
  echo "   أُنشئ $ENV_FILE — املأ قيمه قبل التشغيل"
fi

# بوت LSPD يقرأ DISCORD_TOKEN وGUILD_ID نفسيهما، لكن بقيمتين مختلفتين
# (بوت آخر وسيرفر آخر) — فلو شارك الملف السابق لرحّب في السيرفر الخطأ.
LSPD_ENV_FILE="$ENV_DIR/lspd.env"
if [[ ! -f "$LSPD_ENV_FILE" ]]; then
  cat > "$LSPD_ENV_FILE" <<'LSPDEOF'
# أسرار بوت ترحيب LSPD — بوت وسيرفر مختلفان عن الرئيسي
DISCORD_TOKEN=
GUILD_ID=
LSPDEOF
  chmod 600 "$LSPD_ENV_FILE"
  chown root:root "$LSPD_ENV_FILE"
  echo "   أُنشئ $LSPD_ENV_FILE — لبوت LSPD وحده"
fi

# ── ٦) الاعتماديات ───────────────────────────────────────────────
# --omit=dev لأن الخادم لا يحتاج أدوات التطوير، وتثبيتها يبطئ ويوسّع
# مساحة الهجوم بلا مقابل.
for svc in welcome-bot admin-panel lspd-welcome-bot logs-bot; do
  if [[ -f "$APP_DIR/$svc/package.json" ]]; then
    log "تثبيت اعتماديات $svc"
    (cd "$APP_DIR/$svc" && npm install --omit=dev --no-audit --no-fund)
  fi
done

chown -R "$RUN_USER:$RUN_USER" "$APP_DIR"

# ── ٧) خدمات systemd ─────────────────────────────────────────────
log "تركيب خدمات systemd"
cp "$APP_DIR/deploy/oracle/systemd/"*.service /etc/systemd/system/
systemctl daemon-reload

# ── ٨) الجدار الناري ─────────────────────────────────────────────
# لا نفتح أي منفذ وارد للتطبيق: الوصول يأتي عبر نفق Cloudflare الذي
# يفتح اتصالًا صادرًا فقط. هذا يعني أن الخادم غير مكشوف على الإنترنت
# أصلًا — لا عنوان يُكتشف ولا منفذ يُفحص، ولا حاجة إلى شهادة على الأصل.
log "ضبط الجدار الناري"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp comment 'SSH' >/dev/null
ufw --force enable >/dev/null
ufw status verbose | sed 's/^/   /'

log "اكتملت التهيئة"
cat <<'DONE'

الخطوات المتبقية (بالترتيب):

  ١. املأ الأسرار:      nano /etc/enclave/enclave.env
  ٢. استعد النسخة:      node /opt/enclave/admin-panel/scripts/restore-backup.js \
                            /root/enclave-backup.json /data
                        chown -R enclave:enclave /data
  ٣. ثبّت نفق Cloudflare بالرمز الذي نسخته من لوحة Cloudflare:
                        cloudflared service install <TOKEN>
  ٤. شغّل الخدمات:      systemctl enable --now enclave-welcome enclave-panel
                        (وenclave-lspd وenclave-logs إن أردتهما)
  ٥. تابع السجلات:      journalctl -u enclave-panel -f

DONE
