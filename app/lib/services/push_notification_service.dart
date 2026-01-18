import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:http/http.dart' as http;
import 'package:app/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// JS interop for JSON.stringify
@JS('JSON.stringify')
external String _jsStringify(JSAny? obj);

/// Check if a property exists on an object (mimics JS 'in' operator)
@JS()
external bool _hasProperty(String prop, JSAny obj);

/// Inline JS to define the hasProperty function
@JS('eval')
external JSAny _eval(String code);

void _initJsHelpers() {
  _eval('globalThis._hasProperty = (prop, obj) => prop in obj');
}

/// Service for managing VAPID push notification subscriptions.
///
/// This service:
/// 1. Requests notification permission from the user
/// 2. Subscribes to push notifications via the service worker
/// 3. Sends the subscription to the backend for geo-targeted alerts
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  static const _enabledKey = 'push_notifications_enabled';
  static const _geohashKey = 'push_notifications_geohash';

  String? _cachedVapidKey;
  bool _isSupported = false;

  /// Check if push notifications are supported in this browser.
  bool get isSupported => _isSupported;

  /// Initialize the service and check for browser support.
  Future<void> initialize() async {
    _isSupported = _checkSupport();
    if (_isSupported) {
      // Pre-fetch VAPID key
      _cachedVapidKey = await _fetchVapidPublicKey();
    }
  }

  bool _checkSupport() {
    // Only supported on web
    if (!kIsWeb) return false;
    
    try {
      // Initialize our JS helper function
      _initJsHelpers();
      
      // Use custom JS interop to check for required APIs
      final hasServiceWorker = _hasProperty('serviceWorker', web.window.navigator as JSAny);
      final hasPushManager = _hasProperty('PushManager', web.window as JSAny);
      final hasNotification = _hasProperty('Notification', web.window as JSAny);
      
      final result = hasServiceWorker && hasPushManager && hasNotification;
      
      // Log to browser console for debugging
      web.console.log('[PushNotificationService] Support check:'.toJS);
      web.console.log('  serviceWorker: $hasServiceWorker'.toJS);
      web.console.log('  PushManager: $hasPushManager'.toJS);
      web.console.log('  Notification: $hasNotification'.toJS);
      web.console.log('  Result: $result'.toJS);
      
      return result;
    } catch (e) {
      web.console.log('[PushNotificationService] Support check failed: $e'.toJS);
      return false;
    }
  }

  /// Check if notifications are currently enabled.
  Future<bool> isEnabled() async {
    if (!_isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Get the permission state.
  Future<String> getPermissionState() async {
    if (!_isSupported) return 'unsupported';
    try {
      return web.Notification.permission;
    } catch (e) {
      return 'unsupported';
    }
  }

  /// Request notification permission and subscribe to push.
  ///
  /// [geohash] is required for geo-targeted notifications.
  /// Returns true if subscription was successful.
  /// enableNotifications request notification permission and subscribe to push.
  ///
  /// [geohash] is required for geo-targeted notifications.
  /// Returns null if successful, or an error message string if failed.
  Future<String?> enableNotifications(String geohash) async {
    if (!_isSupported) return 'Push notifications not supported in this browser';

    try {
      // 1. Request permission
      final permission = await web.Notification.requestPermission().toDart;
      if (permission.toDart != 'granted') {
        return 'Notification permission denied ($permission)';
      }

      // 2. Get VAPID public key
      final vapidKey = _cachedVapidKey ?? await _fetchVapidPublicKey();
      if (vapidKey == null) {
        return 'Failed to fetch server VAPID key';
      }

      // 3. Get service worker registration
      final registration = await _getServiceWorkerRegistration();
      if (registration == null) {
        return 'Service Worker not found or not ready';
      }
      
      // Check if we got the right service worker
      final active = registration.active;
      if (active != null) {
        web.console.log('[notICE] Using Service Worker: ${active.scriptURL}'.toJS);
      }

      // 4. Subscribe to push
      final subscriptionJson = await _subscribeToPush(registration, vapidKey);
      if (subscriptionJson == null) {
        return 'Failed to subscribe to Push Manager';
      }

      // 5. Send subscription to backend
      final success = await _sendSubscriptionToBackend(subscriptionJson, geohash);
      if (!success) {
        return 'Failed to syncing subscription with server';
      }

      // 6. Save state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
      await prefs.setString(_geohashKey, geohash);

      return null;
    } catch (e) {
      web.console.error('[notICE] Enable notifications error: $e'.toJS);
      return 'Error: $e';
    }
  }

  /// Disable push notifications and remove subscription from backend.
  Future<bool> disableNotifications() async {
    if (!_isSupported) return false;

    try {
      final registration = await _getServiceWorkerRegistration();
      if (registration != null) {
        final pushManager = registration.pushManager;
        final subscriptionOrNull = await pushManager.getSubscription().toDart;
        if (subscriptionOrNull != null) {
          // Unsubscribe from browser
          await subscriptionOrNull.unsubscribe().toDart;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
      await prefs.remove(_geohashKey);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update the geohash for an existing subscription.
  Future<bool> updateGeohash(String newGeohash) async {
    if (!_isSupported) return false;

    try {
      final registration = await _getServiceWorkerRegistration();
      if (registration == null) return false;

      final pushManager = registration.pushManager;
      final subscriptionOrNull = await pushManager.getSubscription().toDart;
      if (subscriptionOrNull == null) return false;

      // Get subscription as JSON string
      final jsonObj = subscriptionOrNull.toJSON();
      final jsonStr = _jsObjectToJsonString(jsonObj);
      if (jsonStr == null) return false;

      // Re-send subscription with new geohash
      final success = await _sendSubscriptionToBackend(jsonStr, newGeohash);
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_geohashKey, newGeohash);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// TEST ONLY: Trigger a local notification to verify browser permissions
  Future<void> testLocalNotification() async {
    if (!_isSupported) return;
    try {
      final registration = await _getServiceWorkerRegistration();
      if (registration != null) {
        registration.showNotification(
          '🔔 Test Notification', 
          web.NotificationOptions(
            body: 'If you see this, your browser is configured correctly!',
            icon: 'icons/Icon-192.png',
          ),
        );
      }
    } catch (e) {
      web.console.error('Test notification failed: $e'.toJS);
    }
  }

  Future<String?> _fetchVapidPublicKey() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.pocketbaseUrl}/api/vapid-public-key'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['key'] as String?;
      }
    } catch (e) {
      // VAPID endpoint not available
    }
    return null;
  }

  Future<web.ServiceWorkerRegistration?> _getServiceWorkerRegistration() async {
    try {
      final sw = web.window.navigator.serviceWorker;

      // Wait for the push-sw.js registration
      final registrations = await sw.getRegistrations().toDart;
      for (final reg in registrations.toDart) {
        final active = reg.active;
        if (active != null && active.scriptURL.contains('push-sw.js')) {
          return reg;
        }
      }

      // If not found, wait for ready
      final ready = await sw.ready.toDart;
      return ready;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _subscribeToPush(
    web.ServiceWorkerRegistration registration,
    String vapidKey,
  ) async {
      final pushManager = registration.pushManager;

      // Convert VAPID key to Uint8Array
      final keyBytes = _urlBase64ToUint8Array(vapidKey);
      final jsArray = keyBytes.toJS;

      final options = web.PushSubscriptionOptionsInit(
        userVisibleOnly: true,
        applicationServerKey: jsArray,
      );

    try {
      final subscription = await pushManager.subscribe(options).toDart;
      
      // Convert to JSON string for backend
      final jsonObj = subscription.toJSON();
      return _jsObjectToJsonString(jsonObj);
    } catch (e) {
      // Handle VAPID key mismatch (browser has old subscription with different key)
      final errStr = e.toString();
      if (errStr.contains('InvalidStateError') || 
          errStr.contains('different applicationServerKey')) {
        web.console.warn('[notICE] VAPID key mismatch. Clearing old subscription...'.toJS);
        
        // Unsubscribe from old key
        final existing = await registration.pushManager.getSubscription().toDart;
        if (existing != null) {
          await existing.unsubscribe().toDart;
        }

        // Retry subscription with new key
        final newSub = await registration.pushManager.subscribe(options).toDart;
        final jsonObj = newSub.toJSON();
        return _jsObjectToJsonString(jsonObj);
      }

      web.console.error('[notICE] Push Subscription failed: $e'.toJS);
      throw e;
    }
  }

  String? _jsObjectToJsonString(web.PushSubscriptionJSON jsObj) {
    try {
      // Use JS JSON.stringify to properly serialize the object
      final jsonString = _jsStringify(jsObj);
      return jsonString;
    } catch (e) {
      return null;
    }
  }

  Future<bool> _sendSubscriptionToBackend(
    String subscriptionJson,
    String geohash,
  ) async {
    try {
      final parsed = json.decode(subscriptionJson) as Map<String, dynamic>;
      
      // Ensure keys exist
      final keys = parsed['keys'] as Map<String, dynamic>?;
      if (keys == null) {
        web.console.error('[notICE] Push subscription missing keys'.toJS);
        // We might want to fail here, but let's try sending what we have
        // or return failure to avoid backend 400
      }

      final body = json.encode({
        'endpoint': parsed['endpoint'],
        'keys_p256dh': keys?['p256dh'] ?? '',
        'keys_auth': keys?['auth'] ?? '',
        'geohash': geohash,
      });

      final response = await http.post(
        Uri.parse('${AppConfig.pocketbaseUrl}/api/collections/push_subscriptions/records'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      } else {
        final msg = 'Server rejected subscription: ${response.statusCode} - ${response.body}';
        web.console.error(msg.toJS);
        throw Exception(msg);
      }
    } catch (e) {
      web.console.error('Backend send error: $e'.toJS);
      throw e; // Propagate to enableNotifications
    }
  }

  /// Convert URL-safe base64 to Uint8List for VAPID key.
  Uint8List _urlBase64ToUint8Array(String base64String) {
    // Add padding if needed
    var padded = base64String;
    final mod = padded.length % 4;
    if (mod > 0) {
      padded += '=' * (4 - mod);
    }

    // Replace URL-safe characters
    final standard = padded.replaceAll('-', '+').replaceAll('_', '/');

    return base64.decode(standard);
  }
}
