# notICE Deployment Guide

This guide covers deploying notICE for a city or region.

## Prerequisites

- A VPS with SSH access (DigitalOcean, Hetzner, Linode, etc.)
- A domain name pointing to your server
- A Telegram bot (created via [@BotFather](https://t.me/botfather))

## 1. Server Setup

### Create a VPS

Recommended specs:
- **OS**: Ubuntu 22.04 LTS
- **RAM**: 1GB minimum (2GB recommended)
- **Storage**: 20GB SSD
- **Location**: Choose a region close to your users

### Initial Configuration

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Create a user for PocketBase
sudo useradd -m -s /bin/bash notice
sudo mkdir -p /opt/notice
sudo chown notice:notice /opt/notice
```

## 2. PocketBase Installation

```bash
# Download latest PocketBase (check https://pocketbase.io/docs/)
cd /opt/notice
wget https://github.com/pocketbase/pocketbase/releases/download/v0.25.0/pocketbase_0.25.0_linux_amd64.zip
unzip pocketbase_0.25.0_linux_amd64.zip
rm pocketbase_0.25.0_linux_amd64.zip

# Copy hooks from your repo
mkdir -p pb_hooks
# Copy telegram.pb.js to pb_hooks/

# Make executable
chmod +x pocketbase
```

## 3. SSL with Caddy (Recommended)

Caddy automatically handles SSL certificates via Let's Encrypt.

```bash
# Install Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### Configure Caddy

Create `/etc/caddy/Caddyfile`:

```caddyfile
notice.yourcity.gov {
    reverse_proxy localhost:8090
}
```

```bash
sudo systemctl reload caddy
```

## 4. Create Systemd Service

Create `/etc/systemd/system/notice.service`:

```ini
[Unit]
Description=notICE PocketBase Server
After=network.target

[Service]
Type=simple
User=notice
WorkingDirectory=/opt/notice
Environment=TELEGRAM_BOT_TOKEN=your-bot-token-here
Environment=TELEGRAM_CHAT_ID=-1001234567890
ExecStart=/opt/notice/pocketbase serve --http=0.0.0.0:8090
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable notice
sudo systemctl start notice
```

## 5. Import Schema

1. Open `https://notice.yourcity.gov/_/` in your browser
2. Create an admin account
3. Go to **Settings** > **Import collections**
4. Paste the contents of `backend/pb_schema.json`
5. Click **Review** then **Confirm**

## 6. Telegram Bot Setup

### Create the Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot`
3. Follow prompts to name your bot (e.g., "YourCity notICE Alerts")
4. Copy the token (looks like `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Create a Channel

1. Create a new Telegram channel (e.g., "YourCity Safety Alerts")
2. Make the bot an administrator of the channel
3. Get the chat ID:
   - Send a message to the channel
   - Visit `https://api.telegram.org/bot<TOKEN>/getUpdates`
   - Find `"chat":{"id":-100XXXXXXXXX}` in the response

### Update Environment

Update the systemd service with your bot token and chat ID:

```bash
sudo systemctl edit notice
```

Add:
```ini
[Service]
Environment=TELEGRAM_BOT_TOKEN=123456789:ABCdefGHI...
Environment=TELEGRAM_CHAT_ID=-1001234567890
```

```bash
sudo systemctl restart notice
```

## 7. Build the App

### Configure the Server URL

Edit `app/lib/config/app_config.dart` or use build-time configuration:

```bash
cd app
flutter build apk --dart-define=POCKETBASE_URL=https://notice.yourcity.gov
flutter build ios --dart-define=POCKETBASE_URL=https://notice.yourcity.gov
```

### Distribute

- **Android**: Upload APK to your website or Google Play
- **iOS**: Distribute via TestFlight or App Store

## 8. Monitoring

### Check Service Status

```bash
sudo systemctl status notice
sudo journalctl -u notice -f
```

### View Logs

```bash
tail -f /opt/notice/pb_data/logs.db
```

## Security Considerations

1. **Firewall**: Only expose ports 80, 443, and 22
2. **Rate Limiting**: PocketBase has built-in throttling
3. **Backups**: Regularly backup `/opt/notice/pb_data/`
4. **Updates**: Monitor PocketBase releases for security patches

## Scaling

For larger deployments:

- Use PostgreSQL instead of SQLite (PocketBase supports this)
- Add a CDN (Cloudflare) in front of your server
- Consider regional deployments for lower latency

---

## Quick Reference

| Service | URL |
|---------|-----|
| Admin Panel | `https://notice.yourcity.gov/_/` |
| API | `https://notice.yourcity.gov/api/` |
| Realtime | `wss://notice.yourcity.gov/api/realtime` |
