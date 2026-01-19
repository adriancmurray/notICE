# notICE Architecture

High-level architecture and design patterns.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter PWA                               │
│  ┌────────────────┐  ┌────────────────┐  ┌───────────────────┐  │
│  │  MapScreen     │  │  MapController │  │  Services Layer   │  │
│  │  (UI only)     │◄─┤  (state/logic) │◄─┤  (API + device)   │  │
│  └────────────────┘  └────────────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ HTTP + SSE
┌─────────────────────────────────────────────────────────────────┐
│                   PocketBase + Go Extension                      │
│  ┌────────────────┐  ┌────────────────┐  ┌───────────────────┐  │
│  │  REST API      │  │  JS Hooks      │  │  VAPID Push       │  │
│  │  (collections) │  │  (notifications)│  │  (Go webpush)     │  │
│  └────────────────┘  └────────────────┘  └───────────────────┘  │
│                              │                                   │
│                      ┌───────┴───────┐                          │
│                      │  SQLite DB    │                          │
│                      │  (pb_data/)   │                          │
│                      └───────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Design Patterns

### 1. Controller Pattern (Flutter)

UI widgets are pure renderers. Business logic lives in `MapController`:

```dart
// Controller handles state and logic
class MapController extends ChangeNotifier {
  List<Report> reports = [];
  Future<void> refreshReports();
  void setTimeFilter(TimeFilter filter);
}

// UI consumes controller
class MapScreen extends StatelessWidget {
  final controller = MapController.instance;
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => /* render reports */,
    );
  }
}
```

### 2. Singleton Services

All services are singletons accessed via `ClassName.instance`:

```dart
PocketbaseService.instance.fetchReports();
LocationService.instance.getCurrentLocation();
PushNotificationService.instance.enableNotifications(geohash);
```

### 3. Geohash Spatial Indexing

Reports use precision-6 geohashes (~1.2km × 0.6km cells):

```
encode(lat, long) → "9xj5ns"
getNeighbors("9xj5ns") → {"9xj5nt", "9xj5nn", ...}
```

Push notifications use 4-char prefix (~20km radius).

### 4. Defense-in-Depth Rate Limiting

- **Client**: `RateLimitService` checks SharedPreferences
- **Server**: `rate_limit.pb.js` verifies fingerprint in DB

### 5. PWA Co-location

Flutter web build is served from PocketBase's `pb_public/`:
- Same-origin API calls (no CORS)
- Single deployment artifact
- Service worker for offline + push

---

## Directory Structure

```
notICE/
├── app/                          # Flutter PWA
│   └── lib/
│       ├── controllers/          # Business logic
│       │   └── map_controller.dart
│       ├── models/               # Data classes
│       │   └── report.dart
│       ├── screens/              # UI widgets
│       │   └── map_screen.dart
│       ├── services/             # API + device
│       │   ├── pocketbase_service.dart
│       │   ├── location_service.dart
│       │   ├── push_notification_service.dart
│       │   └── ...
│       ├── theme/                # Design tokens
│       │   └── app_theme.dart
│       └── widgets/              # Reusable components
│           ├── report_detail_sheet.dart
│           ├── report_form.dart
│           ├── report_marker.dart
│           └── time_filter_bar.dart
│
├── backend/                      # PocketBase instance
│   ├── pb_data/                  # SQLite (gitignored)
│   ├── pb_hooks/                 # Server-side JS
│   ├── pb_migrations/            # Schema migrations
│   └── pb_public/                # Served static files
│
├── pb_hooks/                     # Hook templates
│   ├── notifications.pb.js       # Telegram + ntfy
│   └── rate_limit.pb.js          # Server throttling
│
├── docs/                         # Documentation
│   ├── ARCHITECTURE.md           # This file
│   ├── API.md                    # REST reference
│   ├── SCHEMA.md                 # Database schema
│   ├── CODEBASE.md               # Developer guide
│   └── DEPLOYMENT.md             # Deployment options
│
└── main.go                       # Go extension (VAPID)
```

---

## Data Flow

### Report Submission

```
User → ReportForm → MapController.submitReport()
  → PocketbaseService.submitReport()
    → POST /api/collections/reports/records
      → rate_limit.pb.js (validate)
      → PocketBase saves to SQLite
      → notifications.pb.js (Telegram + ntfy)
      → main.go:sendPushToNearbySubscribers (VAPID)
```

### Realtime Updates

```
PocketBase → SSE event
  → pocketbase_service.reportsStream
    → MapController._onNewReport()
      → notifyListeners()
        → MapScreen rebuilds
```
