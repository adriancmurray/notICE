# notICE Database Schema

Canonical schema reference for the PocketBase backend.

---

## Collections

### `reports`

Safety reports submitted by community members.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | text (15) | ✓ | Auto-generated primary key |
| `geohash` | text (6-12) | ✓ | Spatial index, pattern: `^[0-9bcdefghjkmnpqrstuvwxyz]+$` |
| `type` | select | ✓ | Values: `danger`, `warning`, `safe` |
| `description` | text (0-500) | - | User-provided details |
| `lat` | number | ✓ | Latitude (-90 to 90) |
| `long` | number | ✓ | Longitude (-180 to 180) |
| `confirmations` | number | - | Community verification count (default: 0) |
| `disputes` | number | - | Dispute count (default: 0) |
| `device_fingerprint` | text | - | Hidden; for server-side rate limiting |
| `created` | autodate | ✓ | Auto on create |
| `updated` | autodate | ✓ | Auto on create/update |

**Indexes:**
- `idx_reports_geohash` — Spatial queries
- `idx_reports_type` — Filter by type
- `idx_reports_created` — Time-based queries (DESC)
- `idx_reports_fingerprint` — Rate limiting

**API Rules:**
- Create: Public (anonymous submissions)
- Read/List: Public
- Update: Public (for voting)
- Delete: Admin only

---

### `push_subscriptions`

Web push notification subscriptions for geo-targeted alerts.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | text (15) | ✓ | Auto-generated primary key |
| `endpoint` | text | ✓ | Push service URL (unique) |
| `keys_p256dh` | text | ✓ | VAPID public key |
| `keys_auth` | text | ✓ | VAPID auth secret |
| `geohash` | text (4-12) | ✓ | Subscription location |
| `created` | autodate | ✓ | Auto on create |
| `updated` | autodate | ✓ | Auto on create/update |

**Indexes:**
- `idx_push_subs_endpoint` — Unique constraint
- `idx_push_subs_geohash` — Geo-targeted queries

**API Rules:**
- Create: Public (anyone can subscribe)
- Update: Public (anyone can update their subscription)
- Delete: Public (anyone can unsubscribe)
- Read/List: Admin only

---

### `config`

Server configuration (region settings, links).

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | text (15) | ✓ | Auto-generated primary key |
| `key` | text | ✓ | Config key (e.g., `region`, `telegram`) |
| `value` | json | ✓ | Config value object |

**API Rules:**
- Read/List: Public
- Create/Update/Delete: Admin only

---

## Custom API Endpoints

### `GET /api/vapid-public-key`

Returns the VAPID public key for push notification subscriptions.

**Response:**
```json
{
  "key": "BASE64_PUBLIC_KEY"
}
```

**Error (503):**
```json
{
  "error": "VAPID keys not initialized"
}
```

---

## Geohash Strategy

Precision 6 geohashes (~1.2km × 0.6km cells) are used for:
- Report spatial indexing
- Subscription targeting
- Neighbor queries (8 adjacent cells)

Push notifications use 4-character prefix matching (~20km radius).
