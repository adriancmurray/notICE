package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/SherClockHolmes/webpush-go"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// ============================================================================
// CRYPTOGRAPHICALLY SECURE SALT MANAGER
// ============================================================================
// Thread-safe, in-memory only salt that rotates daily.
// Never written to disk - adversary cannot brute-force hashes.

var (
	saltMutex     sync.RWMutex
	currentSalt   []byte
	lastSaltEpoch int64
)

// getDailySalt returns a cryptographically random salt that rotates daily.
// Uses double-checked locking for thread safety and efficiency.
func getDailySalt() []byte {
	now := time.Now().UTC().Unix()
	dayEpoch := now / (24 * 60 * 60)

	// Fast path: read lock, check if salt is current
	saltMutex.RLock()
	if currentSalt != nil && lastSaltEpoch == dayEpoch {
		defer saltMutex.RUnlock()
		return currentSalt
	}
	saltMutex.RUnlock()

	// Slow path: need to rotate salt
	saltMutex.Lock()
	defer saltMutex.Unlock()

	// Double-check after acquiring write lock
	if currentSalt != nil && lastSaltEpoch == dayEpoch {
		return currentSalt
	}

	// Generate new 32-byte cryptographically random salt
	newSalt := make([]byte, 32)
	if _, err := rand.Read(newSalt); err != nil {
		log.Printf("[SECURITY] Failed to generate random salt: %v - using fallback", err)
		// Fallback to less-secure but still random-ish salt
		newSalt = []byte(fmt.Sprintf("fallback-%d-%d", now, time.Now().UnixNano()))
	}

	currentSalt = newSalt
	lastSaltEpoch = dayEpoch
	log.Printf("[SECURITY] Rotated rate-limit salt (day epoch: %d)", dayEpoch)

	return currentSalt
}

// VAPIDKeys stores the generated key pair
type VAPIDKeys struct {
	PrivateKey string `json:"private_key"`
	PublicKey  string `json:"public_key"`
}

