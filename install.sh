#!/usr/bin/env bash
#=====================================================================
#  RTSP NVR Dashboard – Robust installer (auto .env, Docker, logs)
#=====================================================================
#  What this script does:
#   1) Installs APT prerequisites (curl, git, Docker Engine)
#   2) Installs Docker‑Compose v2 (CLI plugin)
#   3) Clones / updates the dashboard repo into /opt/rtsp-nvr-dashboard
#   4) Guarantees a usable .env (copy template or interactive creation)
#   5) Detects a docker‑compose file, creates a minimal fallback if needed
#   6) Starts the stack with `docker compose -f <file> up -d`
#   7) Shows final instructions + live‑log helpers
#=====================================================================

set -euo pipefail
IFS=$'\n\t'
trap 'echo -e "\n❌  Installer stopped on line $LINENO. Last command: $BASH_COMMAND\n"; exit 1' ERR

# ---------- Helper functions ----------
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

# ---------- 1 – Detect Ubuntu version ----------
log "Detecting Ubuntu version"
UBUNTU_CODENAME=$(lsb_release -cs)

# Ubuntu 24.04 (noble) does not have a public archive yet.
# If we are on a development release, fall back to a supported LTS (jammy).
if [[ "$UBUNTU_CODENAME" == "noble" ]]; then
    warn "You are on Ubuntu 'noble', which is still in development."
    warn "For the purpose of this installer we will treat it as 'jammy' (22.04 LTS)."
    UBUNTU_CODENAME="jammy"
fi
log "Using Ubuntu codename: $UBUNTU_CODENAME"

# ---------- 2 – Install APT prerequisites ----------
log "Updating APT index (forcing IPv4)"
# Force IPv4 – avoids the “Network is unreachable” IPv6 messages
apt-get -o Acquire::ForceIPv4=true update -y

log "Installing required packages"
apt-get -o Acquire::ForceIPv4=true install -y \
    ca-certificates curl gnupg lsb-release software-properties-common git

# ---------- 3 – Docker Engine ----------
log "Adding Docker GPG key (overwrites existing one without prompting)"
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
log "Fetching latest Docker‑Compose version tag"
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
    ok "Repo already exists → pulling latest changes"
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
    info "No .env template – creating a minimal one from prompts."

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
        warn "No .env template found in the repo."
        create_env_interactively
    fi
fi

info "Opening .env for final manual edits (Ctrl‑X to keep as‑is)."
if command -v nano >/dev/null 2>&1; then
    nano .env
else
    ${EDITOR:-vi} .env
fi

# ---------- 7️⃣ – Detect or create a docker‑compose file ----------
log "Searching for a docker‑compose definition"

# 1️⃣ Normal file name
COMPOSE_FILE=$(find . -type f \
    \( -iname 'docker-compose.yml' -o -iname 'docker-compose.yaml' \) \
    -not -path '*/\.*' | head -n1 || true)

# 2️⃣ Common sub‑folder “docker/”
if [[ -z "$COMPOSE_FILE" && -f ./docker/docker-compose.yml ]]; then
    COMPOSE_FILE=./docker/docker-compose.yml
    ok "Found compose file in sub‑folder: $COMPOSE_FILE"
fi

# 3️⃣ Look for any template (example / sample / default) and copy‑rename it
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

# 4️⃣ If STILL nothing, create a *minimal* default compose file.
if [[ -z "$COMPOSE_FILE" ]]; then
    warn "No compose file found anywhere – creating a minimal default one."
    COMPOSE_FILE="./docker-compose.yml"
    cat > "$COMPOSE_FILE" <<'EOF'
# -------------------------------------------------------------------------
# Minimal docker‑compose file for rtsp‑nvr‑dashboard.
# It pulls the official images published by the project and uses the
# variables from the .env file (HOST_IP, NVR_URL, ADMIN_*).
# -------------------------------------------------------------------------
version: "3.8"

services:
  # Web UI (frontend)
  frontend:
    image: ghcr.io/onebyjorah/rtsp-nvr-dashboard-frontend:latest
    container_name: rtsp-nvr-frontend
    env_file: ./.env
    ports:
      - "${HOST_IP:-0.0.0.0}:3000:3000"
    restart: unless-stopped

  # FFmpeg worker – consumes the RTSP feed
  ffmpeg:
    image: ghcr.io/onebyjorah/rtsp-nvr-dashboard-ffmpeg:latest
    container_name: rtsp-nvr-ffmpeg
    env_file: ./.env
    restart: unless-stopped
EOF
    ok "Created minimal $COMPOSE_FILE"
fi

ok "Using compose file: $COMPOSE_FILE"

# ---------- 8️⃣ – Bring the stack up ----------
log "Running: docker compose -f \"$COMPOSE_FILE\" up -d"
docker compose -f "$COMPOSE_FILE" up -d

# ---------- 9️⃣ – Final status ----------
log "Waiting a few seconds for containers to initialise…"
sleep 5
log "Current container status"
docker compose -f "$COMPOSE_FILE" ps

# Show user the address to open
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
