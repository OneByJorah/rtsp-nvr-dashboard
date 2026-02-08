#!/usr/bin/env bash
#=====================================================================
#  RTSP NVR Dashboard – Full‑featured installer (patched)
#=====================================================================
#  What this script does
#  --------------------
#   1) Installs required APT packages (curl, git, Docker Engine, …)
#   2) Installs Docker‑Compose v2 as a CLI plugin
#   3) Clones or updates the dashboard repo into /opt/rtsp-nvr-dashboard
#   4) Guarantees a usable .env file:
#        • If a template (.env.sample/.env.example/…) exists → copy it.
#        • If no template → auto‑create a minimal .env and ask the user
#          for every required key (HOST_IP, NVR_URL, ADMIN_USER, ADMIN_PASSWORD …)
#   5) Starts the docker‑compose stack
#   6) Shows a final “open in browser” hint + how to watch live logs
#=====================================================================

# ---------- 0 – Safety net ----------
set -euo pipefail                       # exit on error, undefined var, pipe fail
IFS=$'\n\t'                              # sane field splitting

# On any error print a nice line‑number/message before exiting
trap 'echo -e "\n❌  Installer stopped on line $LINENO. Last command: $BASH_COMMAND\n"; exit 1' ERR

# ---------- 1 – Helper functions ----------
log()   { echo -e "📦  $*"; }
warn()  { echo -e "⚠️  $*"; }
ok()    { echo -e "✅  $*"; }
info()  { echo -e "ℹ️   $*"; }

# Prompt the user for a value, allowing a default.
#   $1 = variable name (for the prompt)
#   $2 = default value (optional)
prompt() {
    local var_name="$1"
    local default="${2:-}"
    local read_val

    if [[ -n "$default" ]]; then
        read -rp "   $var_name [$default]: " read_val
        echo "${read_val:-$default}"
    else
        read -rp "   $var_name: " read_val
        # keep prompting until we get something non‑empty
        while [[ -z "$read_val" ]]; do
            read -rp "   $var_name (cannot be empty): " read_val
        done
        echo "$read_val"
    fi
}

# ---------- 2 – Basic system information ----------
log "Detecting Ubuntu version"
UBUNTU_CODENAME=$(lsb_release -cs)
log "Ubuntu codename: $UBUNTU_CODENAME"

# ---------- 3 – Install APT prerequisites ----------
log "Updating package index"
apt-get update -y

log "Installing prerequisite packages"
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git

# ---------- 4 – Install Docker Engine ----------
log "Adding Docker’s official GPG key"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

log "Setting up the Docker APT repository"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" |
    tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Installing Docker Engine"
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# Enable Docker to start on boot (and start it now)
systemctl enable --now docker

# ---------- 5 – Install Docker‑Compose (v2 plugin) ----------
log "Fetching latest Docker‑Compose version"
DC_LATEST=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest |
            grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
log "Latest Docker‑Compose = v$DC_LATEST"

log "Installing Docker‑Compose CLI plugin"
COMPOSE_PATH="/usr/local/lib/docker/cli-plugins/docker-compose"
mkdir -p "$(dirname "$COMPOSE_PATH")"
curl -L "https://github.com/docker/compose/releases/download/v${DC_LATEST}/docker-compose-linux-$(uname -m)" \
    -o "$COMPOSE_PATH"
chmod +x "$COMPOSE_PATH"

# Verify it works
docker compose version | head -n1

# ---------- 6 – Clone / update the dashboard repo ----------
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

# ---------- 7 – Ensure a usable .env file ----------
cd "$TARGET_DIR"

# Function that creates a minimal .env from user prompts
create_env_interactively() {
    info "Creating a new .env file from scratch – you will be asked for each value."

    # Change / add keys here if the project later adds more required vars
    HOST_IP=$(prompt "HOST_IP (IP that will host the UI)" "0.0.0.0")
    NVR_URL=$(prompt "NVR_URL (RTSP URL, e.g. rtsp://user:pass@192.168.1.10:554/stream)")
    ADMIN_USER=$(prompt "ADMIN_USER (web UI username)" "admin")
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

    ok ".env file created. Please double‑check the values."
    cat .env
}

# Try to copy an existing template; if none, fall back to interactive creation
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
        warn "No .env template found in the repository."
        create_env_interactively
    fi
fi

# Give the user one last chance to edit the file (nano is the default, change if you prefer)
info "Opening .env for final edits (you can press Ctrl‑X to keep it as‑is)."
if command -v nano >/dev/null 2>&1; then
    nano .env
else
    ${EDITOR:-vi} .env
fi

# ---------- 8 – Start the Docker‑Compose stack ----------
log "Bringing up the Docker‑Compose stack (detached)…"
docker compose up -d

# ---------- 9 – Final status ----------
log "Waiting a few seconds for containers to settle…"
sleep 5

log "Fetching container status"
docker compose ps

# Resolve the address to show the user
HOST_IP_TO_SHOW=$(grep '^HOST_IP=' .env | cut -d'=' -f2 | tr -d '"')
if [[ -z "$HOST_IP_TO_SHOW" ]]; then
    HOST_IP_TO_SHOW="0.0.0.0"
fi

ok "=============================================================="
ok "✅  Installation complete!"
ok "Open your browser at:   http://$HOST_IP_TO_SHOW:3000"
ok "--------------------------------------------------------------"
ok "If you want to watch live logs, you have three easy options:"
ok "  1) Simple:   docker compose logs -f"
ok "  2) Screen (persistent):"
ok "       sudo apt-get install -y screen   # once"
ok "       screen -S nvr-dashboard"
ok "       docker compose logs -f"
ok "       # detach with Ctrl‑A D   – re‑attach with: screen -r nvr-dashboard"
ok "  3) Tmux (if you prefer):"
ok "       sudo apt-get install -y tmux && tmux new -s nvr"
ok "       docker compose logs -f"
ok "=============================================================="
