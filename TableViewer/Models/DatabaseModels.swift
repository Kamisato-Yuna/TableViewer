import Foundation

enum DatabaseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sqlite = "SQLite", postgresql = "PostgreSQL", mongodb = "MongoDB"
    var id: String { rawValue }
    var symbol: String { switch self { case .sqlite: "externaldrive"; case .postgresql: "server.rack"; case .mongodb: "leaf" } }
    var defaultPort: String { self == .postgresql ? "5432" : "27017" }
}

struct ConnectionProfile: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var kind: DatabaseKind = .sqlite
    var path = ""
    var host = "localhost"
    var port = "5432"
    var database = "postgres"
    var user = ""
    var sslMode = "prefer"
    var isDemo = false
    var fileBookmark: Data?
    var directoryBookmark: Data?
    var subtitle: String { kind == .sqlite ? (isDemo ? String(localized: "本地 · 示例数据库", bundle: TableViewerLocalization.bundle) : URL(fileURLWithPath: path).lastPathComponent) : "\(host):\(port) / \(database)" }
}

struct DatabaseObject: Identifiable, Hashable, Sendable {
    var name: String
    var schema: String = ""
    var isView = false
    var id: String { schema + "." + name }
    var qualifiedName: String { schema.isEmpty ? quoteIdentifier(name) : quoteIdentifier(schema) + "." + quoteIdentifier(name) }
}

struct ColumnInfo: Identifiable, Sendable {
    var name: String
    var type: String = "TEXT"
    var isPrimaryKey = false
    var isEditable = true
    var defaultValue: String?
    var id: String { name }
}

enum CellValue: Equatable, Sendable {
    case null, text(String), blob(Data)
    var display: String { switch self { case .null: "NULL"; case .text(let s): s; case .blob(let d): "⟨BLOB · \(d.count) bytes⟩" } }
    var string: String? { if case .text(let s) = self { s } else { nil } }
    var isNull: Bool { self == .null }
}

struct DataRow: Identifiable, Sendable {
    let id = UUID()
    var cells: [CellValue]
    var document: String?
}

struct QueryResult: Sendable {
    var columns: [ColumnInfo] = []
    var rows: [DataRow] = []
    var affectedRows = 0
    var elapsed: Double = 0
    var hasMore = false
}

struct DatabaseFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = TableViewerLocalization.bundle.localizedString(forKey: message, value: nil, table: nil) }
}

func quoteIdentifier(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

func jsonText(_ value: Any, pretty: Bool = false) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: pretty ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed] : [.sortedKeys, .fragmentsAllowed])
    return String(decoding: data, as: UTF8.self)
}

func jsonObject(_ text: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw DatabaseFailure(String(localized: "请输入一个 JSON 对象。", bundle: TableViewerLocalization.bundle)) }
    return object
}

func numericValue(_ value: Any?) -> Int {
    if let n = value as? NSNumber { return n.intValue }
    if let v = value as? [String: String], let s = v["$numberInt"] ?? v["$numberLong"] { return Int(s) ?? 0 }
    return 0
}

/// The standalone shell lives in Contents/Helpers, so its main bundle has no resources.
enum TableViewerLocalization {
    static let bundle: Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" { return .main }
        if let executable = Bundle.main.executableURL {
            let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if app.pathExtension == "app", let bundle = Bundle(url: app) {
                let arguments = CommandLine.arguments
                let index = arguments.firstIndex(of: "--tableviewer-language")
                let requested = index.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "en"
                let language = ["en", "zh-Hans"].contains(requested) ? requested : "en"
                if let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) { return localized }
                return bundle
            }
        }
        return .main
    }()
}
