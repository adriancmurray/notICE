/// <reference path="../pb_data/types.d.ts" />

/**
 * Initialization hook for notICE server.
 * 
 * Automatically creates the config collection and region settings
 * from environment variables on first boot.
 */

onAfterBootstrap((e) => {
    const regionName = $os.getenv("REGION_NAME") || "My City";
    const regionLat = parseFloat($os.getenv("REGION_LAT")) || 39.7392;
    const regionLong = parseFloat($os.getenv("REGION_LONG")) || -104.9903;
    const regionZoom = parseInt($os.getenv("REGION_ZOOM")) || 14;

    // Check if config collection exists
    try {
        const configCollection = $app.findCollectionByNameOrId("config");

        // Check if region config exists
        const existing = $app.findFirstRecordByData("config", "key", "region");

        if (!existing) {
            // Create region config
            const record = new Record(configCollection);
            record.set("key", "region");
            record.set("value", {
                name: regionName,
                lat: regionLat,
                long: regionLong,
                zoom: regionZoom
            });
            $app.save(record);
            console.log("Created region config:", regionName);
        }
    } catch (err) {
        // Config collection doesn't exist yet - will be created via schema import
        console.log("Config collection not found, will be created on schema import");
    }
});
