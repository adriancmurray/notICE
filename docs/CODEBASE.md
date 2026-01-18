# notICE Codebase Handoff

A complete guide to the notICE codebase for future developers.

---

## Architecture Overview

notICE is a **localized safety alert system** with two main components:

```
┌────────────────────────────────────────────────────────────┐
│                    PocketBase Server                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │  SQLite DB   │  │  REST API    │  │  Realtime SSE    │ │
│  │  (pb_data/)  │  │  /api/...    │  │  Subscriptions   │ │
│  └──────────────┘  └──────────────┘  └──────────────────┘ │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  pb_hooks/ - Server-side JavaScript                  │ │
│  │  • telegram.pb.js — Push to Telegram on new report   │ │
│  │  • init.pb.js — Auto-config from env vars            │ │
│  │  • migration_verification.pb.js — Schema migrations  │ │
│  └──────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  pb_public/ - Static files served by PocketBase      │ │
│  │  • Flutter PWA (compiled from app/)                  │ │
│  │  • admin.html — Simplified admin interface           │ │
│  └──────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│                    Flutter PWA (app/)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │  MapScreen   │  │  Services    │  │  Models          │ │
│  │  (main UI)   │  │  (API calls) │  │  (data classes)  │ │
│  └──────────────┘  └──────────────┘  └──────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
notICE/
├── app/                          # Flutter PWA source
│   └── lib/
│       ├── main.dart             # Entry point, theme setup
│       ├── config/
│       │   └── app_config.dart   # PocketBase URL, defaults
│       ├── models/
│       │   └── report.dart       # Report data class
│       ├── screens/
│       │   └── map_screen.dart   # Main map UI (700+ lines)
│       ├── services/
│       │   ├── pocketbase_service.dart   # API client
│       │   ├── location_service.dart     # GPS tracking
│       │   ├── geohash_service.dart      # Spatial indexing
│       │   ├── rate_limit_service.dart   # 1 report/hour limit
│       │   └── vote_tracking_service.dart # 1 vote per device
│       └── widgets/
│           ├── report_form.dart   # Bottom sheet form
│           └── report_marker.dart # Map pin widget
│
├── backend/                      # PocketBase instance
│   ├── pb_data/                  # SQLite database (gitignored)
│   ├── pb_hooks/                 # Server-side JS hooks
│   └── pb_public/                # Served static files
│
├── pb_hooks/                     # Hook templates (copied to backend/)
│   ├── telegram.pb.js            # Telegram notifications
│   ├── init.pb.js                # Auto-config from env
│   └── migration_verification.pb.js
│
├── pb_public/                    # Static file templates
│   └── admin.html                # Simplified admin UI
│
├── docker-compose.yml            # Container deployment
├── setup.sh                      # Interactive setup wizard
└── .env.example                  # Config template
```

---

## Key Components

### 1. Flutter App (`app/lib/`)

#### `main.dart`
Entry point. Sets up MaterialApp with dark theme and launches MapScreen.

#### `config/app_config.dart`  
Auto-detects PocketBase URL:
- **Web**: Uses `window.location.origin` (same-origin)
- **Native**: Falls back to localhost:8090

#### `models/report.dart`
```dart
class Report {
  final String id;
  final String geohash;
  final ReportType type;      // danger, warning, safe
  final String? description;
  final double lat, long;
  final int confirmations;    // Community verification
  final int disputes;
  final DateTime created;
  
  bool get isDisputed => disputes >= 2;  // Auto-hide threshold
}
```

#### `screens/map_screen.dart` (Main Screen)
The largest file. Handles:
- **Map rendering** with flutter_map + OpenStreetMap tiles
- **Location tracking** via LocationService
- **Realtime subscriptions** via PocketbaseService
- **Time filtering** (1h, 6h, 24h, 3d, 7d, All)
- **Report submission** via bottom sheet form
- **Vote UI** (confirm/dispute buttons in detail sheet)

Key methods:
- `_initializeAsync()` — Boot sequence
- `_subscribeToGeohashes()` — Realtime updates
- `_refreshReports()` — Manual refresh
- `_showReportDetails()` — Opens vote sheet

#### `services/pocketbase_service.dart`
Singleton API client:
- `fetchReports()` — GET with geohash + time filter
- `submitReport()` — POST new report
- `confirmReport()` / `disputeReport()` — Vote methods
- `subscribeToGeohashes()` — Realtime SSE subscription

#### `services/geohash_service.dart`
Spatial indexing using precision-6 geohashes (~1km² cells):
- `encode(lat, long)` — Convert coords to geohash
- `getNeighbors()` — 8 adjacent cells
- `buildGeohashFilter()` — PocketBase filter string

