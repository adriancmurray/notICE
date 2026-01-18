# notICE 🧊

![notICE](assets/banner.jpg)

**A localized, decentralized safety alert system.**

notICE allows a city or region to self-host a single server that citizens can connect to via a mobile app to report and view dangerous situations — **anonymously**.

## 🚀 One-Click Deploy

Deploy your own notICE server in 60 seconds:

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/notICE?referralCode=notICE)

---

## Features

- 📍 **Real-time map** — See reports as they happen
- 🔔 **Telegram alerts** — Push notifications to your community
- ✅ **Confirm/Dispute** — Community verification system
- 🛡️ **Anti-abuse** — Rate limiting, vote tracking, disputed report hiding
- 🔐 **Admin panel** — Manage reports and settings
- 🌐 **PWA** — Works in any browser, installable on phones
- 🔒 **Privacy-first** — Anonymous, no tracking

---

## Quick Start (3 Steps)

### 1. Get the code

```bash
git clone https://github.com/adriancmurray/notICE
cd notICE
```

### 2. Run the setup wizard

```bash
./setup.sh
```

This will ask for:
- Your city/region name
- Map coordinates (get from Google Maps)
- Telegram bot token (optional)

### 3. Create your admin account

Open `http://localhost:8090/_/` and create a superuser account.

**Done!** Your server is running at `http://localhost:8090`

---

## Post-Setup Configuration

### Admin Panel

Access the simplified admin at: `http://yourserver/admin.html`

- **Region settings** — Name, coordinates, zoom level
- **Telegram link** — Community channel for app's "Join" button
- **Manage reports** — View and delete fake/spam reports

> **Security:** The admin panel requires PocketBase superuser login.

### Telegram Notifications

1. Create a bot with [@BotFather](https://t.me/BotFather)
2. Create a channel/group and add your bot as admin
3. Get the chat ID (use [@userinfobot](https://t.me/userinfobot))
4. Set environment variables:
   ```
   TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
   TELEGRAM_CHAT_ID=-1001234567890
   ```

---

## Anti-Abuse Features

| Feature | Description |
|---------|-------------|
| **Rate limiting** | 1 report per hour per device |
| **Vote tracking** | 1 confirm/dispute per device per report |
| **Auto-hide** | Reports with 2+ disputes hidden from map |
| **Admin delete** | Remove fake reports from admin panel |

---

## Architecture

### Philosophy

- **Zero Big Tech**: No Firebase, No Google Maps API, No AWS
- **Simplicity**: The backend is a single deployable binary
- **Privacy**: No user tracking, anonymous authentication only
- **Local-First**: Cities own their data, not corporations

### Tech Stack

| Layer | Technology | Why |
|-------|------------|-----|
| **Backend** | [PocketBase](https://pocketbase.io/) | Single Go binary with SQLite, Auth, Realtime |
| **Frontend** | Flutter (PWA) | Cross-platform, installable web app |
| **Maps** | [flutter_map](https://pub.dev/packages/flutter_map) + OpenStreetMap | No Google dependency |
| **Notifications** | Telegram Bot API | Bypasses APNS/FCM complexity |

### Data Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Flutter PWA   │────▶│   PocketBase    │────▶│  Telegram Bot   │
│  (Reporter)     │     │  (Single Binary)│     │  (Alerts)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        ▲                       │
        │                       │ Realtime
        │                       ▼
┌─────────────────┐     ┌─────────────────┐
│   Flutter PWA   │◀────│   Geohash       │
│  (Subscribers)  │     │   Pub/Sub       │
└─────────────────┘     └─────────────────┘
```

---

## Deployment Options

### Option 1: Railway (Recommended)

Click the deploy button above. Set environment variables in Railway dashboard.

### Option 2: Docker

```bash
cp .env.example .env
nano .env  # Configure your settings

# Local only
docker compose up -d

# With public HTTPS (Cloudflare Tunnel)
docker compose --profile public up -d
```

### Option 3: Manual

```bash
# Download PocketBase for your platform
# https://pocketbase.io/docs/

# Copy files
cp -r pb_hooks backend/
cp -r pb_public backend/

# Run
./pocketbase serve --http=0.0.0.0:8090
```

---

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `REGION_NAME` | Your city name | `My City, State` |
| `REGION_LAT` | Map center latitude | `40.7128` |
| `REGION_LONG` | Map center longitude | `-74.0060` |
| `REGION_ZOOM` | Default zoom level | `14` |
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather | `123456:ABC-DEF...` |
| `TELEGRAM_CHAT_ID` | Channel/Group ID | `-1001234567890` |

---

## Project Structure

```
notICE/
├── app/                    # Flutter PWA source
├── backend/                # PocketBase instance
│   ├── pb_hooks/           # Server-side JavaScript hooks
│   └── pb_public/          # Static files (PWA + admin.html)
├── pb_hooks/               # Hooks template (copied to backend)
├── pb_public/              # Public files template
├── docker-compose.yml      # Docker deployment
├── setup.sh                # Interactive setup wizard
└── .env.example            # Configuration template
```

---

## Security Notes

- **Change default admin password** before going public
- **PocketBase API rules** control who can read/write data
- **Rate limiting** is client-side (blocks casual abuse)
- **Vote tracking** prevents spam voting

For production, consider:
- Running behind a reverse proxy (nginx/Caddy)
- Enabling HTTPS (Cloudflare Tunnel or Let's Encrypt)
- Regular backups of `pb_data/`

---

## Contributing

Contributions welcome! Please open an issue first to discuss changes.

## License

MIT License — See [LICENSE](LICENSE) for details.

---

*Built for communities, not corporations.*
