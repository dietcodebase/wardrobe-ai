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

        return migrator
    }()
}
