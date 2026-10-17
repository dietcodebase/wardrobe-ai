import Foundation
import GRDB

final class WardrobeRepository {
    private let database: DatabaseWriter
    private let now: () -> Date

    init(database: DatabaseWriter, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    func createItem(_ draft: GarmentDraft, seedKey: String? = nil) throws -> GarmentItem {
        let normalized = try validate(draft)
        let timestamp = now()
        let item = GarmentItem(
            id: UUID(), name: normalized.name, category: normalized.category, color: normalized.color,
            tags: normalized.tags, notes: normalized.notes, imagePath: normalized.imagePath,
            createdAt: timestamp, updatedAt: timestamp
        )
        try database.write { database in
            try database.execute(
                sql: """
                INSERT INTO items (id, name, category, color, tags_json, notes, image_path, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id.uuidString, item.name, item.category, item.color, try encode(item.tags),
                    item.notes, item.imagePath, seedKey, item.createdAt, item.updatedAt
                ]
            )
        }
        return item
    }

    func createSeedItem(_ draft: GarmentDraft, key: String) throws -> GarmentItem {
        let normalized = try validate(draft)
        return try database.write { database in
            if let row = try Row.fetchOne(database, sql: "SELECT * FROM items WHERE seed_key = ?", arguments: [key]) {
                return try garmentItem(from: row)
            }
            let timestamp = now()
            let item = GarmentItem(
                id: UUID(), name: normalized.name, category: normalized.category, color: normalized.color,
                tags: normalized.tags, notes: normalized.notes, imagePath: normalized.imagePath,
                createdAt: timestamp, updatedAt: timestamp
            )
            try database.execute(
                sql: """
                INSERT INTO items (id, name, category, color, tags_json, notes, image_path, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id.uuidString, item.name, item.category, item.color, try encode(item.tags),
                    item.notes, item.imagePath, key, item.createdAt, item.updatedAt
                ]
            )
            return item
        }
    }

    func item(id: UUID) throws -> GarmentItem? {
        try database.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM items WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try garmentItem(from: row)
        }
    }

