import Foundation
import GRDB

// MARK: - Activity Event Model

struct ActivityEvent: Identifiable, Codable {
    let id: Int64?
    var comicId: String?
    var action: ActionType
    var oldValue: String?
    var newValue: String?
    var timestamp: Date
    var userConfirmed: Bool

    enum ActionType: String, Codable, CaseIterable {
        // File lifecycle
        case imported = "imported"
        case deleted = "deleted"
        case renamed = "renamed"

        // Metadata edits
        case titleChanged = "title_changed"
        case seriesChanged = "series_changed"
        case issueChanged = "issue_number_changed"
        case publisherChanged = "publisher_changed"
        case writerChanged = "writer_changed"
        case artistChanged = "artist_changed"
        case yearChanged = "year_changed"
        case statusChanged = "status_changed"
        case ratingChanged = "rating_changed"
        case favoriteToggled = "favorite_toggled"

        // Knowledge base
        case knowledgeAdded = "knowledge_added"
        case knowledgeDeleted = "knowledge_deleted"

        var displayName: String {
            switch self {
            case .imported: return "Imported"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .titleChanged: return "Title Updated"
            case .seriesChanged: return "Series Updated"
            case .issueChanged: return "Issue # Updated"
            case .publisherChanged: return "Publisher Updated"
            case .writerChanged: return "Writer Updated"
            case .artistChanged: return "Artist Updated"
            case .yearChanged: return "Year Updated"
            case .statusChanged: return "Status Changed"
            case .ratingChanged: return "Rating Changed"
            case .favoriteToggled: return "Favorite Toggled"
            case .knowledgeAdded: return "Knowledge Added"
            case .knowledgeDeleted: return "Knowledge Removed"
            }
        }

        var icon: String {
            switch self {
            case .imported: return "arrow.down.circle.fill"
            case .deleted: return "trash.fill"
            case .renamed: return "pencil.circle.fill"
            case .titleChanged: return "textformat"
            case .seriesChanged: return "books.vertical.fill"
            case .issueChanged: return "number.circle.fill"
            case .publisherChanged: return "building.2.fill"
            case .writerChanged: return "person.fill"
            case .artistChanged: return "paintbrush.pointed.fill"
            case .yearChanged: return "calendar"
            case .statusChanged: return "checkmark.circle.fill"
            case .ratingChanged: return "star.fill"
            case .favoriteToggled: return "heart.fill"
            case .knowledgeAdded: return "brain.head.profile"
            case .knowledgeDeleted: return "brain.head.profile"
            }
        }

        var color: String {
            switch self {
            case .imported: return "blue"
            case .deleted: return "red"
            case .renamed: return "orange"
            case .statusChanged: return "green"
            case .favoriteToggled: return "pink"
            case .knowledgeAdded, .knowledgeDeleted: return "purple"
            default: return "primary"
            }
        }
    }

    init(
        id: Int64? = nil,
        comicId: String? = nil,
        action: ActionType,
        oldValue: String? = nil,
        newValue: String? = nil,
        timestamp: Date = Date(),
        userConfirmed: Bool = false
    ) {
        self.id = id
        self.comicId = comicId
        self.action = action
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = timestamp
        self.userConfirmed = userConfirmed
    }
}

// MARK: - GRDB Conformance

extension ActivityEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "activity_log"

    enum Columns {
        static let id = Column("id")
        static let comicId = Column("comic_id")
        static let action = Column("action")
        static let oldValue = Column("old_value")
        static let newValue = Column("new_value")
        static let timestamp = Column("timestamp")
        static let userConfirmed = Column("user_confirmed")
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.comicId] = comicId
        container[Columns.action] = action.rawValue
        container[Columns.oldValue] = oldValue
        container[Columns.newValue] = newValue
        container[Columns.timestamp] = timestamp
        container[Columns.userConfirmed] = userConfirmed
    }

    init(row: Row) throws {
        id = row[Columns.id]
        comicId = row[Columns.comicId]
        let rawAction: String = row[Columns.action]
        action = ActivityEvent.ActionType(rawValue: rawAction) ?? .titleChanged
        oldValue = row[Columns.oldValue]
        newValue = row[Columns.newValue]
        timestamp = row[Columns.timestamp] ?? Date()
        userConfirmed = row[Columns.userConfirmed] ?? false
    }
}
