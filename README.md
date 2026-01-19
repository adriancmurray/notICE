# notICE 🧊

**Privacy-first community safety alerts for immigrant communities.**

A decentralized, anonymous reporting system that enables communities to share real-time safety information without surveillance risk.

---

## Features

- **Anonymous Reporting** — No accounts, no tracking, no PII stored
- **Geo-targeted Alerts** — Push notifications only to nearby users
- **Privacy by Design** — SHA-256 hashed identifiers, 24h auto-purge
- **Forensic Resistance** — VACUUM scrubs deleted data from disk
- **PWA** — Works offline, installable on any device

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter PWA (Dart)                       │
│  • MapScreen with report markers                             │
│  • Real-time geohash-based subscriptions                     │
│  • VAPID push notification support                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTP + SSE
┌─────────────────────────────────────────────────────────────┐
│              PocketBase + Go Extension                       │
│  • REST API for reports collection                           │
│  • Privacy-preserving rate limiting                          │
│  • VAPID Web Push (webpush-go)                               │
│  • 24h TTL with VACUUM                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                      ┌───────┴───────┐
                      │  SQLite DB    │
                      └───────────────┘
```

---

## Privacy Guarantees

| Data | Storage | Retention |
|------|---------|-----------|
| Reports | Geohash + description only | 24 hours |
| IP addresses | SHA-256 hash with daily rotating salt | 2 hours |
| Push subscriptions | FCM endpoint + geohash | 7 days |
| Logs | Disabled | N/A |

**Rate limiting** uses one-way hashing — the server can verify if an IP recently posted, but cannot recover the original IP from the hash.

---

## Quick Start (Operators)

Deploy notICE for your community in one command.

### Docker (Recommended)

```bash
docker run -d -p 8090:8090 -v notice-data:/app/pb_data ghcr.io/adriancmurray/notice

# Create admin account
docker exec -it <container_id> ./notICE superuser upsert admin@local.dev yourpassword
```

### Docker Compose (with Cloudflare Tunnel)

```bash
git clone https://github.com/adriancmurray/notICE.git
cd notICE
docker compose up -d

# For instant HTTPS:
docker compose --profile public up -d
```

### Linux VPS (One-Liner)

```bash
curl -sSL https://raw.githubusercontent.com/adriancmurray/notICE/main/scripts/install.sh | bash
```

### Manual Download

Download binaries from [GitHub Releases](https://github.com/adriancmurray/notICE/releases):
- `notICE-darwin-arm64` (Apple Silicon)
- `notICE-linux-amd64` (x86 VPS)
- `notICE-linux-arm64` (Raspberry Pi)
- `notICE-windows-amd64.exe`

---

## Disclaimer

> **notICE is provided "as-is" without warranty of any kind.**
> 
> The authors and contributors bear no responsibility for how the software is deployed, operated, or used. Each community operator assumes full liability for their instance.
>
> This software is licensed under the MIT License.

---

## Development

### Prerequisites

- Go 1.24+
- Flutter 3.35+
- macOS/Linux

### Build from Source

```bash
git clone https://github.com/adriancmurray/notICE.git
cd notICE

# Build backend
go build -o notICE .

# Build frontend
cd app && flutter build web --release && cd ..
cp -r app/build/web/* pb_public/

# Run
./notICE serve --http=0.0.0.0:8090
```

Open `http://localhost:8090`

---

## Project Structure

```
notICE/
├── main.go                 # Go backend with VAPID push
├── go.mod                  # Go dependencies
├── pocketbase_vapid        # Compiled binary
├── deploy_local.sh         # Build + deploy script
├── pb_data/                # SQLite database + VAPID keys
├── pb_public/              # Served Flutter PWA
├── pb_hooks/               # JS hooks (not used with custom binary)
├── app/                    # Flutter frontend
│   ├── lib/
│   │   ├── main.dart
│   │   ├── config/         # App configuration
│   │   ├── controllers/    # MapController (state management)
│   │   ├── models/         # Report, TimeFilter
│   │   ├── screens/        # MapScreen
│   │   ├── services/       # PocketBase, Location, Push, Geohash
│   │   ├── theme/          # AppTheme design tokens
│   │   └── widgets/        # Extracted UI components
│   └── test/               # Unit tests
└── docs/
    ├── ARCHITECTURE.md     # System design
    ├── API.md              # REST endpoints
    └── SCHEMA.md           # Database schema
```

---

## API Reference

### Reports

```http
# List reports in area
GET /api/collections/reports/records?filter=(geohash~"9x8r")

# Create report (rate limited: 1/hour per IP)
POST /api/collections/reports/records
Content-Type: application/json
{
  "geohash": "9x8r6m",
  "type": "warning",
  "description": "Activity reported near 5th St",
  "lat": 43.49,
  "long": -112.04
}

# Vote on report
PATCH /api/collections/reports/records/:id
{
  "confirmations": 1
}
```

### Push Notifications

```http
# Get VAPID public key
GET /api/vapid-public-key

# Subscribe to alerts
POST /api/collections/push_subscriptions/records
{
  "endpoint": "https://fcm.googleapis.com/...",
  "keys_p256dh": "...",
  "keys_auth": "...",
  "geohash": "9x8r6c"
}
```

---

## Security Considerations

### Rate Limiting

```go
// One-way hash prevents IP recovery
hash := SHA256(dailySalt + ":" + clientIP)
// Stored hash: 1ef951a7701b27a9b40202607b84d8d7...
// Original IP: Unrecoverable
```

### Data Lifecycle

- **Reports**: Auto-deleted after 24 hours
- **Rate limit hashes**: Auto-deleted after 2 hours  
- **Push subscriptions**: Auto-deleted after 7 days of inactivity
- **Disk scrubbing**: `VACUUM` overwrites deleted data

### Cold Boot Mitigations

| Risk | Mitigation |
|------|------------|
| VAPID keys on disk | Store in env var for production |
| SQLite WAL | Truncated after each purge |
| Swap files | Use encrypted swap (cloud VPS: configure inside VM) |
| Disk persistence | **Paranoid mode**: Mount `pb_data/` as tmpfs (RAM-only) |

---

## Deployment

### Docker (Recommended)

```dockerfile
# Option 1: Minimal Alpine (pinned version)
FROM golang:1.21-alpine3.19 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o pocketbase_vapid .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /app/pocketbase_vapid .
COPY pb_public/ ./pb_public/
EXPOSE 8090
CMD ["./pocketbase_vapid", "serve", "--http=0.0.0.0:8090"]
```

```dockerfile
# Option 2: Distroless (maximum hardening — no shell)
FROM golang:1.21-alpine3.19 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o pocketbase_vapid .

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/pocketbase_vapid /pocketbase_vapid
COPY pb_public/ /pb_public/
EXPOSE 8090
ENTRYPOINT ["/pocketbase_vapid", "serve", "--http=0.0.0.0:8090"]
```

### Environment Variables

```bash
NOTICE_SUBSCRIPTION_KEY=<32-byte-hex>  # Optional: encrypt push subs at rest
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

---

## License

MIT License — See [LICENSE](LICENSE) for details.

---

## Acknowledgments

Built with:
- [PocketBase](https://pocketbase.io) — Backend framework
- [Flutter](https://flutter.dev) — Cross-platform UI
- [webpush-go](https://github.com/SherClockHolmes/webpush-go) — VAPID push notifications
