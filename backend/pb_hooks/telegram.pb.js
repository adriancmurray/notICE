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
 */

const TELEGRAM_API = "https://api.telegram.org/bot";

// Report type to emoji mapping
const TYPE_EMOJI = {
    danger: "🚨",
    warning: "⚠️",
    safe: "✅"
};

// Report type to human-readable label
const TYPE_LABEL = {
    danger: "DANGER",
    warning: "Warning",
    safe: "All Clear"
};

/**
 * Send a message to Telegram.
 * @param {string} token - Bot token
 * @param {string} chatId - Target chat ID
 * @param {string} message - Message text (supports Markdown)
 */
function sendTelegramMessage(token, chatId, message) {
    const url = `${TELEGRAM_API}${token}/sendMessage`;

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
        timeout: 10 // seconds
    });

    if (response.statusCode !== 200) {
        console.log("Telegram API error:", response.raw);
        throw new Error(`Telegram API returned ${response.statusCode}`);
    }

    return response.json;
}

/**
 * Format a report for Telegram notification.
 * @param {Object} record - PocketBase record
 * @returns {string} Formatted message
 */
function formatReportMessage(record) {
    const emoji = TYPE_EMOJI[record.get("type")] || "📍";
    const label = TYPE_LABEL[record.get("type")] || record.get("type");
    const description = record.get("description") || "No description provided";
    const geohash = record.get("geohash");
    const lat = record.get("lat");
    const long = record.get("long");

    // OpenStreetMap link (no Google!)
    const mapLink = `https://www.openstreetmap.org/?mlat=${lat}&mlon=${long}#map=17/${lat}/${long}`;

    return `${emoji} *${label}*

📝 ${description}

📍 [View Location](${mapLink})
🗺️ Geohash: \`${geohash}\`
⏰ ${new Date().toISOString()}`;
}

// Hook: Listen for new reports
onRecordAfterCreateRequest((e) => {
    const token = $os.getenv("TELEGRAM_BOT_TOKEN");
    const chatId = $os.getenv("TELEGRAM_CHAT_ID");

    // Skip if not configured
    if (!token || !chatId) {
        console.log("Telegram not configured, skipping notification");
        return;
    }

    try {
        const message = formatReportMessage(e.record);
        sendTelegramMessage(token, chatId, message);
        console.log(`Telegram notification sent for report ${e.record.id}`);
    } catch (err) {
        // Log but don't block the request
        console.log("Failed to send Telegram notification:", err.message);
    }
}, "reports");
