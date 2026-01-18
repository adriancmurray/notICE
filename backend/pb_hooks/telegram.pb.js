/// <reference path="../pb_data/types.d.ts" />

/**
 * Telegram notification hook for notICE reports.
 * 
 * Sends an alert to a configured Telegram channel/group when 
 * a new report is created.
 * 
 * Environment variables (set in PocketBase settings or system env):
 * - TELEGRAM_BOT_TOKEN: Bot token from @BotFather
 * - TELEGRAM_CHAT_ID: Target channel/group ID
 * 
 * Updated for PocketBase 0.25+ hooks API.
 */

// Hook: Listen for new reports (PocketBase 0.25+ API)
onRecordCreateRequest((e) => {
    // Only trigger after record is created
    e.next();

    // Only process reports collection
    if (e.collection.name !== "reports") {
        return;
    }

    const token = $os.getenv("TELEGRAM_BOT_TOKEN");
    const chatId = $os.getenv("TELEGRAM_CHAT_ID");

    // Skip if not configured
    if (!token || !chatId) {
        console.log("Telegram not configured, skipping notification");
        return;
    }

    try {
        // Report type to emoji/label mapping
        const TYPE_EMOJI = {
            danger: "🚨",
            warning: "⚠️",
            safe: "✅"
        };
        const TYPE_LABEL = {
            danger: "DANGER",
            warning: "Warning",
            safe: "All Clear"
        };

        // Format message
        const reportType = e.record.get("type");
        const emoji = TYPE_EMOJI[reportType] || "📍";
        const label = TYPE_LABEL[reportType] || reportType;
        const description = e.record.get("description") || "No description provided";
        const geohash = e.record.get("geohash");
        const lat = e.record.get("lat");
        const long = e.record.get("long");

        const mapLink = "https://www.openstreetmap.org/?mlat=" + lat + "&mlon=" + long + "#map=17/" + lat + "/" + long;

        const message = emoji + " *" + label + "*\n\n📝 " + description + "\n\n📍 [View Location](" + mapLink + ")\n🗺️ Geohash: `" + geohash + "`\n⏰ " + new Date().toISOString();

        // Send to Telegram
        const url = "https://api.telegram.org/bot" + token + "/sendMessage";

        const response = $http.send({
            url: url,
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                chat_id: chatId,
                text: message,
                parse_mode: "Markdown",
                disable_web_page_preview: true
            }),
            timeout: 10
        });

        if (response.statusCode !== 200) {
            console.log("Telegram API error:", response.raw);
        } else {
            console.log("Telegram notification sent for report " + e.record.id);
        }
    } catch (err) {
        // Log but don't block the request
        console.log("Failed to send Telegram notification:", err.message);
    }
});