func main() {
	app := pocketbase.New()

	// Initialize VAPID keys and register API route on serve
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		// Ensure collections exist
		if err := ensureReportsCollection(app); err != nil {
			log.Printf("Failed to ensure reports collection: %v", err)
		}
		if err := ensureRateLimitHashesCollection(app); err != nil {
			log.Printf("Failed to ensure rate_limit_hashes collection: %v", err)
		}
		if err := ensurePushCollection(app); err != nil {
			log.Printf("Failed to ensure push collection: %v", err)
		}

		keys := initVAPIDKeys(app.DataDir())

		// API: Get public VAPID key for frontend
		se.Router.GET("/api/vapid-public-key", func(e *core.RequestEvent) error {
			if keys == nil || keys.PublicKey == "" {
				return e.JSON(http.StatusServiceUnavailable, map[string]string{
					"error": "VAPID keys not initialized",
				})
			}
			return e.JSON(http.StatusOK, map[string]string{
				"key": keys.PublicKey,
			})
		})

		// API: Admin "Torch" - Delete all reports (superuser only)
		se.Router.DELETE("/api/admin/torch", func(e *core.RequestEvent) error {
			// Require superuser authentication
			info, _ := e.RequestInfo()
			if info == nil || info.Auth == nil || !info.Auth.IsSuperuser() {
				return apis.NewUnauthorizedError("Superuser access required", nil)
			}

			// Delete all records from reports collection
			records, err := app.FindAllRecords("reports")
			if err != nil {
				return apis.NewBadRequestError("Failed to find reports: "+err.Error(), nil)
			}

			deleted := 0
			for _, record := range records {
				if err := app.Delete(record); err != nil {
					log.Printf("[TORCH] Failed to delete record %s: %v", record.Id, err)
				} else {
					deleted++
				}
			}

			log.Printf("[ADMIN] Torch executed by superuser: deleted %d reports", deleted)
			return e.JSON(http.StatusOK, map[string]any{
				"success": true,
				"deleted": deleted,
			})
		})

		// Serve static files from pb_public directory
		se.Router.GET("/{path...}", apis.Static(os.DirFS("./pb_public"), true))

		return se.Next()
	})

	// Hook: Privacy-preserving rate limiting on report creation
	app.OnRecordCreateRequest("reports").BindFunc(func(e *core.RecordRequestEvent) error {
		// Get client IP (strip port if present)
		ip := e.Request.RemoteAddr
		if host, _, err := net.SplitHostPort(ip); err == nil {
			ip = host
		}
		if xForwardedFor := e.Request.Header.Get("X-Forwarded-For"); xForwardedFor != "" {
			// X-Forwarded-For may contain multiple IPs; use the first one
			if idx := strings.Index(xForwardedFor, ","); idx > 0 {
				ip = strings.TrimSpace(xForwardedFor[:idx])
			} else {
				ip = strings.TrimSpace(xForwardedFor)
			}
		}

		// One-way hash: SHA-256(IP + daily rotating salt)
		hashedIP := hashIdentifier(ip)

		// Check for recent hash
		cutoff := time.Now().Add(-1 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z")
		existing, _ := app.FindFirstRecordByFilter(
			"rate_limit_hashes",
			"hash = {:hash} && created >= {:cutoff}",
			map[string]any{"hash": hashedIP, "cutoff": cutoff},
		)

		if existing != nil {
			return apis.NewBadRequestError("Please wait 1 hour between reports", nil)
		}

		// Store hash (NOT the original IP)
		hashCollection, err := app.FindCollectionByNameOrId("rate_limit_hashes")
		if err == nil {
			hashRecord := core.NewRecord(hashCollection)
			hashRecord.Set("hash", hashedIP)
			if err := app.Save(hashRecord); err != nil {
				log.Printf("Failed to save rate limit hash: %v", err)
			}
		}

		return e.Next()
	})

	// Hook: Send push notifications on new report creation
	app.OnRecordAfterCreateSuccess("reports").BindFunc(func(e *core.RecordEvent) error {
		// Non-blocking: send notifications in background
		go sendPushToNearbySubscribers(app, e.Record)
		return e.Next()
	})

	// Schedule: TTL purge every hour
	app.Cron().Add("ttl_purge", "0 * * * *", func() {
		purgeOldData(app)
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}

// ensureReportsCollection checks if reports collection exists, if not creates it
func ensureReportsCollection(app *pocketbase.PocketBase) error {
	collection, err := app.FindCollectionByNameOrId("reports")
	if err == nil && collection != nil {
		return nil // Already exists
	}

	log.Println("Creating reports collection...")

	collection = core.NewBaseCollection("reports")
	collection.Type = core.CollectionTypeBase

	// Public API rules ("" = anyone can access)
	public := ""
	collection.ListRule = &public
	collection.ViewRule = &public
	collection.CreateRule = &public
	collection.UpdateRule = &public
	// DeleteRule stays nil = admin only

	// Fields - NO PII stored (device_fingerprint removed)
	collection.Fields.Add(
		&core.TextField{Name: "geohash", Required: true, Min: 6, Max: 12},
		&core.SelectField{Name: "type", Required: true, Values: []string{"danger", "warning", "safe"}, MaxSelect: 1},
		&core.TextField{Name: "description", Required: false, Max: 500},
		&core.NumberField{Name: "lat", Required: true, Min: float64Ptr(-90), Max: float64Ptr(90)},
		&core.NumberField{Name: "long", Required: true, Min: float64Ptr(-180), Max: float64Ptr(180)},
		&core.NumberField{Name: "confirmations", Required: false, OnlyInt: true, Min: float64Ptr(0)},
		&core.NumberField{Name: "disputes", Required: false, OnlyInt: true, Min: float64Ptr(0)},
		&core.AutodateField{Name: "created", OnCreate: true},
		&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
	)

	return app.Save(collection)
}

// ensureRateLimitHashesCollection creates the privacy-preserving rate limit table
func ensureRateLimitHashesCollection(app *pocketbase.PocketBase) error {
	collection, err := app.FindCollectionByNameOrId("rate_limit_hashes")
	if err == nil && collection != nil {
		return nil // Already exists
	}

	log.Println("Creating rate_limit_hashes collection...")

	collection = core.NewBaseCollection("rate_limit_hashes")
	collection.Type = core.CollectionTypeBase

	// No public access - only hooks can read/write
	// nil rules = admin only (hooks run as admin)

	collection.Fields.Add(
		&core.TextField{Name: "hash", Required: true, Max: 64}, // SHA-256 hex
		&core.AutodateField{Name: "created", OnCreate: true},
	)

	return app.Save(collection)
}

func float64Ptr(v float64) *float64 {
	return &v
}

// ensurePushCollection checks if push_subscriptions exists, if not creates it
func ensurePushCollection(app *pocketbase.PocketBase) error {
	collection, err := app.FindCollectionByNameOrId("push_subscriptions")
	if err == nil && collection != nil {
		return nil // Already exists
	}

	log.Println("Creating push_subscriptions collection...")

	collection = core.NewBaseCollection("push_subscriptions")
	collection.Type = core.CollectionTypeBase
	collection.CreateRule = nil // public (anyone can subscribe)
	collection.UpdateRule = nil // public (anyone can update their sub)
	collection.DeleteRule = nil // public
	// List/View restricted by default (nil rules mean strict checks usually, but let's check docs.
	// Actually nil = admin only. We need empty string "" for public.
	// In Go types, pointer Strings are used. nil means default/locked?
	// Wait, for Rules: nil = admin only, "" = public?
	// Let's check PocketBase core struct. usually it's *string.
	// Actually, let's use explicit empty string pointers for public.

	public := ""
	collection.CreateRule = &public
	collection.UpdateRule = &public
	collection.DeleteRule = &public

	// Fields
	collection.Fields.Add(
		&core.TextField{Name: "endpoint", Required: true},
		&core.TextField{Name: "keys_p256dh", Required: true},
		&core.TextField{Name: "keys_auth", Required: true},
		&core.TextField{Name: "geohash", Required: true},
	)

	return app.Save(collection)
}

// initVAPIDKeys generates and stores VAPID keys if not already present
func initVAPIDKeys(dataDir string) *VAPIDKeys {
	keysPath := filepath.Join(dataDir, "vapid_keys.json")

	// Try to load existing keys
	if data, err := os.ReadFile(keysPath); err == nil {
		var keys VAPIDKeys
		if err := json.Unmarshal(data, &keys); err == nil && keys.PrivateKey != "" {
			log.Println("VAPID keys loaded from file")
			return &keys
		}
	}

	// Generate new VAPID key pair
	privateKey, publicKey, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		log.Printf("Failed to generate VAPID keys: %v", err)
		return nil
	}

	keys := &VAPIDKeys{
		PrivateKey: privateKey,
		PublicKey:  publicKey,
	}

	// Ensure data directory exists
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Printf("Failed to create data directory: %v", err)
		return keys // Return keys anyway, just won't persist
	}

	// Save to file
	data, _ := json.MarshalIndent(keys, "", "  ")
	if err := os.WriteFile(keysPath, data, 0600); err != nil {
		log.Printf("Failed to save VAPID keys: %v", err)
	} else {
		log.Println("VAPID keys generated and saved to", keysPath)
		log.Printf("Public Key: %s", publicKey)
	}

	return keys
}

