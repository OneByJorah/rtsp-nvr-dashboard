#!/usr/bin/env bash
#=====================================================================
#  RTSP NVR Dashboard – Public, token‑free installer
#=====================================================================
#  What this script does
#   1) Install required APT packages (curl, git, Docker Engine)
#   2) Install Docker‑Compose v2 (CLI plugin)
#   3) Clone / update the dashboard repo into /opt/rtsp-nvr-dashboard
#   4) Create a minimal .env (or copy an existing one)
#   5) Detect the docker‑compose file (any location, sub‑folder, template)
#   6) **Remove any `version:` key** (Docker‑Compose v2 ignores it)
#   7) **Build the images locally** (no pull from GHCR – images are private)
#   8) Start the stack with `docker compose up -d`
#   9) Print the URL to open in a browser and some log‑viewing helpers
#=====================================================================

set -euo pipefail
IFS=$'\n\t'
trap 'echo -e "\n❌  Installer stopped on line $LINENO. Last command: $BASH_COMMAND\n"; exit 1' ERR

# ---------- Helper output ----------
log()   { echo -e "📦  $*"; }
ok()    { echo -e "✅  $*"; }
warn()  { echo -e "⚠️  $*"; }
info()  { echo -e "ℹ️   $*"; }

# Prompt helper (default optional)
prompt() {
    local name="$1"
    local def="${2:-}"
    local ans
    if [[ -n "$def" ]]; then
        read -rp "   $name [$def]: " ans
        echo "${ans:-$def}"
    else
        read -rp "   $name: " ans
        while [[ -z "$ans" ]]; do
            read -rp "   $name (cannot be empty): " ans
        done
        echo "$ans"
    fi
}

# ---------- 1 – Detect Ubuntu / Debian codename ----------
log "Detecting distribution..."
if command -v lsb_release >/dev/null 2>&1; then
    UBUNTU_CODENAME=$(lsb_release -cs)
else
    # Fallback for minimal containers (try /etc/os-release)
    . /etc/os-release
    UBUNTU_CODENAME=$VERSION_CODENAME
fi

# If we are on the development release "noble" (Ubuntu 24.04) fallback to jammy
if [[ "$UBUNTU_CODENAME" == "noble" ]]; then
    warn "Running on Ubuntu 'noble' (development). Using jammy APT sources."
    UBUNTU_CODENAME="jammy"
fi
log "Using codename: $UBUNTU_CODENAME"

# ---------- 2 – Install APT prerequisites (force IPv4) ----------
log "Updating APT index (IPv4 only)"
apt-get -o Acquire::ForceIPv4=true update -y

log "Installing required packages"
apt-get -o Acquire::ForceIPv4=true install -y \
    ca-certificates curl gnupg lsb-release software-properties-common git

# ---------- 3 – Docker Engine ----------
log "Adding Docker GPG key (overwrite without prompting)"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

log "Adding Docker APT repository"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" |
    tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Installing Docker Engine"
apt-get -o Acquire::ForceIPv4=true update -y
apt-get -o Acquire::ForceIPv4=true install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker

# ---------- 4 – Docker‑Compose (v2) ----------
log "Fetching latest Docker‑Compose version"
DC_LATEST=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest |
            grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
log "Latest Docker‑Compose = v$DC_LATEST"

COMPOSE_PATH="/usr/local/lib/docker/cli-plugins/docker-compose"
mkdir -p "$(dirname "$COMPOSE_PATH")"
log "Downloading Docker‑Compose binary"
curl -L "https://github.com/docker/compose/releases/download/v${DC_LATEST}/docker-compose-linux-$(uname -m)" \
    -o "$COMPOSE_PATH"
chmod +x "$COMPOSE_PATH"
docker compose version | head -n1

# ---------- 5 – Clone / update the dashboard ----------
TARGET_DIR="/opt/rtsp-nvr-dashboard"
log "Preparing $TARGET_DIR"
if [[ -d "$TARGET_DIR/.git" ]]; then
    ok "Repo already exists → pulling latest"
    pushd "$TARGET_DIR" > /dev/null
    git fetch --all
    git reset --hard origin/main
    popd > /dev/null
else
    ok "Cloning fresh copy of the dashboard"
    git clone https://github.com/OneByJorah/rtsp-nvr-dashboard.git "$TARGET_DIR"
fi

# ---------- 6 – Ensure a usable .env ----------
cd "$TARGET_DIR"

create_env_interactively() {
    info "No .env template – creating one from prompts."
    HOST_IP=$(prompt "HOST_IP (IP the UI will bind to)" "0.0.0.0")
    NVR_URL=$(prompt "NVR_URL (RTSP URL, e.g. rtsp://user:pass@192.168.1.10:554/stream)")
    ADMIN_USER=$(prompt "ADMIN_USER (web UI login name)" "admin")
    ADMIN_PASSWORD=$(prompt "ADMIN_PASSWORD (web UI password)" "admin")

    cat > .env <<EOF
# -------------------------------------------------
# RTSP‑NVR‑Dashboard – automatically generated .env
# -------------------------------------------------
HOST_IP=$HOST_IP
NVR_URL=$NVR_URL
ADMIN_USER=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASSWORD
EOF
    ok ".env file created."
    cat .env
}

