/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    "createRule": "",       // Public: anyone can submit reports (anonymous)
    "deleteRule": null,     // Admin only
    "updateRule": "",       // Public: for confirm/dispute voting
    "listRule": "",         // Public: anyone can view reports
    "viewRule": "",         // Public: anyone can view reports
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
        "id": "text1624927940",
        "max": 12,
        "min": 6,
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
        "id": "select2363381545",
        "maxSelect": 1,
        "name": "type",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "select",
        "values": [
          "danger",
          "warning",
          "safe"
        ]
      },
      {
        "autogeneratePattern": "",
        "hidden": false,
        "id": "text1843675174",
        "max": 500,
        "min": 0,
        "name": "description",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "hidden": false,
        "id": "number2499937429",
        "max": 90,
        "min": -90,
        "name": "lat",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "hidden": false,
        "id": "number999795048",
        "max": 180,
        "min": -180,
        "name": "long",
        "onlyInt": false,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "hidden": false,
        "id": "number_confirmations",
        "max": null,
        "min": 0,
        "name": "confirmations",
        "onlyInt": true,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "hidden": false,
        "id": "number_disputes",
        "max": null,
        "min": 0,
        "name": "disputes",
        "onlyInt": true,
        "presentable": false,
        "required": false,
        "system": false,
        "type": "number"
      },
      {
        "autogeneratePattern": "",
        "hidden": true,
        "id": "text_device_fingerprint",
        "max": 64,
        "min": 0,
        "name": "device_fingerprint",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "hidden": false,
        "id": "autodate2990389176",
        "name": "created",
        "onCreate": true,
        "onUpdate": false,
        "presentable": false,
        "system": false,
        "type": "autodate"
      },
      {
        "hidden": false,
        "id": "autodate3332085495",
        "name": "updated",
        "onCreate": true,
        "onUpdate": true,
        "presentable": false,
        "system": false,
        "type": "autodate"
      }
    ],
    "id": "pbc_1615648943",
    "indexes": [
      "CREATE INDEX idx_reports_geohash ON reports (geohash)",
      "CREATE INDEX idx_reports_type ON reports (type)",
      "CREATE INDEX idx_reports_created ON reports (created DESC)",
      "CREATE INDEX idx_reports_fingerprint ON reports (device_fingerprint)"
    ],
    "name": "reports",
    "system": false,
    "type": "base"
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_1615648943");

  return app.delete(collection);
})