// loadVAPIDKeys loads keys from the data directory
func loadVAPIDKeys(dataDir string) *VAPIDKeys {
	keysPath := filepath.Join(dataDir, "vapid_keys.json")
	data, err := os.ReadFile(keysPath)
	if err != nil {
		return nil
	}
	var keys VAPIDKeys
	if err := json.Unmarshal(data, &keys); err != nil {
		return nil
	}
	return &keys
}

// sendPushToNearbySubscribers sends push notifications to subscribers near the report
func sendPushToNearbySubscribers(app *pocketbase.PocketBase, record *core.Record) {
	// Get report details
	reportType := record.GetString("type")
	description := record.GetString("description")
	lat := record.GetFloat("lat")
	long := record.GetFloat("long")
	geohash := record.GetString("geohash")

	if geohash == "" || len(geohash) < 4 {
		log.Println("Push: Report missing valid geohash, skipping")
		return
	}

	// Get VAPID keys
	keys := loadVAPIDKeys(app.DataDir())
	if keys == nil || keys.PrivateKey == "" || keys.PublicKey == "" {
		log.Println("Push: VAPID keys not configured")
		return
	}

	// Build notification payload
	typeEmoji := map[string]string{"danger": "🚨", "warning": "⚠️", "safe": "✅"}
	typeLabel := map[string]string{"danger": "DANGER", "warning": "Warning", "safe": "All Clear"}

	emoji := typeEmoji[reportType]
	if emoji == "" {
		emoji = "📍"
	}
	label := typeLabel[reportType]
	if label == "" {
		label = "Report"
	}

	payload := map[string]interface{}{
		"title": emoji + " " + label,
		"body":  description,
		"id":    record.Id,
		"url":   fmt.Sprintf("/?lat=%f&long=%f", lat, long),
	}
	payloadBytes, _ := json.Marshal(payload)

	// Query nearby subscribers (4-char geohash prefix = ~20km radius)
	geohashPrefix := geohash[:4]
	subscriptions, err := app.FindRecordsByFilter(
		"push_subscriptions",
		"geohash ~ {:prefix}",
		"",
		100, // max 100 notifications per report
		0,
		map[string]any{"prefix": geohashPrefix + "%"},
	)

	if err != nil {
		log.Printf("Push: Failed to query subscriptions: %v", err)
		return
	}

	log.Printf("Push: Found %d subscribers near %s", len(subscriptions), geohashPrefix)

	// Send to each subscriber
	successCount := 0
	for _, sub := range subscriptions {
		endpoint := sub.GetString("endpoint")
		p256dh := sub.GetString("keys_p256dh")
		auth := sub.GetString("keys_auth")

		if endpoint == "" || p256dh == "" || auth == "" {
			continue
		}

		subscription := &webpush.Subscription{
			Endpoint: endpoint,
			Keys: webpush.Keys{
				P256dh: p256dh,
				Auth:   auth,
			},
		}

		resp, err := webpush.SendNotification(payloadBytes, subscription, &webpush.Options{
			Subscriber:      "mailto:admin@notice.local",
			VAPIDPublicKey:  keys.PublicKey,
			VAPIDPrivateKey: keys.PrivateKey,
			TTL:             3600, // 1 hour
		})

		if err != nil {
			log.Printf("Push: Failed to send to %s...: %v", truncateEndpoint(endpoint), err)
			// Check for expired/invalid subscriptions
			if resp != nil && (resp.StatusCode == 404 || resp.StatusCode == 410) {
				// Subscription is invalid, delete it
				if err := app.Delete(sub); err != nil {
					log.Printf("Push: Failed to delete invalid subscription: %v", err)
				}
			}
			continue
		}
		resp.Body.Close()
		successCount++
	}

	log.Printf("Push: Sent %d/%d notifications for report %s", successCount, len(subscriptions), record.Id)
}

