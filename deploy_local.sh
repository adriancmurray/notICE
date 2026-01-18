#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🚀 Starting notICE Deployment Pipeline...${NC}"

# generate usage timestamp
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")

# 1. Clean Target
echo -e "${YELLOW}🧹 Cleaning backend/pb_public...${NC}"
rm -rf backend/pb_public/*
mkdir -p backend/pb_public

# 2. Build Flutter Web
echo -e "${YELLOW}🔨 Building Flutter Web (Release)...${NC}"
cd app
flutter build web --release --no-tree-shake-icons
cd ..

# 3. Copy Artifacts
echo -e "${YELLOW}📦 Copying build artifacts...${NC}"
cp -r app/build/web/* backend/pb_public/

# 4. Inject Push Handler into Flutter's Service Worker
# CRITICAL: Flutter's flutter_service_worker.js is the ACTIVE SW.
# We must inject our push handler INTO it, not register a separate SW.
echo -e "${YELLOW}💉 Injecting Push Handler into Flutter Service Worker...${NC}"

# Create the push handler code block
PUSH_HANDLER="
// === notICE Push Notification Handler (Injected) ===
// VERSION: ${TIMESTAMP}
console.log('[Push SW] Service Worker Loaded v${TIMESTAMP}');

self.addEventListener('push', function (event) {
    console.log('[Push SW] Push received:', event);

    let data = {
        title: '🚨 notICE Alert',
        body: 'New safety report in your area',
        id: null,
        url: '/'
    };

    if (event.data) {
        try {
            const json = event.data.json();
            console.log('[Push SW] Payload:', json);
            data = Object.assign(data, json);
        } catch (e) {
            console.log('[Push SW] Failed to parse push data:', e);
            data.body = event.data.text() || data.body;
        }
    }

    const options = {
        body: data.body,
        icon: '/icons/Icon-192.png',
        tag: data.id || 'notice-alert-' + Date.now(),
        data: {
            url: data.url,
            id: data.id
        },
        requireInteraction: false
    };

    event.waitUntil(
        self.registration.showNotification(data.title, options)
            .then(() => console.log('[Push SW] Notification shown'))
            .catch(err => console.error('[Push SW] showNotification error:', err))
    );
});

self.addEventListener('notificationclick', function (event) {
    console.log('[Push SW] Notification clicked:', event.action);
    event.notification.close();

    if (event.action === 'dismiss') {
        return;
    }

    const url = event.notification.data?.url || '/';

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true })
            .then(function (clientList) {
                for (const client of clientList) {
                    if (client.url.includes(self.location.origin) && 'focus' in client) {
                        client.navigate(url);
                        return client.focus();
                    }
                }
                if (clients.openWindow) {
                    return clients.openWindow(url);
                }
            })
    );
});

self.addEventListener('pushsubscriptionchange', function (event) {
    console.log('[Push SW] Subscription changed, re-subscribing...');
});
// === End of notICE Push Handler ==="

# Append push handler to Flutter's service worker
echo "$PUSH_HANDLER" >> backend/pb_public/flutter_service_worker.js

# Remove the standalone push-sw.js (no longer needed)
rm -f backend/pb_public/push-sw.js

# 5. Sync to root pb_public (server serves from here)
echo -e "${YELLOW}🔄 Syncing to root pb_public...${NC}"
rm -rf pb_public/*
cp -r backend/pb_public/* pb_public/

# 6. Verify
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "Build ID: ${TIMESTAMP}"
echo -e "Push handler injected into flutter_service_worker.js"
grep "notICE Push" pb_public/flutter_service_worker.js | head -1
