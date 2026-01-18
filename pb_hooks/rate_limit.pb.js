/// <reference path="../pb_data/types.d.ts" />

/**
 * Server-side rate limiting hook.
 * 
 * Enforces 1 report per hour per device using a fingerprint token.
 * The client sends X-Device-Fingerprint header with each request.
 * 
 * This works alongside client-side rate limiting as defense in depth.
 */

onRecordCreateRequest((e) => {
    // Only process reports collection
    if (e.collection.name !== "reports") {
        return;
    }

    // Get device fingerprint from header
    const fingerprint = e.httpContext.request.header.get("X-Device-Fingerprint");

    if (!fingerprint) {
        // No fingerprint = suspicious, but allow for backwards compatibility
        console.log("Warning: Report submitted without device fingerprint");
        e.next();
        return;
    }

    // Check for recent reports from this device
    const oneHourAgo = new Date(Date.now() - 3600000).toISOString();

    try {
        const records = $app.findRecordsByFilter(
            "reports",
            `device_fingerprint = "${fingerprint}" && created >= "${oneHourAgo}"`,
            "-created",
            1,
            0
        );

        if (records && records.length > 0) {
            throw new BadRequestError("Please wait 1 hour between reports");
        }
    } catch (err) {
        // If it's our rate limit error, rethrow it
        if (err.message && err.message.includes("Please wait")) {
            throw err;
        }
        // Otherwise log and continue (e.g., field doesn't exist yet)
        console.log("Rate limit check error (may be first run):", err.message);
    }

    // Store fingerprint with report for future checks
    e.record.set("device_fingerprint", fingerprint);

    e.next();
});