    func item(seedKey: String) throws -> GarmentItem? {
        try database.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM items WHERE seed_key = ?", arguments: [seedKey]) else {
                return nil
            }
            return try garmentItem(from: row)
        }
    }

    func allItems() throws -> [GarmentItem] {
        try database.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM items ORDER BY created_at ASC").map(garmentItem(from:))
        }
    }

    func items(tag: String) throws -> [GarmentItem] {
        try database.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT items.* FROM items
                WHERE EXISTS (SELECT 1 FROM json_each(items.tags_json) WHERE json_each.value = ?)
                ORDER BY items.created_at ASC
                """,
                arguments: [tag]
            )
            return try rows.map(garmentItem(from:))
        }
    }

    func items(matching query: String, category: String? = nil, tag: String? = nil) throws -> [GarmentItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try database.read { database in
            var clauses: [String] = []
            var arguments: [DatabaseValueConvertible?] = []
            if !text.isEmpty {
                clauses.append("(name LIKE ? COLLATE NOCASE OR color LIKE ? COLLATE NOCASE OR notes LIKE ? COLLATE NOCASE OR EXISTS (SELECT 1 FROM json_each(items.tags_json) WHERE json_each.value LIKE ? COLLATE NOCASE))")
                let pattern = "%\(text)%"
                arguments += [pattern, pattern, pattern, pattern]
            }
            if let category, !category.isEmpty {
                clauses.append("category = ?")
                arguments.append(category)
            }
            if let tag, !tag.isEmpty {
                clauses.append("EXISTS (SELECT 1 FROM json_each(items.tags_json) WHERE json_each.value = ?)")
                arguments.append(tag)
            }
            let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let rows = try Row.fetchAll(database, sql: "SELECT items.* FROM items \(whereClause) ORDER BY updated_at DESC", arguments: StatementArguments(arguments))
            return try rows.map(garmentItem(from:))
        }
    }

    func updateItem(_ item: GarmentItem) throws -> GarmentItem {
        let draft = try validate(GarmentDraft(
            name: item.name, category: item.category, color: item.color, tags: item.tags,
            notes: item.notes, imagePath: item.imagePath
        ))
        var updated = item
        updated.name = draft.name
        updated.category = draft.category
        updated.color = draft.color
        updated.tags = draft.tags
        updated.notes = draft.notes
        updated.imagePath = draft.imagePath
        updated.updatedAt = now()
        try database.write { database in
            try database.execute(
                sql: """
                UPDATE items SET name = ?, category = ?, color = ?, tags_json = ?, notes = ?, image_path = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    updated.name, updated.category, updated.color, try encode(updated.tags), updated.notes,
                    updated.imagePath, updated.updatedAt, updated.id.uuidString
                ]
            )
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.itemNotFound(updated.id) }
        }
        return updated
    }

    func deleteItem(id: UUID) throws {
        try database.write { database in
            let hasReferences = try Bool.fetchOne(
                database,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM outfit_items WHERE item_id = ?
                    UNION ALL SELECT 1 FROM wear_logs WHERE item_id = ?
                )
                """,
                arguments: [id.uuidString, id.uuidString]
            ) ?? false
            if hasReferences { throw WardrobeRepositoryError.itemIsReferenced(id) }
            try database.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [id.uuidString])
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.itemNotFound(id) }
        }
    }

    func preferences() throws -> StylePreferences {
        try database.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM preferences WHERE key = 'style'") else {
                return .empty
            }
            return StylePreferences(
                preferredCategories: try decode(row["categories_json"]),
                preferredColors: try decode(row["colors_json"]),
                notes: row["notes"]
            )
        }
    }

    func savePreferences(_ preferences: StylePreferences) throws {
        try database.write { database in
            try database.execute(
                sql: """
                INSERT INTO preferences (key, categories_json, colors_json, notes, updated_at)
                VALUES ('style', ?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    categories_json = excluded.categories_json,
                    colors_json = excluded.colors_json,
                    notes = excluded.notes,
                    updated_at = excluded.updated_at
                """,
                arguments: [try encode(preferences.preferredCategories), try encode(preferences.preferredColors), preferences.notes, now()]
            )
        }
    }

    func createOutfit(_ draft: OutfitDraft) throws -> Outfit {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WardrobeRepositoryError.invalidName
        }
        if let duplicate = duplicateID(in: draft.itemIDs) { throw WardrobeRepositoryError.duplicateOutfitItem(duplicate) }
        let timestamp = now()
        let outfit = Outfit(
            id: UUID(), name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), notes: draft.notes,
            isFavorite: draft.isFavorite, createdAt: timestamp, updatedAt: timestamp, itemIDs: draft.itemIDs
        )
        try database.write { database in
            for itemID in outfit.itemIDs where try !itemExists(itemID, in: database) {
                throw WardrobeRepositoryError.itemNotFound(itemID)
            }
            try database.execute(
                sql: "INSERT INTO outfits (id, name, notes, is_favorite, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [outfit.id.uuidString, outfit.name, outfit.notes, outfit.isFavorite, outfit.createdAt, outfit.updatedAt]
            )
            for (position, itemID) in outfit.itemIDs.enumerated() {
                try database.execute(
                    sql: "INSERT INTO outfit_items (outfit_id, item_id, position) VALUES (?, ?, ?)",
                    arguments: [outfit.id.uuidString, itemID.uuidString, position]
                )
            }
        }
        return outfit
    }

    func outfit(id: UUID) throws -> Outfit? {
        try database.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM outfits WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return try makeOutfit(from: row, in: database)
        }
    }

    func deleteOutfit(id: UUID) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM outfits WHERE id = ?", arguments: [id.uuidString])
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.outfitNotFound(id) }
        }
    }

    func logWear(itemID: UUID, outfitID: UUID? = nil, wornAt: Date? = nil) throws -> WearLog {
        let log = WearLog(id: UUID(), itemID: itemID, outfitID: outfitID, wornAt: wornAt ?? now(), createdAt: now())
        try database.write { database in
            guard try itemExists(itemID, in: database) else { throw WardrobeRepositoryError.itemNotFound(itemID) }
            if let outfitID, try !outfitExists(outfitID, in: database) { throw WardrobeRepositoryError.outfitNotFound(outfitID) }
            try database.execute(
                sql: "INSERT INTO wear_logs (id, item_id, outfit_id, worn_at, created_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [log.id.uuidString, log.itemID.uuidString, log.outfitID?.uuidString, log.wornAt, log.createdAt]
            )
        }
        return log
    }

    func wearLogs(for itemID: UUID) throws -> [WearLog] {
        try database.read { database in
            try Row.fetchAll(
                database, sql: "SELECT * FROM wear_logs WHERE item_id = ? ORDER BY worn_at DESC", arguments: [itemID.uuidString]
            ).map(wearLog(from:))
        }
    }

    func deleteWearLog(id: UUID) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM wear_logs WHERE id = ?", arguments: [id.uuidString])
        }
    }

    private func validate(_ draft: GarmentDraft) throws -> GarmentDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WardrobeRepositoryError.invalidName }
        let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { throw WardrobeRepositoryError.invalidCategory }
        return GarmentDraft(
            name: name, category: category, color: draft.color?.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: Array(Set(draft.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted(),
            notes: draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines), imagePath: draft.imagePath
        )
    }
}

private func garmentItem(from row: Row) throws -> GarmentItem {
    GarmentItem(
        id: try uuid(row["id"]), name: row["name"], category: row["category"], color: row["color"],
        tags: try decode(row["tags_json"]), notes: row["notes"], imagePath: row["image_path"],
        createdAt: row["created_at"], updatedAt: row["updated_at"]
    )
}

private func makeOutfit(from row: Row, in database: Database) throws -> Outfit {
    let id = try uuid(row["id"])
    let itemIDs = try String.fetchAll(
        database, sql: "SELECT item_id FROM outfit_items WHERE outfit_id = ? ORDER BY position", arguments: [id.uuidString]
    ).map(UUID.init(uuidString:)).compactMap { $0 }
    return Outfit(
        id: id, name: row["name"], notes: row["notes"], isFavorite: row["is_favorite"],
        createdAt: row["created_at"], updatedAt: row["updated_at"], itemIDs: itemIDs
    )
}

private func wearLog(from row: Row) throws -> WearLog {
    WearLog(
        id: try uuid(row["id"]), itemID: try uuid(row["item_id"]), outfitID: try optionalUUID(row["outfit_id"]),
        wornAt: row["worn_at"], createdAt: row["created_at"]
    )
}

private func itemExists(_ id: UUID, in database: Database) throws -> Bool {
    try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM items WHERE id = ?)", arguments: [id.uuidString]) ?? false
}

private func outfitExists(_ id: UUID, in database: Database) throws -> Bool {
    try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM outfits WHERE id = ?)", arguments: [id.uuidString]) ?? false
}

private func duplicateID(in ids: [UUID]) -> UUID? {
    var seen = Set<UUID>()
    return ids.first { !seen.insert($0).inserted }
}

private func encode(_ values: [String]) throws -> String {
    String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
}

private func decode(_ value: String) throws -> [String] {
    try JSONDecoder().decode([String].self, from: Data(value.utf8))
}

private func uuid(_ value: String) throws -> UUID {
    guard let value = UUID(uuidString: value) else { throw WardrobeRepositoryError.corruptRecord }
    return value
}

private func optionalUUID(_ value: String?) throws -> UUID? {
    guard let value else { return nil }
    return try uuid(value)
}
