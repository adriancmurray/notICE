/// <reference path="../pb_data/types.d.ts" />

/**
 * Modular notification hook for notICE.
 * 
 * Supports multiple notification providers:
 * - Telegram (via Bot API)
 * - ntfy.sh (via HTTP POST)
 * 
 * Configure via environment variables:
 * 
 * TELEGRAM:
 *   TELEGRAM_BOT_TOKEN=your_bot_token
 *   TELEGRAM_CHAT_ID=-1001234567890
 * 
 * NTFY:
 *   NTFY_TOPIC=your_topic_name
 *   NTFY_SERVER=https://ntfy.sh (optional, defaults to ntfy.sh)
 * 
 * Both can be enabled simultaneously for redundancy.
 */

// Format report for notification
function formatReport(record) {
    const TYPE_EMOJI = { danger: "🚨", warning: "⚠️", safe: "✅" };
    const TYPE_LABEL = { danger: "DANGER", warning: "Warning", safe: "All Clear" };

    const type = record.get("type") || "report";
    const emoji = TYPE_EMOJI[type] || "📍";
    const label = TYPE_LABEL[type] || type;
    const description = record.get("description") || "";
    const lat = record.get("lat");
    const long = record.get("long");

    const mapUrl = `https://www.openstreetmap.org/?mlat=${lat}&mlon=${long}#map=17/${lat}/${long}`;

    return { emoji, label, description, lat, long, mapUrl, type };
}

// Telegram notification adapter
function sendTelegram(record, report) {
    const token = $os.getenv("TELEGRAM_BOT_TOKEN");
    const chatId = $os.getenv("TELEGRAM_CHAT_ID");

    if (!token || !chatId) return false;

    try {
        const message = `${report.emoji} *${report.label}*\n${report.description}\n\n[📍 View Map](${report.mapUrl})`;

        $http.send({
            url: `https://api.telegram.org/bot${token}/sendMessage`,
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                chat_id: chatId,
                text: message,
                parse_mode: "Markdown"
            }),
            timeout: 10
        });
        console.log("Telegram notification sent:", record.id);
        return true;
    } catch (err) {
        console.log("Telegram error:", err.message);
        return false;
    }
}

// ntfy.sh notification adapter
function sendNtfy(record, report) {
    const topic = $os.getenv("NTFY_TOPIC");
    if (!topic) return false;

    const server = $os.getenv("NTFY_SERVER") || "https://ntfy.sh";

    try {
        // ntfy supports rich notifications with priority, tags, and actions
        const priority = report.type === "danger" ? "urgent" :
            report.type === "warning" ? "high" : "default";

        const tags = report.type === "danger" ? "rotating_light,warning" :
            report.type === "warning" ? "warning" : "white_check_mark";

        $http.send({
            url: `${server}/${topic}`,
            method: "POST",
            headers: {
                "Title": `${report.emoji} ${report.label}`,
                "Priority": priority,
                "Tags": tags,
                "Click": report.mapUrl,
                "Actions": `view, View Map, ${report.mapUrl}`
            },
            body: report.description || "New report submitted",
            timeout: 10
        });
        console.log("ntfy notification sent:", record.id);
        return true;
    } catch (err) {
        console.log("ntfy error:", err.message);
        return false;
    }
}

// Main hook - fires on new report creation
onRecordCreateRequest((e) => {
    // Let the record be created first
    e.next();

    // Only process reports
    if (e.collection.name !== "reports") return;

    const report = formatReport(e.record);

    // Try all configured notification providers
    const results = {
        telegram: sendTelegram(e.record, report),
        ntfy: sendNtfy(e.record, report)
    };

    // Log which providers were used
    const used = Object.entries(results)
        .filter(([_, success]) => success)
        .map(([name]) => name);

    if (used.length > 0) {
        console.log("Notifications sent via:", used.join(", "));
    } else {
        console.log("No notification providers configured");
    }
});
