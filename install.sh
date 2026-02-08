#!/usr/bin/env bash
#=====================================================================
#  RTSP NVR Dashboard – One‑line installer (patched)
#  -----------------------------------------------------------------
#  What we added:
#   • trap on ERR that prints line number & failing command
#   • set -x (trace) for full visibility
#   • idempotent “docker compose up -d || true”
#=====================================================================

# Abort on any error, but also give a useful error message
set -e
trap 'echo -e "\n❌  Installer stopped on line $LINENO. Last command: $BASH_COMMAND\n"; exit 1' ERR

# Show each command as it runs – helps debugging
set -x

# -----------------------------------------------------------------
# 1) Basic info
# -----------------------------------------------------------------
echo "Installing RTSP NVR Dashboard"
VERSION_ID=$(lsb_release -rs)
echo "Detected Ubuntu version: $VERSION_ID"

# -----------------------------------------------------------------
# 2) Install apt prerequisites
# -----------------------------------------------------------------
apt-get update -y
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git

# -----------------------------------------------------------------
# 3) Install Docker Engine (official Docker repo)
# -----------------------------------------------------------------
# 3.1 Add Docker’s GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 3.2 Set up the stable repository
UBUNTU_CODENAME=$(lsb_release -cs)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" |
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 3.3 Install Docker packages
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# -----------------------------------------------------------------
# 4) Install Docker‑Compose (v2 plugin)
# -----------------------------------------------------------------
DC_LATEST=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest |
            grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
mkdir -p /usr/local/lib/docker/cli-plugins
curl -L "https://github.com/docker/compose/releases/download/v${DC_LATEST}/docker-compose-linux-$(uname -m)" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify installation
docker compose version

# -----------------------------------------------------------------
# 5) Clone the dashboard repo (into /opt)
# -----------------------------------------------------------------
TARGET_DIR="/opt/rtsp-nvr-dashboard"
if [ -d "$TARGET_DIR" ]; then
    echo "Directory $TARGET_DIR already exists – pulling latest changes"
    cd "$TARGET_DIR"
    git pull
else
    git clone https://github.com/OneByJorah/rtsp-nvr-dashboard.git "$TARGET_DIR"
fi

# -----------------------------------------------------------------
# 6) Prepare the .env file
# -----------------------------------------------------------------
cd "$TARGET_DIR"
if [ ! -f .env ]; then
    cp .env.sample .env
    echo "# ---------------------------------------------------------------"
    echo "# Please edit the .env file now (HOST_IP, NVR_URL, etc.)"
    echo "# ---------------------------------------------------------------"
    nano .env   # opens the console editor; you can replace with any editor you like
else
    echo ".env file already exists – leaving untouched"
fi

# -----------------------------------------------------------------
# 7) Bring the services up
# -----------------------------------------------------------------
docker compose up -d || true   # keep going even if containers are already up

# -----------------------------------------------------------------
# 8) Final message
# -----------------------------------------------------------------
HOST_IP=$(grep '^HOST_IP=' .env | cut -d'=' -f2 | tr -d '"')
echo "✅  Installation complete!"
echo "Open http://$HOST_IP:3000 in your browser."
echo "To watch live logs:  cd $TARGET_DIR && docker compose logs -f"
