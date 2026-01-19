#!/bin/bash
#
# notICE Install Script
# One-liner: curl -sSL https://raw.githubusercontent.com/adriancmurray/notICE/main/scripts/install.sh | bash
#

set -e

REPO="adriancmurray/notICE"
INSTALL_DIR="/opt/notICE"
SERVICE_NAME="notice"

echo "╔════════════════════════════════════╗"
echo "║       notICE Installer             ║"
echo "║   Community Safety Alert System    ║"
echo "╚════════════════════════════════════╝"
echo ""

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  linux) BINARY="notICE-linux-$ARCH" ;;
  darwin) BINARY="notICE-darwin-$ARCH" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

echo "→ Detected: $OS/$ARCH"
echo "→ Binary: $BINARY"
echo ""

# Get latest release
echo "→ Fetching latest release..."
RELEASE_URL=$(curl -sSL "https://api.github.com/repos/$REPO/releases/latest" | grep "browser_download_url.*$BINARY.tar.gz" | cut -d '"' -f 4)

if [ -z "$RELEASE_URL" ]; then
  echo "✗ Could not find release for $BINARY"
  exit 1
fi

# Create install directory
echo "→ Creating installation directory..."
sudo mkdir -p "$INSTALL_DIR"

# Download and extract
echo "→ Downloading $BINARY..."
curl -sSL "$RELEASE_URL" | sudo tar -xzf - -C "$INSTALL_DIR"

# Make executable
sudo chmod +x "$INSTALL_DIR/notICE"*

echo ""
echo "→ Creating superuser account..."
read -p "   Admin email: " ADMIN_EMAIL
read -sp "   Admin password: " ADMIN_PASS
echo ""

cd "$INSTALL_DIR"
sudo ./notICE-* superuser upsert "$ADMIN_EMAIL" "$ADMIN_PASS"

# Create systemd service (Linux only)
if [ "$OS" = "linux" ] && command -v systemctl &> /dev/null; then
  echo ""
  echo "→ Creating systemd service..."
  
  sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<EOF
[Unit]
Description=notICE Safety Alert System
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/notICE-linux-$ARCH serve --http 0.0.0.0:8090
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable $SERVICE_NAME
  sudo systemctl start $SERVICE_NAME
  
  echo "→ Service started!"
fi

echo ""
echo "╔════════════════════════════════════╗"
echo "║       Installation Complete!       ║"
echo "╚════════════════════════════════════╝"
echo ""
echo "  Access your instance at:"
echo "  → http://localhost:8090"
echo "  → http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo "your-ip"):8090"
echo ""
echo "  Admin panel: http://localhost:8090/admin.html"
echo ""
echo "  For HTTPS, set up Cloudflare Tunnel or Caddy."
echo ""
