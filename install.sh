#!/usr/bin/env bash
# dokku-synology installer
# Starts Dokku as a Docker container and writes a wildcard nginx conf so
# *.dokku.<zone> routes through DSM nginx → Dokku nginx → app containers.
#
# Usage: curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh -o /tmp/install.sh
#        sudo bash /tmp/install.sh
set -eo pipefail

REPO_URL="https://github.com/pjaol/dokku-synology"
CLONE_DIR="/var/lib/dokku-synology"

# ── helpers ────────────────────────────────────────────────────────────────────
log()  { echo "[dokku-synology] $*"; }
die()  { echo "[dokku-synology] ERROR: $*" >&2; exit 1; }

# ── preflight ──────────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run as root (sudo bash install.sh)"

command -v docker &>/dev/null || die "docker not found — is Container Manager installed?"
command -v git    &>/dev/null || die "git not found"

SITES_ENABLED="/etc/nginx/sites-enabled"
[[ -d "$SITES_ENABLED" ]] || die "$SITES_ENABLED not found — is this Synology DSM 7?"

NGINX_BIN="$(command -v nginx || true)"
[[ -n "$NGINX_BIN" ]] || die "nginx not found on host"

[[ -f "/run/nginx.pid" ]] || die "nginx pid not found — is DSM nginx running?"

# ── clone / update repo ────────────────────────────────────────────────────────
log "Fetching dokku-synology → $CLONE_DIR..."
if [[ -d "$CLONE_DIR/.git" ]]; then
  git -C "$CLONE_DIR" pull --ff-only
else
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

# ── start Dokku container ──────────────────────────────────────────────────────
if docker ps -q --filter name=^dokku$ | grep -q .; then
  log "Dokku container already running — skipping start"
else
  log "Starting Dokku container..."
  docker compose -f "${CLONE_DIR}/dokku/dokku-docker-compose.yaml" up -d

  log "Waiting for Dokku to be ready..."
  for i in $(seq 1 30); do
    docker exec dokku dokku version &>/dev/null && break
    sleep 2
  done
fi

docker exec dokku dokku version || die "Dokku container did not start correctly"
log "Dokku is running: $(docker exec dokku dokku version)"

# ── wildcard DNS entry (optional — requires DSM DNS Server package) ────────────
RNDC="/var/packages/DNSServer/target/bin/rndc"
RNDC_KEY="/var/packages/DNSServer/target/named/rndc.key"
ZONE_DIR="/var/packages/DNSServer/target/named/etc/zone/master"

if [[ -x "$RNDC" && -d "$ZONE_DIR" ]]; then
  read -rp "[dokku-synology] DNS zone name (e.g. home.arpa): " SYNO_DNS_ZONE </dev/tty
  read -rp "[dokku-synology] NAS IP address (e.g. 192.168.0.74): " SYNO_NAS_IP </dev/tty

  ZONE_FILE="${ZONE_DIR}/${SYNO_DNS_ZONE}"
  WILDCARD_RECORD="*.dokku.${SYNO_DNS_ZONE}.    86400   A   ${SYNO_NAS_IP}"

  if [[ -f "$ZONE_FILE" ]]; then
    if grep -q '^\*\.dokku\.' "$ZONE_FILE"; then
      log "Wildcard DNS entry already exists — skipping"
    else
      sed -i "/^${SYNO_DNS_ZONE}\.[[:space:]]*NS/i ${WILDCARD_RECORD}" "$ZONE_FILE"
      "$RNDC" -k "$RNDC_KEY" reload "$SYNO_DNS_ZONE"
      log "Added *.dokku.${SYNO_DNS_ZONE} → ${SYNO_NAS_IP} and reloaded named"
    fi
  else
    log "Zone file not found at $ZONE_FILE — skipping DNS entry"
    log "Add manually: ${WILDCARD_RECORD}"
  fi
else
  log "DSM DNS Server not found — skipping wildcard DNS entry"
  log "Ensure your router forwards *.dokku.<zone> queries to this NAS"
fi

# ── generate self-signed wildcard cert ────────────────────────────────────────
CERT_DIR="/etc/nginx"
CERT_FILE="${CERT_DIR}/dokku-wildcard.crt"
KEY_FILE="${CERT_DIR}/dokku-wildcard.key"
if [[ ! -f "$CERT_FILE" ]]; then
  log "Generating self-signed wildcard cert for *.dokku.<zone>..."
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/CN=*.dokku.home.arpa" \
    -addext "subjectAltName=DNS:*.dokku.home.arpa" 2>/dev/null
  log "Cert written to $CERT_FILE"
else
  log "Wildcard cert already exists — skipping"
fi

# ── write wildcard nginx conf ──────────────────────────────────────────────────
WILDCARD_CONF="${SITES_ENABLED}/dokku-wildcard.conf"
if [[ ! -f "$WILDCARD_CONF" ]]; then
  log "Writing wildcard nginx conf → $WILDCARD_CONF"
  cat > "$WILDCARD_CONF" <<NGINX
# Routes *.dokku.<zone> → Dokku container
# Managed by dokku-synology — do not edit manually
server {
    listen 80;
    server_name ~^.+\.dokku\..+\$;

    access_log /var/log/nginx/dokku.access.log;
    error_log  /var/log/nginx/dokku.error.log;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name ~^.+\.dokku\..+\$;

    ssl_certificate     ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};

    access_log /var/log/nginx/dokku.access.log;
    error_log  /var/log/nginx/dokku.error.log;

    location / {
        proxy_pass https://127.0.0.1:8443;
        proxy_ssl_verify off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
NGINX
  "$NGINX_BIN" -s reload
  log "DSM nginx reloaded"
else
  log "Wildcard conf already exists at $WILDCARD_CONF — skipping"
fi

# ── done ───────────────────────────────────────────────────────────────────────
echo ""
log "Installation complete!"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Add your SSH public key (run from your dev machine):"
echo "     cat ~/.ssh/id_rsa.pub | ssh root@<nas-ip> 'docker exec -i dokku dokku ssh-keys:add admin'"
echo ""
echo "  2. Deploy an app:"
echo "     git remote add dokku ssh://dokku@<nas-ip>:3022/<appname>"
echo "     git push dokku main"
echo ""
echo "     Your app will be available at: http://<appname>.dokku.home.arpa"
echo ""
echo "  Dokku admin:"
echo "     docker exec dokku dokku apps:list"
echo "     docker exec dokku dokku logs <app>"
echo ""
