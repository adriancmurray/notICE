/// <reference path="../pb_data/types.d.ts" />

/**
 * Server-side rate limiting hook.
 * 
 * Enforces 1 report per hour per device/IP.
 * Runs BEFORE record creation and can reject the request.
 * 
 * NOTE: This is defense-in-depth. Client also rate limits.
 */

onRecordCreateRequest((e) => {
    // Only process reports collection
    if (e.collection.name !== "reports") {
        e.next();
        return;
    }

    // Get identifier: fingerprint header or IP
    let identifier = null;
    try {
        identifier = e.httpContext.request.header.get("X-Device-Fingerprint");
    } catch (err) {
        // Header access failed, try IP
    }

    if (!identifier) {
        try {
            identifier = e.httpContext.remoteIP();
        } catch (err) {
            // IP access failed too
        }
    }

    // If we can't identify the device, allow but log
    if (!identifier) {
        console.log("Rate limit: No identifier available, allowing request");
        e.next();
        return;
    }

    // Check for recent reports
    const oneHourAgo = new Date(Date.now() - 3600000).toISOString();

    try {
        // Try with fingerprint field first, fall back to IP
        let found = false;

        try {
            const records = $app.findRecordsByFilter(
                "reports",
                `device_fingerprint = "${identifier}" && created >= "${oneHourAgo}"`,
                "-created", 1, 0
            );
            if (records && records.length > 0) found = true;
        } catch (err) {
            // Field doesn't exist, try client_ip
            try {
                const records = $app.findRecordsByFilter(
                    "reports",
                    `client_ip = "${identifier}" && created >= "${oneHourAgo}"`,
                    "-created", 1, 0
                );
                if (records && records.length > 0) found = true;
            } catch (err2) {
                // Neither field exists, skip rate limiting
                console.log("Rate limit: No tracking fields in schema, skipping");
            }
        }

        if (found) {
            throw new BadRequestError("Please wait 1 hour between reports");
        }
    } catch (err) {
        if (err.message && err.message.includes("Please wait")) {
            throw err;
        }
        console.log("Rate limit check error:", err.message);
    }

    // Try to store identifier for future checks (optional - don't block if fails)
    try {
        e.record.set("device_fingerprint", identifier);
    } catch (err) {
        // Field doesn't exist in schema - that's fine
    }

    e.next();
});
