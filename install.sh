#!/usr/bin/env bash
# dokku-synology installer
# Usage: curl -fsSL https://raw.githubusercontent.com/pjaol/dokku-synology/main/install.sh | sudo bash
set -eo pipefail

REPO_URL="https://github.com/pjaol/dokku-synology"
RAW_URL="https://raw.githubusercontent.com/pjaol/dokku-synology/main"
DOKKU_PLUGIN_DIR="/var/lib/dokku/plugins/available"

# ── helpers ────────────────────────────────────────────────────────────────────
log()  { echo "[dokku-synology] $*"; }
warn() { echo "[dokku-synology] WARN: $*" >&2; }
die()  { echo "[dokku-synology] ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' not found — is $2 installed?"; }

# ── preflight ──────────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run as root (sudo bash install.sh)"

require_cmd dokku  "Dokku"
require_cmd nginx  "DSM nginx"
require_cmd docker "Docker"

DSM_CONF_DIR="/usr/local/etc/nginx/conf.d"
[[ -d "$DSM_CONF_DIR" ]] || die "$DSM_CONF_DIR not found — is this Synology DSM 7?"

# ── menu ───────────────────────────────────────────────────────────────────────
INSTALL_PROXY=true
INSTALL_DNS=false

NAMED_BASE="/var/packages/DNSServer/target/named"
if [[ -d "$NAMED_BASE" ]] && command -v rndc &>/dev/null; then
  INSTALL_DNS=true
  log "DNS Server package detected — will install both plugins"
else
  warn "DNS Server package not found — installing proxy plugin only"
  warn "Install Synology DNS Server package and re-run to enable DNS automation"
fi

# ── install proxy plugin ───────────────────────────────────────────────────────
install_plugin() {
  local NAME="$1"
  local SRC="plugins/${NAME}"
  local DEST="${DOKKU_PLUGIN_DIR}/${NAME}"

  log "Installing $NAME..."

  if [[ -d "$DEST" ]]; then
    log "$NAME already installed — updating"
    rm -rf "$DEST"
  fi

  mkdir -p "$DEST/hooks"

  # Download each file
  for f in plugin.toml install; do
    curl -fsSL "${RAW_URL}/${SRC}/${f}" -o "${DEST}/${f}"
  done

  for hook in $(curl -fsSL "${RAW_URL}/${SRC}/hooks/" 2>/dev/null | grep -oP '(?<=href=")[^"]*(?=")' | grep -v '^\.' || true); do
    curl -fsSL "${RAW_URL}/${SRC}/hooks/${hook}" -o "${DEST}/hooks/${hook}"
    chmod +x "${DEST}/hooks/${hook}"
  done

  chmod +x "${DEST}/install" 2>/dev/null || true

  dokku plugin:enable "$NAME" 2>/dev/null || true
  log "$NAME installed"
}

# ── alternative: clone and symlink ─────────────────────────────────────────────
CLONE_DIR="/var/lib/dokku/plugins/src/dokku-synology"

log "Cloning $REPO_URL..."
if [[ -d "$CLONE_DIR" ]]; then
  git -C "$CLONE_DIR" pull --ff-only
else
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

# Symlink each plugin into Dokku's available plugins dir
for PLUGIN in synology-proxy synology-dns; do
  SRC="${CLONE_DIR}/plugins/${PLUGIN}"
  DEST="${DOKKU_PLUGIN_DIR}/${PLUGIN}"

  if [[ "$PLUGIN" == "synology-dns" ]] && [[ "$INSTALL_DNS" != "true" ]]; then
    continue
  fi

  [[ -d "$SRC" ]] || { warn "Plugin source not found: $SRC"; continue; }

  if [[ -L "$DEST" ]]; then
    rm "$DEST"
  elif [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
  fi

  ln -s "$SRC" "$DEST"
  chmod +x "$SRC"/hooks/* "$SRC/install" 2>/dev/null || true

  dokku plugin:enable "$PLUGIN"
  log "Enabled $PLUGIN"
done

# ── configure DNS plugin ────────────────────────────────────────────────────────
if [[ "$INSTALL_DNS" == "true" ]]; then
  echo ""
  log "DNS plugin configuration"

  if [[ -z "${SYNO_DNS_ZONE:-}" ]]; then
    read -rp "  DNS zone (e.g. home.arpa): " SYNO_DNS_ZONE
  fi
  if [[ -z "${SYNO_NAS_IP:-}" ]]; then
    # Auto-detect NAS IP from the zone file if possible
    ZONE_FILE="${NAMED_BASE}/etc/zone/master/${SYNO_DNS_ZONE}"
    DETECTED_IP=""
    if [[ -f "$ZONE_FILE" ]]; then
      DETECTED_IP="$(grep -oP '(?<=A\s{1,20})\d+\.\d+\.\d+\.\d+' "$ZONE_FILE" | head -1 || true)"
    fi
    read -rp "  NAS IP address [${DETECTED_IP:-192.168.0.x}]: " SYNO_NAS_IP
    SYNO_NAS_IP="${SYNO_NAS_IP:-$DETECTED_IP}"
  fi

  dokku config:set --global SYNO_DNS_ZONE="$SYNO_DNS_ZONE"
  dokku config:set --global SYNO_NAS_IP="$SYNO_NAS_IP"
  log "Set SYNO_DNS_ZONE=$SYNO_DNS_ZONE SYNO_NAS_IP=$SYNO_NAS_IP"
fi

# ── done ───────────────────────────────────────────────────────────────────────
echo ""
log "Installation complete!"
echo ""
echo "  Next steps:"
echo "  1. Move DSM web UI off port 80/443 if you haven't already:"
echo "     DSM → Control Panel → Login Portal → change HTTP to 8880, HTTPS to 8443"
echo ""
echo "  2. Set your app's proxy type:"
echo "     dokku proxy:set <app> synology"
echo ""
echo "  3. Set a domain:"
echo "     dokku domains:set <app> myapp.${SYNO_DNS_ZONE:-home.arpa}"
echo ""
echo "  4. Deploy — nginx conf and DNS record are managed automatically."
