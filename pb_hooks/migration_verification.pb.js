/// <reference path="../pb_data/types.d.ts" />

/**
 * Migration hook to add confirmations/disputes fields to reports collection.
 * 
 * This runs on bootstrap and adds the fields if they don't exist.
 */

onAfterBootstrap((e) => {
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
                max: null,
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
                max: null,
            });
            needsSave = true;
            console.log("Added disputes field to reports collection");
        }

        if (needsSave) {
            $app.save(collection);
            console.log("Reports collection updated with verification fields");
        }
    } catch (err) {
        console.log("Could not update reports collection:", err);
    }
});
