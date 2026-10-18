import Foundation
import GRDB

enum WardrobeDatabase {
    static func makeQueue(at url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try migrator.migrate(queue)
        return queue
    }

    static func makeInMemoryQueue() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: ":memory:", configuration: configuration)
        try migrator.migrate(queue)
        return queue
    }

    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_items_and_preferences") { database in
            try database.create(table: "items") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("category", .text).notNull()
                table.column("color", .text)
                table.column("tags_json", .text).notNull().defaults(to: "[]")
                table.column("notes", .text)
                table.column("image_path", .text)
                table.column("seed_key", .text).unique()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try database.create(index: "items_category", on: "items", columns: ["category"])

            try database.create(table: "preferences") { table in
                table.column("key", .text).primaryKey()
                table.column("categories_json", .text).notNull().defaults(to: "[]")
                table.column("colors_json", .text).notNull().defaults(to: "[]")
                table.column("notes", .text).notNull().defaults(to: "")
                table.column("updated_at", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_outfits_and_wear_logs") { database in
            try database.create(table: "outfits") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("notes", .text)
                table.column("is_favorite", .boolean).notNull().defaults(to: false)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try database.create(table: "outfit_items") { table in
                table.column("outfit_id", .text).notNull().references("outfits", onDelete: .cascade)
                table.column("item_id", .text).notNull().references("items", onDelete: .restrict)
                table.column("position", .integer).notNull()
                table.primaryKey(["outfit_id", "item_id"])
                table.uniqueKey(["outfit_id", "position"])
            }
            try database.create(index: "outfit_items_item", on: "outfit_items", columns: ["item_id"])

            try database.create(table: "wear_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("item_id", .text).notNull().references("items", onDelete: .restrict)
                table.column("outfit_id", .text).references("outfits", onDelete: .setNull)
                table.column("worn_at", .datetime).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try database.create(index: "wear_logs_item", on: "wear_logs", columns: ["item_id"])
            try database.create(index: "wear_logs_worn_at", on: "wear_logs", columns: ["worn_at"])
        }

        migrator.registerMigration("v3_wear_events") { database in
            try database.create(table: "wear_events") { table in
                table.column("id", .text).primaryKey()
                table.column("outfit_id", .text).references("outfits", onDelete: .setNull)
                table.column("local_day", .text).notNull()
                table.column("worn_at", .datetime).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try database.create(index: "wear_events_outfit_day", on: "wear_events", columns: ["outfit_id", "local_day"], unique: true)
            try database.alter(table: "wear_logs") { table in
                table.add(column: "event_id", .text).references("wear_events", onDelete: .cascade)
            }
            try database.create(index: "wear_logs_event", on: "wear_logs", columns: ["event_id"])
        }

        migrator.registerMigration("v4_classification_provenance") { database in
            try database.alter(table: "items") { table in
                table.add(column: "classification_json", .text)
            }
        }

        migrator.registerMigration("v5_item_embeddings") { database in
            try database.create(table: "item_embeddings") { table in
                table.column("item_id", .text).primaryKey().references("items", onDelete: .cascade)
                table.column("model_id", .text).notNull()
                table.column("model_revision", .text).notNull()
                table.column("dimension", .integer).notNull()
                table.column("normalized", .boolean).notNull()
                table.column("preprocessing_version", .text).notNull()
                table.column("content_hash", .text).notNull()
                table.column("vector", .blob).notNull()
                table.column("indexed_at", .datetime).notNull()
            }
            try database.create(index: "item_embeddings_compatibility", on: "item_embeddings", columns: ["model_id", "model_revision", "dimension", "preprocessing_version"])
        }

        migrator.registerMigration("v6_outfit_plans") { database in
            try database.create(table: "outfit_plans") { table in
                table.column("id", .text).primaryKey()
                table.column("outfit_id", .text).notNull().references("outfits", onDelete: .cascade)
                table.column("scheduled_for", .datetime).notNull()
                table.column("occasion", .text)
                table.column("source_event_id", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try database.create(index: "outfit_plans_date", on: "outfit_plans", columns: ["scheduled_for"])
            try database.create(index: "outfit_plans_event", on: "outfit_plans", columns: ["source_event_id"])
        }

        migrator.registerMigration("v7_recommendation_events") { database in
            try database.create(table: "recommendation_events") { table in
                table.column("id", .text).primaryKey()
                table.column("recommendation_id", .text).notNull()
                table.column("candidate_ids_json", .text).notNull()
                table.column("context_snapshot", .text).notNull()
                table.column("source", .text).notNull()
                table.column("outcome", .text).notNull()
                table.column("occurred_at", .datetime).notNull()
            }
            try database.create(index: "recommendation_events_id", on: "recommendation_events", columns: ["recommendation_id"])
            try database.create(index: "recommendation_events_date", on: "recommendation_events", columns: ["occurred_at"])
        }

        migrator.registerMigration("v8_garment_availability") { database in
            try database.alter(table: "items") { table in
                table.add(column: "availability", .text).notNull().defaults(to: "active")
            }
        }

        migrator.registerMigration("v9_explicit_style_preferences") { database in
            try database.alter(table: "preferences") { table in
                table.add(column: "warmth_preference", .text).notNull().defaults(to: "any")
                table.add(column: "prefers_rain_tolerance", .boolean).notNull().defaults(to: false)
                table.add(column: "prefers_walking_comfort", .boolean).notNull().defaults(to: false)
                table.add(column: "preferred_formality", .text)
                table.add(column: "footwear_preference", .text)
                table.add(column: "repeat_frequency", .text).notNull().defaults(to: "avoidRecent")
            }
        }

        migrator.registerMigration("v10_recommendation_compose_context") { database in
            try database.alter(table: "recommendation_events") { table in
                table.add(column: "locked_ids_json", .text).notNull().defaults(to: "[]")
                table.add(column: "requested_slots_json", .text).notNull().defaults(to: "[]")
                table.add(column: "outcome_reason", .text)
            }
        }

        migrator.registerMigration("v11_trips_and_packing") { database in
            try database.create(table: "trips") { table in
                table.column("id", .text).primaryKey()
                table.column("destination", .text).notNull()
                table.column("start_date", .datetime).notNull()
                table.column("end_date", .datetime).notNull()
                table.column("activities_json", .text).notNull().defaults(to: "[]")
                table.column("luggage_constraints", .text)
                table.column("weather_note", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try database.create(table: "trip_outfits") { table in
                table.column("trip_id", .text).notNull().references("trips", onDelete: .cascade)
                table.column("outfit_id", .text).notNull().references("outfits", onDelete: .cascade)
                table.primaryKey(["trip_id", "outfit_id"])
            }
            try database.create(table: "packing_items") { table in
                table.column("trip_id", .text).notNull().references("trips", onDelete: .cascade)
                table.column("item_id", .text).notNull().references("items", onDelete: .restrict)
                table.column("is_packed", .boolean).notNull().defaults(to: false)
                table.primaryKey(["trip_id", "item_id"])
            }
        }

        return migrator
    }()
}
