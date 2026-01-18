// VERSION: {{BUILD_ID}}
console.log('[Push SW] Service Worker Loaded v{{BUILD_ID}}');

self.addEventListener('push', function (event) {
    console.log('[Push SW] Push received:', event);

    let data = {
        title: '🚨 notICE Alert',
        body: 'New safety report in your area',
        id: null,
        url: '/'
    };

    // Try to parse the push payload
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
        requireInteraction: true
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
                // Try to focus existing window
                for (const client of clientList) {
                    if (client.url.includes(self.location.origin) && 'focus' in client) {
                        client.navigate(url);
                        return client.focus();
                    }
                }
                // Open new window
                if (clients.openWindow) {
                    return clients.openWindow(url);
                }
            })
    );
});

self.addEventListener('pushsubscriptionchange', function (event) {
    console.log('[Push SW] Subscription changed, re-subscribing...');
    // The subscription has expired or been revoked
    // The app should re-subscribe when next opened
});