func truncateEndpoint(endpoint string) string {
	if len(endpoint) > 40 {
		return endpoint[:40]
	}
	return endpoint
}

// hashIdentifier creates a one-way hash of an identifier (IP/fingerprint)
// using SHA-256 with a cryptographically random daily salt for privacy preservation.
// The salt is generated via crypto/rand and stored only in memory - never on disk.
func hashIdentifier(identifier string) string {
	// Get current day's cryptographically random salt
	salt := getDailySalt()

	// SHA-256(salt + identifier) - one-way, irreversible
	// Even if adversary gets the hash, they cannot brute-force without the salt
	data := append(salt, []byte(":"+identifier)...)
	hash := sha256.Sum256(data)
	return hex.EncodeToString(hash[:])
}

// purgeOldData implements aggressive TTL for forensic resistance
// Deletes old reports and rate limit hashes, then VACUUMs the database
func purgeOldData(app *pocketbase.PocketBase) {
	// Purge reports older than 24 hours
	reportCutoff := time.Now().Add(-24 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z")
	oldReports, _ := app.FindRecordsByFilter("reports", "created < {:cutoff}", "", 1000, 0, map[string]any{"cutoff": reportCutoff})
	for _, record := range oldReports {
		app.Delete(record)
	}

	// Purge rate limit hashes older than 2 hours
	hashCutoff := time.Now().Add(-2 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z")
	oldHashes, _ := app.FindRecordsByFilter("rate_limit_hashes", "created < {:cutoff}", "", 1000, 0, map[string]any{"cutoff": hashCutoff})
	for _, record := range oldHashes {
		app.Delete(record)
	}

	// Purge stale push subscriptions (7 days)
	subCutoff := time.Now().Add(-7 * 24 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z")
	oldSubs, _ := app.FindRecordsByFilter("push_subscriptions", "updated < {:cutoff}", "", 1000, 0, map[string]any{"cutoff": subCutoff})
	for _, record := range oldSubs {
		app.Delete(record)
	}

	// VACUUM to overwrite deleted data on disk (forensic resistance)
	// NOTE: VACUUM is a blocking operation that may lock the DB briefly
	log.Println("[TTL] Starting VACUUM (may briefly lock database)...")
	if _, err := app.DB().NewQuery("VACUUM").Execute(); err != nil {
		log.Printf("[TTL] VACUUM failed: %v", err)
	}

	// Truncate WAL to prevent recovery from write-ahead log
	if _, err := app.DB().NewQuery("PRAGMA wal_checkpoint(TRUNCATE)").Execute(); err != nil {
		log.Printf("[TTL] WAL checkpoint failed: %v", err)
	}

	log.Printf("[TTL] Purged %d reports, %d hashes, %d subscriptions. Disk scrubbed.", len(oldReports), len(oldHashes), len(oldSubs))
}
