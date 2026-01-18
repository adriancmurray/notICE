/// <reference path="../pb_data/types.d.ts" />

/**
 * Migration hook to ensure reports collection has verification fields.
 * 
 * This runs on every record create and adds fields if missing.
 * Uses a one-time flag to avoid repeated checks.
 */

onRecordCreate((e) => {
    // Only process reports collection
    if (e.collection.name !== "reports") {
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

        // If both fields exist, nothing to do
        if (hasConfirmations && hasDisputes) {
            return;
        }

        if (!hasConfirmations) {
            collection.fields.push({
                name: "confirmations",
                type: "number",
                required: false,
                min: 0,
            });
            console.log("Added confirmations field to reports collection");
        }

        if (!hasDisputes) {
            collection.fields.push({
                name: "disputes",
                type: "number",
                required: false,
                min: 0,
            });
            console.log("Added disputes field to reports collection");
        }

        $app.save(collection);
        console.log("Reports collection updated with verification fields");
    } catch (err) {
        console.log("Could not update reports collection:", err);
    }
});
