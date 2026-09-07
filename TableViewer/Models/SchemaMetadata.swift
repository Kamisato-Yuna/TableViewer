import Foundation

struct SchemaField: Identifiable, Sendable {
    var name: String
    var type: String
    var constraints: [String] = []
    var defaultValue: String?
    var id: String { name }
}
struct SchemaIndex: Identifiable, Sendable {
    var name: String
    var definition: String
    var unique: Bool
    var id: String { name }
}
struct TableRelationship: Identifiable, Sendable {
    var name: String
    var source: DatabaseObject
    var target: DatabaseObject
    var sourceColumns: [String]
    var targetColumns: [String]
    var id: String { source.id + "." + name }
}
struct SchemaMetadata: Sendable {
    var fields: [SchemaField] = []
    var indexes: [SchemaIndex] = []
    var relationships: [TableRelationship] = []
    var ddl = ""
    var notice = ""
}