#### `services/rate_limit_service.dart`
Client-side rate limiting (1 report/hour):
- Uses SharedPreferences to store last submit timestamp
- `canSubmitReport()` — Check if allowed
- `getRemainingCooldown()` — Time until next allowed

#### `services/vote_tracking_service.dart`
Prevents vote gaming (1 vote per device per report):
- `hasVoted(reportId)` — Already voted?
- `recordConfirmation()` / `recordDispute()` — Store vote

---

### 2. PocketBase Hooks (`pb_hooks/`)

#### `telegram.pb.js` (Active)
Fires on `onRecordCreateRequest` for "reports" collection:
1. Calls `e.next()` first to save the record
2. Gets TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID from env
3. Formats message with emoji, description, map link
4. POSTs to Telegram Bot API (non-blocking)

**Required env vars:**
- `TELEGRAM_BOT_TOKEN` — From @BotFather
- `TELEGRAM_CHAT_ID` — Channel/group ID (negative number for groups)

#### Other hooks (Templates only)
- `init.pb.js` — Auto-config from env vars (optional)
- `migration_verification.pb.js` — Removed (was causing issues)

---

### 3. Admin Interface (`pb_public/admin.html`)

Single-page admin panel:
- **Auth**: PocketBase superuser login
- **Region config**: Name, coordinates, zoom
- **Telegram config**: Channel link for app's "Join" button
- **Report management**: List recent reports, delete spam

Uses vanilla JS + Leaflet for map preview.

---

## Data Flow

### Submitting a Report
```
User taps "Report" → ReportForm opens
  → User selects type + description
  → RateLimitService.canSubmitReport() check
  → PocketbaseService.submitReport()
    → POST /api/collections/reports/records
      → PocketBase saves to SQLite
      → telegram.pb.js hook fires → Telegram notification
  → RateLimitService.recordReportSubmission()
  → MapScreen refreshes
```

### Viewing Reports
```
MapScreen loads → _initializeAsync()
  → LocationService.getCurrentLocation()
  → GeohashService.encode() + getNeighbors()
  → PocketbaseService.fetchReports(geohashes, sinceHours)
    → GET /api/collections/reports/records?filter=...
  → PocketbaseService.subscribeToGeohashes()
    → SSE connection for realtime updates
  → Reports rendered as markers (filtered by isDisputed)
```

### Voting on a Report
```
User taps marker → _showReportDetails() → _ReportDetailSheet
  → VoteTrackingService.hasVoted() check
  → User taps Confirm/Dispute
  → PocketbaseService.confirmReport() or disputeReport()
    → PATCH /api/collections/reports/records/:id
  → VoteTrackingService.recordConfirmation/Dispute()
  → MapScreen._refreshReports()
```

---

## Anti-Abuse Systems

| Layer | Mechanism | Enforcement |
|-------|-----------|-------------|
| **Rate Limit** | 1 report/hour | Client-side (SharedPreferences) |
| **Vote Tracking** | 1 vote/device/report | Client-side (SharedPreferences) |
| **Auto-Hide** | 2+ disputes → hidden | Client-side filter in map rendering |
| **Admin Delete** | Remove fake reports | Server-side via admin.html |

*Note: Client-side enforcement prevents casual abuse. Determined attackers could bypass, but the Telegram notification and admin moderation provide a safety net.*

---

## Deployment

### Docker (Recommended)
```bash
./setup.sh                      # Interactive config
docker compose up -d            # Start server
docker compose --profile public up -d  # With Cloudflare tunnel
```

### Railway (One-Click)
1. Click "Deploy on Railway" button
2. Set REGION_* env vars in dashboard
3. Access via Railway-provided URL

### Manual
1. Download PocketBase binary
2. Copy pb_hooks/ and pb_public/ to same directory
3. Run `./pocketbase serve`

---

## Extending notICE

### Adding a New Report Type
1. Edit `app/lib/models/report.dart` → add to `ReportType` enum
2. Add emoji, color, displayName getters
3. Rebuild PWA

### Adding a New Notification Channel
1. Create new hook in `pb_hooks/` (e.g., `discord.pb.js`)
2. Use `onRecordCreateRequest` pattern from telegram.pb.js
3. Add env vars to .env.example and setup.sh

### Adding Server-Side Rate Limiting
Create a hook that:
1. Tracks IP or device fingerprint
2. Stores last submit time in a new "rate_limits" collection
3. Rejects requests within cooldown period

---

## Known Limitations

- **No user accounts** — Anonymous by design
- **Client-side rate limiting** — Bypassable by technical users
- **No photo attachments** — Deferred feature
- **iOS location permission** — Requires manual grant on first use

---

*Last updated: January 2026*
