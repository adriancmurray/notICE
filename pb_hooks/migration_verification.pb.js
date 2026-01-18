/// <reference path="../pb_data/types.d.ts" />

/**
 * Migration hook to ensure reports collection has verification fields.
 * 
 * This runs on every record create and adds fields if missing.
 * Uses a one-time flag to avoid repeated checks.
 */

// One-time migration flag
let migrationDone = false;

onRecordCreate((e) => {
    // Only run migration once per server session
    if (migrationDone || e.collection.name !== "reports") {
        return;
    }

    try {
        const collection = $app.findCollectionByNameOrId("reports");

        // Check if confirmations field exists
        let hasConfirmations = false;
        let hasDisputes = false;

        for (const field of collection.fields) {
            if (field.name === "confirmations") hasConfirmations = true;
            if (field.name === "disputes") hasDisputes = true;
        }

        let needsSave = false;

        if (!hasConfirmations) {
            collection.fields.push({
                name: "confirmations",
                type: "number",
                required: false,
                min: 0,
            });
            needsSave = true;
            console.log("Added confirmations field to reports collection");
        }

        if (!hasDisputes) {
            collection.fields.push({
                name: "disputes",
                type: "number",
                required: false,
                min: 0,
            });
            needsSave = true;
            console.log("Added disputes field to reports collection");
        }

        if (needsSave) {
            $app.save(collection);
            console.log("Reports collection updated with verification fields");
        }

        migrationDone = true;
    } catch (err) {
        console.log("Could not update reports collection:", err);
        migrationDone = true; // Don't keep retrying
    }
});
