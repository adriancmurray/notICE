/// <reference path="../pb_data/types.d.ts" />

/**
 * Schema migration hook - runs on app startup.
 * 
 * Ensures the reports collection has the verification fields.
 * Uses onAfterBootstrap so it runs ONCE at startup, not on every request.
 */

onAfterBootstrap((e) => {
    try {
        const collection = $app.findCollectionByNameOrId("reports");
        if (!collection) {
            console.log("Reports collection not found, skipping migration");
            return;
        }

        let needsSave = false;

        // Check for confirmations field
        let hasConfirmations = false;
        let hasDisputes = false;
        let hasDeviceFingerprint = false;
        let hasClientIP = false;

        for (const field of collection.fields) {
            if (field.name === "confirmations") hasConfirmations = true;
            if (field.name === "disputes") hasDisputes = true;
            if (field.name === "device_fingerprint") hasDeviceFingerprint = true;
            if (field.name === "client_ip") hasClientIP = true;
        }

        if (!hasConfirmations) {
            collection.fields.push({
                name: "confirmations",
                type: "number",
                required: false,
                min: 0,
            });
            console.log("Adding confirmations field to reports");
            needsSave = true;
        }

        if (!hasDisputes) {
            collection.fields.push({
                name: "disputes",
                type: "number",
                required: false,
                min: 0,
            });
            console.log("Adding disputes field to reports");
            needsSave = true;
        }

        if (!hasDeviceFingerprint) {
            collection.fields.push({
                name: "device_fingerprint",
                type: "text",
                required: false,
            });
            console.log("Adding device_fingerprint field to reports");
            needsSave = true;
        }

        if (!hasClientIP) {
            collection.fields.push({
                name: "client_ip",
                type: "text",
                required: false,
            });
            console.log("Adding client_ip field to reports");
            needsSave = true;
        }

        if (needsSave) {
            $app.save(collection);
            console.log("Reports collection schema updated");
        }
    } catch (err) {
        console.log("Schema migration error:", err.message);
    }
});
