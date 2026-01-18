package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/SherClockHolmes/webpush-go"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

// VAPIDKeys stores the generated key pair
type VAPIDKeys struct {
	PrivateKey string `json:"private_key"`
	PublicKey  string `json:"public_key"`
}

func main() {
	app := pocketbase.New()

	// Initialize VAPID keys and register API route on serve
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		// Ensure push_subscriptions collection exists
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

		// Serve static files from pb_public directory
		se.Router.GET("/{path...}", apis.Static(os.DirFS("./pb_public"), true))

		return se.Next()
	})

	// Hook: Send push notifications on new report creation
	app.OnRecordAfterCreateSuccess("reports").BindFunc(func(e *core.RecordEvent) error {
		// Non-blocking: send notifications in background
		go sendPushToNearbySubscribers(app, e.Record)
		return e.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
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
