/// <reference path="../pb_data/types.d.ts" />

// Minimal Telegram hook for PocketBase 0.25
// Uses onRecordCreateRequest with e.next() first

onRecordCreateRequest((e) => {
    // Let the record be created first
    e.next();

    // Only process reports
    if (e.collection.name !== "reports") return;

    const token = $os.getenv("TELEGRAM_BOT_TOKEN");
    const chatId = $os.getenv("TELEGRAM_CHAT_ID");

    if (!token || !chatId) {
        console.log("Telegram not configured");
        return;
    }

    try {
        const type = e.record.get("type") || "report";
        const desc = e.record.get("description") || "";
        const lat = e.record.get("lat");
        const long = e.record.get("long");

        const emoji = type === "danger" ? "🚨" : type === "warning" ? "⚠️" : "✅";
        const mapUrl = `https://www.openstreetmap.org/?mlat=${lat}&mlon=${long}#map=17/${lat}/${long}`;
        const msg = `${emoji} *${type.toUpperCase()}*\n${desc}\n\n[📍 View Map](${mapUrl})`;

        $http.send({
            url: `https://api.telegram.org/bot${token}/sendMessage`,
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                chat_id: chatId,
                text: msg,
                parse_mode: "Markdown"
            }),
            timeout: 10
        });
        console.log("Telegram sent for", e.record.id);
    } catch (err) {
        console.log("Telegram error:", err);
    }
});
