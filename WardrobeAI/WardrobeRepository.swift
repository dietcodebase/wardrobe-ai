import Foundation
import GRDB

final class WardrobeRepository {
    private let database: DatabaseWriter
    private let now: () -> Date
    private let calendar: Calendar

    init(database: DatabaseWriter, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        self.database = database
        self.now = now
        self.calendar = calendar
    }

    func createItem(_ draft: GarmentDraft, seedKey: String? = nil) throws -> GarmentItem {
        let normalized = try validate(draft)
        let timestamp = now()
        let item = GarmentItem(
            id: UUID(), name: normalized.name, category: normalized.category, color: normalized.color,
            tags: normalized.tags, notes: normalized.notes, imagePath: normalized.imagePath, classification: normalized.classification,
            availability: normalized.availability,
            createdAt: timestamp, updatedAt: timestamp
        )
        try database.write { database in
            try database.execute(
                sql: """
                INSERT INTO items (id, name, category, color, tags_json, notes, image_path, classification_json, availability, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id.uuidString, item.name, item.category, item.color, try encode(item.tags),
                    item.notes, item.imagePath, try encode(item.classification), item.availability.rawValue, seedKey, item.createdAt, item.updatedAt
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
                tags: normalized.tags, notes: normalized.notes, imagePath: normalized.imagePath, classification: normalized.classification,
                availability: normalized.availability,
                createdAt: timestamp, updatedAt: timestamp
            )
            try database.execute(
                sql: """
                INSERT INTO items (id, name, category, color, tags_json, notes, image_path, classification_json, availability, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id.uuidString, item.name, item.category, item.color, try encode(item.tags),
                    item.notes, item.imagePath, try encode(item.classification), item.availability.rawValue, key, item.createdAt, item.updatedAt
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
            notes: item.notes, imagePath: item.imagePath, classification: item.classification, availability: item.availability
        ))
        var updated = item
        updated.name = draft.name
        updated.category = draft.category
        updated.color = draft.color
        updated.tags = draft.tags
        updated.notes = draft.notes
        updated.imagePath = draft.imagePath
        updated.classification = draft.classification
        updated.availability = draft.availability
        updated.updatedAt = now()
        try database.write { database in
            try database.execute(
                sql: """
                UPDATE items SET name = ?, category = ?, color = ?, tags_json = ?, notes = ?, image_path = ?, classification_json = ?, availability = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    updated.name, updated.category, updated.color, try encode(updated.tags), updated.notes,
                    updated.imagePath, try encode(updated.classification), updated.availability.rawValue, updated.updatedAt, updated.id.uuidString
                ]
            )
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.itemNotFound(updated.id) }
            try database.execute(sql: "DELETE FROM item_embeddings WHERE item_id = ?", arguments: [updated.id.uuidString])
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
                notes: row["notes"],
                warmthPreference: WarmthPreference(rawValue: row["warmth_preference"]) ?? .any,
                prefersRainTolerance: row["prefers_rain_tolerance"],
                prefersWalkingComfort: row["prefers_walking_comfort"],
                preferredFormality: row["preferred_formality"],
                footwearPreference: row["footwear_preference"],
                repeatFrequency: RepeatFrequency(rawValue: row["repeat_frequency"]) ?? .avoidRecent
            )
        }
    }

    func savePreferences(_ preferences: StylePreferences) throws {
        try database.write { database in
            try database.execute(
                sql: """
                INSERT INTO preferences (key, categories_json, colors_json, notes, warmth_preference, prefers_rain_tolerance, prefers_walking_comfort, preferred_formality, footwear_preference, repeat_frequency, updated_at)
                VALUES ('style', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    categories_json = excluded.categories_json,
                    colors_json = excluded.colors_json,
                    notes = excluded.notes,
                    warmth_preference = excluded.warmth_preference,
                    prefers_rain_tolerance = excluded.prefers_rain_tolerance,
                    prefers_walking_comfort = excluded.prefers_walking_comfort,
                    preferred_formality = excluded.preferred_formality,
                    footwear_preference = excluded.footwear_preference,
                    repeat_frequency = excluded.repeat_frequency,
                    updated_at = excluded.updated_at
                """,
                arguments: [try encode(preferences.preferredCategories), try encode(preferences.preferredColors), preferences.notes, preferences.warmthPreference.rawValue, preferences.prefersRainTolerance, preferences.prefersWalkingComfort, preferences.preferredFormality, preferences.footwearPreference, preferences.repeatFrequency.rawValue, now()]
            )
        }
    }

    func recommendationSnapshot(recommendationID: UUID) throws -> String? {
        try database.read { database in
            try String.fetchOne(database, sql: "SELECT context_snapshot FROM recommendation_events WHERE recommendation_id = ? ORDER BY occurred_at ASC LIMIT 1", arguments: [recommendationID.uuidString])
        }
    }

    func createOutfit(_ draft: OutfitDraft) throws -> Outfit {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WardrobeRepositoryError.invalidName
        }
        if let duplicate = duplicateID(in: draft.itemIDs) { throw WardrobeRepositoryError.duplicateOutfitItem(duplicate) }
        guard !draft.itemIDs.isEmpty else { throw WardrobeRepositoryError.emptyOutfit }
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

    func allOutfits() throws -> [Outfit] {
        try database.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM outfits ORDER BY is_favorite DESC, updated_at DESC")
                .map { try makeOutfit(from: $0, in: database) }
        }
    }

    func updateOutfit(_ outfit: Outfit) throws -> Outfit {
        try database.write { database in
            guard try outfitExists(outfit.id, in: database) else { throw WardrobeRepositoryError.outfitNotFound(outfit.id) }
            guard !outfit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WardrobeRepositoryError.invalidName }
            guard !outfit.itemIDs.isEmpty else { throw WardrobeRepositoryError.emptyOutfit }
            if let duplicate = duplicateID(in: outfit.itemIDs) { throw WardrobeRepositoryError.duplicateOutfitItem(duplicate) }
            for itemID in outfit.itemIDs where try !itemExists(itemID, in: database) { throw WardrobeRepositoryError.itemNotFound(itemID) }
            let updatedAt = now()
            try database.execute(
                sql: "UPDATE outfits SET name = ?, notes = ?, is_favorite = ?, updated_at = ? WHERE id = ?",
                arguments: [outfit.name.trimmingCharacters(in: .whitespacesAndNewlines), outfit.notes, outfit.isFavorite, updatedAt, outfit.id.uuidString]
            )
            try database.execute(sql: "DELETE FROM outfit_items WHERE outfit_id = ?", arguments: [outfit.id.uuidString])
            for (position, itemID) in outfit.itemIDs.enumerated() {
                try database.execute(sql: "INSERT INTO outfit_items (outfit_id, item_id, position) VALUES (?, ?, ?)", arguments: [outfit.id.uuidString, itemID.uuidString, position])
            }
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM outfits WHERE id = ?", arguments: [outfit.id.uuidString]) else { throw WardrobeRepositoryError.outfitNotFound(outfit.id) }
            return try makeOutfit(from: row, in: database)
        }
    }

    func deleteOutfit(id: UUID) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM outfits WHERE id = ?", arguments: [id.uuidString])
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.outfitNotFound(id) }
        }
    }

    func createPlan(outfitID: UUID, scheduledFor: Date, occasion: String? = nil, sourceEventID: String? = nil) throws -> OutfitPlan {
        let timestamp = now()
        let plan = OutfitPlan(id: UUID(), outfitID: outfitID, scheduledFor: scheduledFor, occasion: occasion?.trimmingCharacters(in: .whitespacesAndNewlines), sourceEventID: sourceEventID, createdAt: timestamp, updatedAt: timestamp)
        try database.write { database in
            guard try outfitExists(outfitID, in: database) else { throw WardrobeRepositoryError.outfitNotFound(outfitID) }
            try database.execute(sql: "INSERT INTO outfit_plans (id, outfit_id, scheduled_for, occasion, source_event_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)", arguments: [plan.id.uuidString, plan.outfitID.uuidString, plan.scheduledFor, plan.occasion, plan.sourceEventID, plan.createdAt, plan.updatedAt])
        }
        return plan
    }

    func plans() throws -> [OutfitPlan] {
        try database.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM outfit_plans ORDER BY scheduled_for ASC").map(outfitPlan(from:))
        }
    }

    func deletePlan(id: UUID) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM outfit_plans WHERE id = ?", arguments: [id.uuidString])
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.planNotFound(id) }
        }
    }

    func logWear(itemID: UUID, outfitID: UUID? = nil, wornAt: Date? = nil) throws -> WearLog {
        let log = WearLog(id: UUID(), itemID: itemID, outfitID: outfitID, wornAt: wornAt ?? now(), createdAt: now())
        try database.write { database in
            guard try itemExists(itemID, in: database) else { throw WardrobeRepositoryError.itemNotFound(itemID) }
            if let outfitID {
                guard try outfitExists(outfitID, in: database) else { throw WardrobeRepositoryError.outfitNotFound(outfitID) }
                let belongsToOutfit = try Bool.fetchOne(
                    database,
                    sql: "SELECT EXISTS(SELECT 1 FROM outfit_items WHERE outfit_id = ? AND item_id = ?)",
                    arguments: [outfitID.uuidString, itemID.uuidString]
                ) ?? false
                guard belongsToOutfit else { throw WardrobeRepositoryError.itemNotInOutfit(itemID: itemID, outfitID: outfitID) }
            }
            try database.execute(
                sql: "INSERT INTO wear_logs (id, item_id, outfit_id, worn_at, created_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [log.id.uuidString, log.itemID.uuidString, log.outfitID?.uuidString, log.wornAt, log.createdAt]
            )
        }
        return log
    }

    func wearToday(outfitID: UUID, wornAt: Date? = nil) throws -> WearEvent {
        let timestamp = wornAt ?? now()
        let day = localDay(for: timestamp)
        return try database.write { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM outfits WHERE id = ?", arguments: [outfitID.uuidString]) else {
                throw WardrobeRepositoryError.outfitNotFound(outfitID)
            }
            let outfit = try makeOutfit(from: row, in: database)
            if let existing = try Row.fetchOne(database, sql: "SELECT * FROM wear_events WHERE outfit_id = ? AND local_day = ?", arguments: [outfitID.uuidString, day]) {
                return try makeWearEvent(from: existing, in: database)
            }
            let eventID = UUID()
            try database.execute(
                sql: "INSERT INTO wear_events (id, outfit_id, local_day, worn_at, created_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [eventID.uuidString, outfitID.uuidString, day, timestamp, now()]
            )
            for itemID in outfit.itemIDs {
                try database.execute(
                    sql: "INSERT INTO wear_logs (id, item_id, outfit_id, worn_at, created_at, event_id) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [UUID().uuidString, itemID.uuidString, outfitID.uuidString, timestamp, now(), eventID.uuidString]
                )
            }
            guard let event = try Row.fetchOne(database, sql: "SELECT * FROM wear_events WHERE id = ?", arguments: [eventID.uuidString]) else { throw WardrobeRepositoryError.corruptRecord }
            return try makeWearEvent(from: event, in: database)
        }
    }

    func wearEvents() throws -> [WearEvent] {
        try database.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM wear_events ORDER BY worn_at DESC, created_at DESC")
                .map { try makeWearEvent(from: $0, in: database) }
        }
    }

    func undoWear(eventID: UUID) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM wear_events WHERE id = ?", arguments: [eventID.uuidString])
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.corruptRecord }
        }
    }

    func underusedItems(limit: Int = 8) throws -> [WearItemSummary] {
        try database.read { database in
            let rows = try Row.fetchAll(database, sql: """
            SELECT items.*, COUNT(wear_logs.id) AS wear_count, MAX(wear_logs.worn_at) AS last_worn_at
            FROM items LEFT JOIN wear_logs ON wear_logs.item_id = items.id
            GROUP BY items.id
            ORDER BY wear_count ASC, last_worn_at ASC, items.created_at DESC
            LIMIT ?
            """, arguments: [limit])
            return try rows.map { row in
                WearItemSummary(item: try garmentItem(from: row), wearCount: row["wear_count"], lastWornAt: row["last_worn_at"])
            }
        }
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
            if let eventID: String = try String.fetchOne(database, sql: "SELECT event_id FROM wear_logs WHERE id = ?", arguments: [id.uuidString]),
               let eventUUID = UUID(uuidString: eventID) {
                throw WardrobeRepositoryError.wearEventLogRequiresUndo(eventUUID)
            }
            try database.execute(sql: "DELETE FROM wear_logs WHERE id = ?", arguments: [id.uuidString])
            guard database.changesCount == 1 else { throw WardrobeRepositoryError.corruptRecord }
        }
    }

    func saveEmbedding(_ embedding: GarmentEmbedding) throws {
        guard isValid(embedding.vector, metadata: embedding.metadata) else { throw SemanticSearchError.invalidVector }
        try database.write { database in
            guard try itemExists(embedding.itemID, in: database) else { throw WardrobeRepositoryError.itemNotFound(embedding.itemID) }
            try upsertEmbedding(embedding, in: database)
        }
    }

    /// Saves an embedding only if the item still has the content used to produce it.
    /// The comparison and upsert share one write transaction so an edit cannot race
    /// between validation and persistence.
    @discardableResult
    func saveEmbedding(_ embedding: GarmentEmbedding, for itemSnapshot: GarmentItem) throws -> Bool {
        guard isValid(embedding.vector, metadata: embedding.metadata) else { throw SemanticSearchError.invalidVector }
        guard embedding.itemID == itemSnapshot.id else { return false }
        return try database.write { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM items WHERE id = ?", arguments: [itemSnapshot.id.uuidString]) else {
                return false
            }
            let currentItem = try garmentItem(from: row)
            guard currentItem.name == itemSnapshot.name,
                  currentItem.category == itemSnapshot.category,
                  currentItem.color == itemSnapshot.color,
                  currentItem.tags == itemSnapshot.tags,
                  currentItem.notes == itemSnapshot.notes else { return false }
            try upsertEmbedding(embedding, in: database)
            return true
        }
    }

    private func upsertEmbedding(_ embedding: GarmentEmbedding, in database: Database) throws {
        try database.execute(sql: """
                INSERT INTO item_embeddings (item_id, model_id, model_revision, dimension, normalized, preprocessing_version, content_hash, vector, indexed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                    model_id = excluded.model_id, model_revision = excluded.model_revision,
                    dimension = excluded.dimension, normalized = excluded.normalized,
                    preprocessing_version = excluded.preprocessing_version,
                    content_hash = excluded.content_hash, vector = excluded.vector, indexed_at = excluded.indexed_at
                """, arguments: [
                    embedding.itemID.uuidString, embedding.metadata.modelID, embedding.metadata.modelRevision,
                    embedding.metadata.dimension, embedding.metadata.normalized, embedding.metadata.preprocessingVersion,
                    embedding.contentHash, vectorData(embedding.vector), embedding.indexedAt
                ])
    }

    func embeddings(compatibleWith metadata: EmbeddingMetadata) throws -> [GarmentEmbedding] {
        try database.read { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT * FROM item_embeddings
                WHERE model_id = ? AND model_revision = ? AND dimension = ?
                  AND normalized = ? AND preprocessing_version = ?
                """, arguments: [metadata.modelID, metadata.modelRevision, metadata.dimension, metadata.normalized, metadata.preprocessingVersion])
            return try rows.compactMap { row in
                let vector = try vectorValues(row["vector"] as Data)
                guard isValid(vector, metadata: metadata) else { return nil }
                return GarmentEmbedding(itemID: try uuid(row["item_id"]), metadata: metadata, contentHash: row["content_hash"], vector: vector, indexedAt: row["indexed_at"])
            }
        }
    }

    func recordRecommendationEvent(_ event: RecommendationEvent) throws {
        try database.write { database in
            try database.execute(sql: """
                INSERT INTO recommendation_events (id, recommendation_id, candidate_ids_json, context_snapshot, source, outcome, occurred_at, locked_ids_json, requested_slots_json, outcome_reason)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [event.id.uuidString, event.recommendationID.uuidString, try encode(event.candidateIDs.map(\.uuidString)), event.contextSnapshot, event.source.rawValue, event.outcome.rawValue, event.occurredAt, try encode(event.lockedItemIDs.map(\.uuidString)), try encode(event.requestedSlots.map(\.rawValue)), event.outcomeReason?.rawValue])
        }
    }

    func recommendationEvents(limit: Int = 500) throws -> [RecommendationEvent] {
        try database.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM recommendation_events ORDER BY occurred_at DESC LIMIT ?", arguments: [limit]).map { row in
                guard let source = RecommendationSource(rawValue: row["source"]),
                      let outcome = RecommendationOutcome(rawValue: row["outcome"]) else { throw WardrobeRepositoryError.corruptRecord }
                let ids: [String] = try decode(row["candidate_ids_json"])
                let lockedIDs: [String] = try decode(row["locked_ids_json"])
                let slots: [String] = try decode(row["requested_slots_json"])
                let reason: String? = row["outcome_reason"]
                return RecommendationEvent(id: try uuid(row["id"]), recommendationID: try uuid(row["recommendation_id"]), candidateIDs: ids.compactMap(UUID.init(uuidString:)), contextSnapshot: row["context_snapshot"], source: source, outcome: outcome, occurredAt: row["occurred_at"], lockedItemIDs: lockedIDs.compactMap(UUID.init(uuidString:)), requestedSlots: slots.compactMap(RecommendationSlot.init(rawValue:)), outcomeReason: reason.flatMap(RecommendationSkipReason.init(rawValue:)))
            }
        }
    }

    func recommendationContext(recommendationID: UUID) throws -> (snapshot: String, source: RecommendationSource, lockedItemIDs: [UUID], requestedSlots: [RecommendationSlot])? {
        try database.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT context_snapshot, source, locked_ids_json, requested_slots_json FROM recommendation_events WHERE recommendation_id = ? ORDER BY occurred_at ASC LIMIT 1", arguments: [recommendationID.uuidString]),
                  let source = RecommendationSource(rawValue: row["source"]) else { return nil }
            let ids: [String] = try decode(row["locked_ids_json"])
            let slots: [String] = try decode(row["requested_slots_json"])
            return (row["context_snapshot"], source, ids.compactMap(UUID.init(uuidString:)), slots.compactMap(RecommendationSlot.init(rawValue:)))
        }
    }

    private func localDay(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func validate(_ draft: GarmentDraft) throws -> GarmentDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WardrobeRepositoryError.invalidName }
        let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GarmentTaxonomy.isKnownCategory(category) else { throw WardrobeRepositoryError.invalidCategory }
        var seenTags = Set<String>()
        let tags = draft.tags.compactMap { tag -> String? in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seenTags.insert(normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted else { return nil }
            return normalized
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return GarmentDraft(
            name: name, category: category, color: normalizedOptional(draft.color),
            tags: tags, notes: normalizedOptional(draft.notes), imagePath: draft.imagePath,
            classification: draft.classification, availability: draft.availability
        )
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func garmentItem(from row: Row) throws -> GarmentItem {
    GarmentItem(
        id: try uuid(row["id"]), name: row["name"], category: row["category"], color: row["color"],
        tags: try decode(row["tags_json"]), notes: row["notes"], imagePath: row["image_path"], classification: try decode(row["classification_json"]),
        availability: GarmentAvailability(rawValue: row["availability"]) ?? .active,
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

private func outfitPlan(from row: Row) throws -> OutfitPlan {
    OutfitPlan(id: try uuid(row["id"]), outfitID: try uuid(row["outfit_id"]), scheduledFor: row["scheduled_for"], occasion: row["occasion"], sourceEventID: row["source_event_id"], createdAt: row["created_at"], updatedAt: row["updated_at"])
}

private func wearLog(from row: Row) throws -> WearLog {
    WearLog(
        id: try uuid(row["id"]), itemID: try uuid(row["item_id"]), outfitID: try optionalUUID(row["outfit_id"]),
        wornAt: row["worn_at"], createdAt: row["created_at"]
    )
}

private func makeWearEvent(from row: Row, in database: Database) throws -> WearEvent {
    let id = try uuid(row["id"])
    let itemIDs = try String.fetchAll(database, sql: "SELECT item_id FROM wear_logs WHERE event_id = ? ORDER BY id", arguments: [id.uuidString])
        .compactMap(UUID.init(uuidString:))
    return WearEvent(id: id, outfitID: try optionalUUID(row["outfit_id"]), wornAt: row["worn_at"], localDay: row["local_day"], createdAt: row["created_at"], itemIDs: itemIDs)
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

private func encode<T: Encodable>(_ value: T?) throws -> String? {
    guard let value else { return nil }
    return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

private func decode<T: Decodable>(_ value: String?) throws -> T? {
    guard let value else { return nil }
    return try JSONDecoder().decode(T.self, from: Data(value.utf8))
}

private func uuid(_ value: String) throws -> UUID {
    guard let value = UUID(uuidString: value) else { throw WardrobeRepositoryError.corruptRecord }
    return value
}

private func optionalUUID(_ value: String?) throws -> UUID? {
    guard let value else { return nil }
    return try uuid(value)
}

private func vectorData(_ vector: [Float]) -> Data {
    vector.withUnsafeBufferPointer { Data(buffer: $0) }
}

private func vectorValues(_ data: Data) throws -> [Float] {
    guard data.count.isMultiple(of: MemoryLayout<Float>.size) else { throw WardrobeRepositoryError.corruptRecord }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

private func isValid(_ vector: [Float], metadata: EmbeddingMetadata) -> Bool {
    guard vector.count == metadata.dimension, vector.allSatisfy(\.isFinite) else { return false }
    let magnitudeSquared = vector.reduce(Float.zero) { $0 + $1 * $1 }
    return magnitudeSquared.isFinite && magnitudeSquared > 0
}
