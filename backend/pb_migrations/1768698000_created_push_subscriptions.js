/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
    const collection = new Collection({
        "createRule": "",  // Anyone can subscribe (anonymous)
        "deleteRule": "",  // Anyone can unsubscribe
        "fields": [
            {
                "autogeneratePattern": "[a-z0-9]{15}",
                "hidden": false,
                "id": "text3208210256",
                "max": 15,
                "min": 15,
                "name": "id",
                "pattern": "^[a-z0-9]+$",
                "presentable": false,
                "primaryKey": true,
                "required": true,
                "system": true,
                "type": "text"
            },
            {
                "autogeneratePattern": "",
                "hidden": false,
                "id": "text_endpoint",
                "max": 0,
                "min": 0,
                "name": "endpoint",
                "pattern": "",
                "presentable": false,
                "primaryKey": false,
                "required": true,
                "system": false,
                "type": "text"
            },
            {
                "autogeneratePattern": "",
                "hidden": false,
                "id": "text_p256dh",
                "max": 0,
                "min": 0,
                "name": "keys_p256dh",
                "pattern": "",
                "presentable": false,
                "primaryKey": false,
                "required": true,
                "system": false,
                "type": "text"
            },
            {
                "autogeneratePattern": "",
                "hidden": false,
                "id": "text_auth",
                "max": 0,
                "min": 0,
                "name": "keys_auth",
                "pattern": "",
                "presentable": false,
                "primaryKey": false,
                "required": true,
                "system": false,
                "type": "text"
            },
            {
                "autogeneratePattern": "",
                "hidden": false,
                "id": "text_geohash",
                "max": 12,
                "min": 4,
                "name": "geohash",
                "pattern": "^[0-9bcdefghjkmnpqrstuvwxyz]+$",
                "presentable": false,
                "primaryKey": false,
                "required": true,
                "system": false,
                "type": "text"
            },
            {
                "hidden": false,
                "id": "autodate_created",
                "name": "created",
                "onCreate": true,
                "onUpdate": false,
                "presentable": false,
                "system": false,
                "type": "autodate"
            },
            {
                "hidden": false,
                "id": "autodate_updated",
                "name": "updated",
                "onCreate": true,
                "onUpdate": true,
                "presentable": false,
                "system": false,
                "type": "autodate"
            }
        ],
        "id": "pbc_push_subs",
        "indexes": [
            "CREATE UNIQUE INDEX idx_push_subs_endpoint ON push_subscriptions (endpoint)",
            "CREATE INDEX idx_push_subs_geohash ON push_subscriptions (geohash)"
        ],
        "listRule": null,
        "name": "push_subscriptions",
        "system": false,
        "type": "base",
        "updateRule": "",  // Anyone can update their subscription
        "viewRule": null
    });

    return app.save(collection);
}, (app) => {
    const collection = app.findCollectionByNameOrId("pbc_push_subs");

    return app.delete(collection);
})