if [[ -f .env ]]; then
    ok ".env already exists – leaving it untouched."
else
    if [[ -f .env.sample ]]; then
        cp .env.sample .env && ok "Copied .env.sample → .env"
    elif [[ -f .env.example ]]; then
        cp .env.example .env && ok "Copied .env.example → .env"
    elif [[ -f .env.default ]]; then
        cp .env.default .env && ok "Copied .env.default → .env"
    else
        warn "No .env template in repo."
        create_env_interactively
    fi
fi

info "Opening .env for final manual edits (Ctrl‑X to keep as‑is)."
if command -v nano >/dev/null 2>&1; then
    nano .env
else
    ${EDITOR:-vi} .env
fi

# ---------- 7️⃣ – Locate docker‑compose file ----------
log "Searching for a docker‑compose definition"

COMPOSE_FILE=$(find . -type f \
    \( -iname 'docker-compose.yml' -o -iname 'docker-compose.yaml' \) \
    -not -path '*/\.*' | head -n1 || true)

# Sub‑folder “docker/” is common
if [[ -z "$COMPOSE_FILE" && -f ./docker/docker-compose.yml ]]; then
    COMPOSE_FILE=./docker/docker-compose.yml
    ok "Found compose file in sub‑folder: $COMPOSE_FILE"
fi

# Any template (example / sample / default)
if [[ -z "$COMPOSE_FILE" ]]; then
    TEMPLATE=$(find . -type f \
        \( -iname '*compose*.example*' -o -iname '*compose*.sample*' -o -iname '*compose*.default*' \) \
        -not -path '*/\.*' | head -n1 || true)
    if [[ -n "$TEMPLATE" ]]; then
        COMPOSE_FILE="./docker-compose.yml"
        cp "$TEMPLATE" "$COMPOSE_FILE"
        ok "Copied template $TEMPLATE → $COMPOSE_FILE"
    fi
fi

# Final fallback – minimal compose that builds locally
if [[ -z "$COMPOSE_FILE" ]]; then
    warn "No compose file found – creating a minimal one that builds locally."
    COMPOSE_FILE="./docker-compose.yml"
    cat > "$COMPOSE_FILE" <<'EOF'
services:
  frontend:
    build: ./frontend
    container_name: rtsp-nvr-frontend
    env_file: ./.env
    ports:
      - "${HOST_IP:-0.0.0.0}:3000:3000"
    restart: unless-stopped

  ffmpeg:
    build: ./ffmpeg
    container_name: rtsp-nvr-ffmpeg
    env_file: ./.env
    restart: unless-stopped
EOF
    ok "Created fallback $COMPOSE_FILE"
fi

ok "Using compose file: $COMPOSE_FILE"

# ---------- 8️⃣ – Remove obsolete `version:` ----------
if grep -qi '^version:' "$COMPOSE_FILE"; then
    warn "Removing obsolete `version:` line (Docker‑Compose v2 no longer uses it)."
    cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak"
    sed -i '/^[[:space:]]*version:/I d' "$COMPOSE_FILE"
fi

# ---------- 9️⃣ – **Build images locally** (NO pull) ----------
log "Building images locally from the repository Dockerfiles"
docker compose -f "$COMPOSE_FILE" build
ok "Local image build completed."

# ---------- 🔟 – Bring the stack up ----------
log "Starting the stack (`docker compose up -d`)"
docker compose -f "$COMPOSE_FILE" up -d

# ---------- 11️⃣ – Final status ----------
log "Waiting a few seconds for containers to initialise…"
sleep 5
log "Current container status"
docker compose -f "$COMPOSE_FILE" ps

# Show the UI address
HOST_IP_TO_SHOW=$(grep '^HOST_IP=' .env | cut -d'=' -f2 | tr -d '"')
HOST_IP_TO_SHOW=${HOST_IP_TO_SHOW:-0.0.0.0}

ok "=============================================================="
ok "✅  Installation complete!"
ok "Open your browser at:   http://$HOST_IP_TO_SHOW:3000"
ok "--------------------------------------------------------------"
ok "Live‑log options (pick one):"
ok "  1) Simple:   docker compose -f \"$COMPOSE_FILE\" logs -f"
ok "  2) Screen:   sudo apt-get install -y screen   # once"
ok "     screen -S nvr-dashboard"
ok "     docker compose -f \"$COMPOSE_FILE\" logs -f"
ok "     # detach with Ctrl‑A D – re‑attach with: screen -r nvr-dashboard"
ok "  3) Tmux:   sudo apt-get install -y tmux && tmux new -s nvr"
ok "     docker compose -f \"$COMPOSE_FILE\" logs -f"
ok "=============================================================="
