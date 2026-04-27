#!/usr/bin/env bash
# dokku-synology installer
# Installs Dokku (as a Docker container) + synology-proxy + synology-dns plugins
# Usage: curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
set -eo pipefail

REPO_URL="https://github.com/pjaol/dokku-synology"
CLONE_DIR="/var/lib/dokku-synology"
RELEASE_URL="https://github.com/pjaol/dokku-synology/releases/latest/download"

# ── helpers ────────────────────────────────────────────────────────────────────
log()  { echo "[dokku-synology] $*"; }
warn() { echo "[dokku-synology] WARN: $*" >&2; }
die()  { echo "[dokku-synology] ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' not found — is $2 installed?"; }

# ── preflight ──────────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run as root (sudo bash install.sh)"

require_cmd docker "Docker (DSM Container Manager)"
require_cmd git    "git"

DSM_CONF_DIR="/usr/local/etc/nginx/conf.d"
[[ -d "$DSM_CONF_DIR" ]] || die "$DSM_CONF_DIR not found — is this Synology DSM 7?"

NGINX_BIN="$(command -v nginx || true)"
[[ -n "$NGINX_BIN" ]] || die "nginx not found on host"

NGINX_PID="/run/nginx.pid"
[[ -f "$NGINX_PID" ]] || die "nginx pid file not found at $NGINX_PID — is DSM nginx running?"

# ── clone repo ─────────────────────────────────────────────────────────────────
log "Cloning $REPO_URL → $CLONE_DIR..."
if [[ -d "$CLONE_DIR/.git" ]]; then
  git -C "$CLONE_DIR" pull --ff-only
else
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

# ── start Dokku container ──────────────────────────────────────────────────────
DOKKU_CONTAINER="$(docker ps -aq --filter name=dokku 2>/dev/null || true)"

if [[ -n "$DOKKU_CONTAINER" ]]; then
  log "Dokku container already exists — skipping start"
else
  log "Starting Dokku container..."
  docker compose -f "${CLONE_DIR}/dokku/dokku-docker-compose.yaml" up -d
  # Fix dns-reload volume permissions — Synology maps container root to non-priv host uid
  DNS_RELOAD_DATA="$(docker volume inspect dokku_dns-reload --format '{{.Mountpoint}}' 2>/dev/null || true)"
  [[ -n "$DNS_RELOAD_DATA" ]] && chmod 777 "$DNS_RELOAD_DATA"
  log "Waiting for Dokku to be ready..."
  for i in $(seq 1 30); do
    if docker exec dokku dokku version &>/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

docker exec dokku dokku version || die "Dokku container did not start correctly"
log "Dokku is running: $(docker exec dokku dokku version)"

# ── install plugins into Dokku ─────────────────────────────────────────────────
for PLUGIN in synology-proxy synology-dns; do
  log "Installing $PLUGIN..."
  docker exec dokku bash -c "
    curl -fsSL '${RELEASE_URL}/${PLUGIN}.tar.gz' | tar -xz -C /tmp --one-top-level=${PLUGIN} &&
    cp -r /tmp/${PLUGIN} /var/lib/dokku/plugins/available/${PLUGIN} &&
    dokku plugin:enable ${PLUGIN} &&
    bash /var/lib/dokku/plugins/available/${PLUGIN}/install
  "
  log "$PLUGIN installed"
done

# ── configure attach networks ─────────────────────────────────────────────────
# Dokku apps can attach to existing Docker networks (e.g. postgres-network, redis-network)
# so they can reach Compose-managed backing services.
# We detect candidate networks and let the user choose which ones to record as defaults.
echo ""
log "Docker network configuration"
log "Dokku apps can be attached to existing Docker networks to reach backing services."
log "(e.g. postgres-network, redis-network)"
echo ""

# List existing bridge/overlay networks, excluding Dokku's own and default Docker nets
CANDIDATE_NETWORKS="$(docker network ls --format '{{.Name}}' | \
  grep -vE '^(bridge|host|none|dokku)$' | sort || true)"

if [[ -n "$CANDIDATE_NETWORKS" ]]; then
  log "Existing Docker networks:"
  echo "$CANDIDATE_NETWORKS" | while read -r net; do echo "    $net"; done
  echo ""
  read -rp "  Enter network names to make available to Dokku apps (space-separated, or leave blank to skip): " SYNO_ATTACH_NETWORKS </dev/tty
else
  log "No existing Docker networks found — skipping network configuration"
  log "You can always attach networks later with:"
  log "  docker exec dokku dokku network:set <app> attach-post-deploy <network>"
  SYNO_ATTACH_NETWORKS=""
fi

if [[ -n "${SYNO_ATTACH_NETWORKS:-}" ]]; then
  docker exec dokku dokku config:set --global SYNO_ATTACH_NETWORKS="${SYNO_ATTACH_NETWORKS}"
  log "Set SYNO_ATTACH_NETWORKS=${SYNO_ATTACH_NETWORKS}"
fi

# ── write wildcard nginx proxy conf for Dokku apps ────────────────────────────
DOKKU_NGINX_CONF="${DSM_CONF_DIR}/dokku-wildcard.conf"
if [[ ! -f "$DOKKU_NGINX_CONF" ]]; then
  log "Writing wildcard nginx proxy conf for Dokku apps..."
  cat > "$DOKKU_NGINX_CONF" <<'NGINX'
# Routes *.dokku.home.arpa → Dokku container on port 8080
# Managed by dokku-synology — do not edit manually
server {
    listen 80;
    server_name ~^.+\.dokku\..+$;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
  "$NGINX_BIN" -s reload
  log "nginx reloaded with Dokku wildcard conf"
fi

# ── done ───────────────────────────────────────────────────────────────────────
echo ""
log "Installation complete!"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Add your SSH public key to Dokku:"
echo "     cat ~/.ssh/id_rsa.pub | ssh root@<nas-ip> 'docker exec -i dokku dokku ssh-keys:add admin'"
echo ""
echo "  2. Configure the DNS plugin:"
echo "     docker exec dokku dokku config:set --global SYNO_DNS_ZONE=<zone> SYNO_NAS_IP=<nas-ip>"
echo "     docker exec dokku dokku synology-dns:test"
echo ""
echo "  3. Verify the proxy plugin:"
echo "     docker exec dokku dokku synology-proxy:test"
echo ""
echo "  4. Deploy an app:"
echo "     git remote add dokku ssh://dokku@<nas-ip>:3022/<appname>"
echo "     git push dokku main"
echo ""

if [[ -n "${SYNO_ATTACH_NETWORKS:-}" ]]; then
  echo "  5. Attach an app to backing service networks (repeat per app):"
  for net in $SYNO_ATTACH_NETWORKS; do
    echo "     docker exec dokku dokku network:set <appname> attach-post-deploy ${net}"
  done
  echo "     Then redeploy: git push dokku main"
  echo ""
fi

echo "  Dokku admin:"
echo "     docker exec dokku dokku apps:list"
echo "     docker exec dokku dokku logs <app>"
