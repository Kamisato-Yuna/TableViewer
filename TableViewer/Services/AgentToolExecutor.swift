import Foundation

// Each conversation owns its driver connection. UI navigation never reconnects this engine.
actor AgentToolExecutor {
    private var resources: [UUID: (ConnectionProfile, DatabaseEngine)] = [:]
    func execute(sessionID: UUID, action: AgentAction, profile: ConnectionProfile, object: DatabaseObject?, readOnly: Bool = false) async throws -> String {
        guard profile.id == action.connectionID else { throw DatabaseFailure(String(localized: "请连接此会话原来的数据库后再批准操作。")) }
        var credential = ""
        do {
            let engine: DatabaseEngine
            if let resource = resources[sessionID], resource.0 == profile { engine = resource.1 }
            else {
                if let previous = resources.removeValue(forKey: sessionID) { await previous.1.disconnect() }
                credential = profile.kind == .sqlite ? "" : try ConnectionVault.read(id: profile.id)
                let fresh = DatabaseEngine()
                _ = try await fresh.connect(profile, secret: credential)
                resources[sessionID] = (profile, fresh); engine = fresh
            }
            switch action.call.function.name {
            case "inspect_schema":
                let objects = try await engine.objects()
                let columns: [ColumnInfo]
                if let object { columns = try await engine.columns(for: object) } else { columns = [] }
                let fields: [[String: Any]] = columns.map { ["name": $0.name, "type": $0.type, "primaryKey": $0.isPrimaryKey] }
                let kinds: [[String: Any]] = objects.prefix(100).map { ["name": $0.qualifiedName, "isView": $0.isView] }
                return try jsonText(["objects": objects.prefix(100).map(\.qualifiedName), "objectKinds": kinds, "selectedObject": object?.name ?? "", "columns": fields], pretty: true)
            case "execute_query":
                guard let query = action.query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DatabaseFailure(String(localized: "工具调用缺少 query。")) }
                let result = try await engine.run(query, readOnly: readOnly)
                let rows: [[Any]] = result.rows.prefix(100).map { $0.cells.map { value -> Any in value.isNull ? NSNull() : value.display } }
                return try jsonText(["columns": result.columns.map(\.name), "rows": rows, "affectedRows": result.affectedRows, "truncated": result.hasMore || result.rows.count > 100], pretty: true)
            default: throw DatabaseFailure(String(localized: "不支持模型提出的工具：\(action.call.function.name)"))
            }
        } catch {
            let message = credential.isEmpty ? error.localizedDescription : error.localizedDescription.replacingOccurrences(of: credential, with: "<credential>")
            throw DatabaseFailure(message)
        }
    }
    func close() async {
        let engines = resources.values.map(\.1); resources = [:]
        for engine in engines { await engine.disconnect() }
    }
}
