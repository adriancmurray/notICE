# notICE REST API Reference

Complete API documentation for the PocketBase backend.

---

## Base URL

```
Development: http://localhost:8090
Production: https://your-domain.com
```

---

## Collections

### Reports (`/api/collections/reports/records`)

Safety reports submitted by community members.

#### List Reports

```http
GET /api/collections/reports/records
```

**Query Parameters:**
| Param | Type | Description |
|-------|------|-------------|
| `filter` | string | PocketBase filter expression |
| `sort` | string | Sort field (prefix `-` for DESC) |
| `perPage` | int | Results per page (default: 30, max: 500) |
| `page` | int | Page number (default: 1) |

**Example — Fetch recent reports in area:**
```
/api/collections/reports/records?filter=(geohash~"9xj" || geohash~"9xk")&&created>="2026-01-17 00:00:00"&sort=-created&perPage=50
```

**Response:**
```json
{
  "items": [
    {
      "id": "abc123def456ghi",
      "geohash": "9xj5ns",
      "type": "danger",
      "description": "Ice on sidewalk",
      "lat": 43.4926,
      "long": -112.0401,
      "confirmations": 3,
      "disputes": 0,
      "created": "2026-01-18T10:30:00Z",
      "updated": "2026-01-18T10:30:00Z"
    }
  ],
  "page": 1,
  "perPage": 50,
  "totalItems": 12,
  "totalPages": 1
}
```

---

#### Create Report

```http
POST /api/collections/reports/records
```

**Headers:**
| Header | Required | Description |
|--------|----------|-------------|
| `X-Device-Fingerprint` | No | Device ID for rate limiting |

**Body:**
```json
{
  "geohash": "9xj5ns",
  "type": "danger",
  "description": "Ice on sidewalk",
  "lat": 43.4926,
  "long": -112.0401
}
```

**Rate Limiting:** 1 report per hour per device fingerprint.

---

#### Update Report (Voting)

```http
PATCH /api/collections/reports/records/:id
```

**Body (confirm):**
```json
{ "confirmations": 4 }
```

**Body (dispute):**
```json
{ "disputes": 1 }
```

---

### Push Subscriptions (`/api/collections/push_subscriptions/records`)

Web push notification subscriptions.

#### Subscribe

```http
POST /api/collections/push_subscriptions/records
```

**Body:**
```json
{
  "endpoint": "https://fcm.googleapis.com/fcm/send/...",
  "keys_p256dh": "BASE64_PUBLIC_KEY",
  "keys_auth": "BASE64_AUTH_SECRET",
  "geohash": "9xj5"
}
```

#### Unsubscribe

```http
DELETE /api/collections/push_subscriptions/records/:id
```

---

### Config (`/api/collections/config/records`)

Server configuration (read-only for non-admins).

#### Get Region Config

```http
GET /api/collections/config/records?filter=key="region"
```

**Response:**
```json
{
  "items": [{
    "id": "...",
    "key": "region",
    "value": {
      "name": "Idaho Falls, ID",
      "lat": 43.4926,
      "long": -112.0401,
      "zoom": 13
    }
  }]
}
```

---

## Custom Endpoints

### VAPID Public Key

```http
GET /api/vapid-public-key
```

Returns the server's VAPID public key for push subscriptions.

**Response:**
```json
{ "key": "BASE64_VAPID_PUBLIC_KEY" }
```

**Error (503):**
```json
{ "error": "VAPID keys not initialized" }
```

---

## Realtime (SSE)

Subscribe to live report updates:

```
GET /api/realtime
```

Use the PocketBase SDK for subscription management:

```dart
pb.collection('reports').subscribe('*', (e) {
  if (e.action == 'create') {
    // Handle new report
  }
});
```

---

## Error Codes

| Code | Description |
|------|-------------|
| 400 | Bad request (validation error, rate limit) |
| 403 | Forbidden (admin-only action) |
| 404 | Record not found |
| 503 | Service unavailable (VAPID not configured) |
