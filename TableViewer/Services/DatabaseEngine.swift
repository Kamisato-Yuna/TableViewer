import Foundation
import Darwin

/// All blocking driver calls are serialized off the main actor.
actor DatabaseEngine {
    private var sqlite: OpaquePointer?
    private var postgres: OpaquePointer?
    private var mongo: UnsafeMutableRawPointer?
    private(set) var profile: ConnectionProfile?
    private var scopedURLs: [URL] = []
    static let pageSize = 200
    private let postgresQueryTimeout: TimeInterval

    init(postgresQueryTimeout: TimeInterval = 20) { self.postgresQueryTimeout = postgresQueryTimeout }

    func disconnect() {
        if let sqlite { sqlite3_close_v2(sqlite) }
        if let postgres { PQfinish(postgres) }
        if let mongo { tv_mongo_close(mongo) }
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }; scopedURLs = []
        sqlite = nil; postgres = nil; mongo = nil; profile = nil
    }

    func connect(_ profile: ConnectionProfile, secret: String) throws -> [DatabaseObject] {
        disconnect()
        self.profile = profile
        do {
            switch profile.kind {
            case .sqlite:
                func resolveScope(_ bookmark: Data) throws -> URL {
                    var stale = false
                    let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                    guard url.startAccessingSecurityScopedResource() else { throw DatabaseFailure(String(localized: "文件授权已失效，请编辑连接并重新选择 SQLite 文件及所在文件夹。")) }
                    scopedURLs.append(url)
                    return url
                }
                // SQLite writes sibling -wal, -shm and journal files. A file-only
                // sandbox extension cannot authorize those sibling files.
                if let bookmark = profile.directoryBookmark { _ = try resolveScope(bookmark) }
                var fileURL = URL(fileURLWithPath: profile.path)
                if let bookmark = profile.fileBookmark {
                    fileURL = try resolveScope(bookmark)
                }
                guard sqlite3_open_v2(fileURL.path, &sqlite, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw sqliteError() }
                sqlite3_busy_timeout(sqlite, 3000)
                _ = try sql("PRAGMA foreign_keys = ON")
            case .postgresql:
                func escape(_ s: String) -> String { "'" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'" }
                let options = ["host": profile.host, "port": profile.port, "dbname": profile.database, "user": profile.user, "password": secret, "sslmode": profile.sslMode, "connect_timeout": "8", "application_name": "TableViewer", "options": "-c statement_timeout=15000"]
                let info = options.map { "\($0.key)=\(escape($0.value))" }.joined(separator: " ")
                postgres = PQconnectdb(info)
                guard let postgres, PQstatus(postgres) == CONNECTION_OK else { throw postgresError() }
                PQsetClientEncoding(postgres, "UTF8")
            case .mongodb:
                var error: UnsafeMutablePointer<CChar>?
                mongo = tv_mongo_open(secret, &error)
                guard mongo != nil else { throw nativeError(error) }
                _ = try mongoCommand(["ping": 1])
            }
            return try objects()
        } catch { disconnect(); throw error }
    }

    func objects() throws -> [DatabaseObject] {
        guard let profile else { throw DatabaseFailure(String(localized: "请先连接数据库。")) }
        switch profile.kind {
        case .sqlite:
            return try catalogSQL("SELECT name, type FROM sqlite_schema WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name").rows.map {
                DatabaseObject(name: $0.cells[0].display, isView: $0.cells[1].display == "view")
            }
        case .postgresql:
            return try catalogSQL("SELECT table_name, table_schema, table_type FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY table_schema, table_name").rows.map {
                DatabaseObject(name: $0.cells[0].display, schema: $0.cells[1].display, isView: $0.cells[2].display == "VIEW")
            }
        case .mongodb:
            let response = try mongoCommand(["listCollections": 1, "nameOnly": true, "cursor": ["batchSize": 1000]])
            var documents = (response["cursor"] as? [String: Any])?["firstBatch"] as? [[String: Any]] ?? []
            var cursorID = numericValue((response["cursor"] as? [String: Any])?["id"])
            while cursorID != 0 {
                let more = try mongoCommand(["getMore": ["$numberLong": String(cursorID)], "collection": "$cmd.listCollections", "batchSize": 1000])
                let cursor = more["cursor"] as? [String: Any] ?? [:]
                documents += cursor["nextBatch"] as? [[String: Any]] ?? []
                cursorID = numericValue(cursor["id"])
            }
            return documents.compactMap { doc in
                guard let name = doc["name"] as? String else { return nil }
                return DatabaseObject(name: name, isView: doc["type"] as? String == "view")
            }.sorted { $0.name < $1.name }
        }
    }

    func replicaSetStatus() throws -> ReplicaSnapshot {
        guard profile?.kind == .mongodb else { throw DatabaseFailure(String(localized: "副本集视图仅适用于 MongoDB。")) }
        let hello = try mongoCommand(["hello": 1], name: "hello", database: "admin")
        guard hello["setName"] != nil else { return try ReplicaSnapshot.parse(hello: hello, status: nil, notice: String(localized: "当前连接未报告副本集。独立实例或 mongos 不提供成员复制状态。")) }
        do {
            let status = try mongoCommand(["replSetGetStatus": 1], name: "replSetGetStatus", database: "admin")
            return try ReplicaSnapshot.parse(hello: hello, status: status)
        } catch {
            return try ReplicaSnapshot.parse(hello: hello, status: nil, notice: String(localized: "已读取拓扑，但无法读取成员状态：\(error.localizedDescription)。健康状态和复制延迟暂不可用。"))
        }
    }

    func columns(for object: DatabaseObject) throws -> [ColumnInfo] {
        guard let profile else { throw DatabaseFailure(String(localized: "未连接。")) }
        switch profile.kind {
        case .sqlite:
            return try catalogSQL("SELECT * FROM pragma_table_xinfo(?) ORDER BY cid", parameters: [.text(object.name)]).rows.map { row in
                ColumnInfo(name: row.cells[1].display, type: row.cells[2].display, isPrimaryKey: (Int(row.cells[5].display) ?? 0) > 0, isEditable: row.cells.count < 7 || row.cells[6].display == "0", defaultValue: row.cells[4].string)
            }
        case .postgresql:
            let query = """
            SELECT c.column_name, c.data_type,
              EXISTS(SELECT 1 FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage k ON k.constraint_name=tc.constraint_name AND k.constraint_schema=tc.constraint_schema AND k.table_name=tc.table_name
                WHERE tc.constraint_type='PRIMARY KEY' AND tc.table_schema=c.table_schema AND tc.table_name=c.table_name AND k.column_name=c.column_name)::text,
              c.is_generated, c.column_default, c.is_identity
            FROM information_schema.columns c WHERE c.table_schema=$1 AND c.table_name=$2 ORDER BY c.ordinal_position
            """
            return try catalogSQL(query, parameters: [.text(object.schema), .text(object.name)]).rows.map { row in
                ColumnInfo(name: row.cells[0].display, type: row.cells[1].display, isPrimaryKey: row.cells[2].display == "true", isEditable: row.cells[3].display == "NEVER" && row.cells[5].display != "YES", defaultValue: row.cells[4].string)
            }
        case .mongodb: return []
        }
    }

    func browse(_ object: DatabaseObject, page: Int = 0, sort: String? = nil, ascending: Bool = true, condition: String = "", pageSize: Int = DatabaseEngine.pageSize) throws -> QueryResult {
        let start = Date()
        let pageSize = max(1, min(10000, pageSize))
        let page = max(0, page)
        guard let profile else { throw DatabaseFailure(String(localized: "未连接。")) }
        var result: QueryResult
        if profile.kind == .mongodb {
            var command: [String: Any] = ["find": object.name, "filter": condition.isEmpty ? [:] : try jsonObject(condition), "skip": page * pageSize, "limit": pageSize + 1, "batchSize": pageSize + 1, "maxTimeMS": 15000]
            command["sort"] = [sort ?? "_id": ascending ? 1 : -1]
            var response = try mongoCommand(command)
            var cursor = response["cursor"] as? [String: Any] ?? [:]
            var documents = cursor["firstBatch"] as? [[String: Any]] ?? []
            var cursorID = numericValue(cursor["id"])
            defer { if cursorID != 0 { _ = try? mongoCommand(["killCursors": object.name, "cursors": [["$numberLong": String(cursorID)]]]) } }
            while cursorID != 0 && documents.count < pageSize + 1 {
                let more = try mongoCommand(["getMore": ["$numberLong": String(cursorID)], "collection": object.name, "batchSize": pageSize + 1 - documents.count])
                cursor = more["cursor"] as? [String: Any] ?? [:]
                documents += cursor["nextBatch"] as? [[String: Any]] ?? []
                cursorID = numericValue(cursor["id"])
            }
            response["cursor"] = ["firstBatch": documents]
            result = try documentsResult(response)
        } else {
            let metadata = try columns(for: object)
            let ordering = sort.map { [quoteIdentifier($0) + (ascending ? " ASC" : " DESC")] } ?? metadata.filter(\.isPrimaryKey).map { quoteIdentifier($0.name) }
            let order = ordering.isEmpty ? "" : " ORDER BY " + ordering.joined(separator: ", ")
            let filter = condition.isEmpty ? "" : " WHERE (" + condition + ")"
            let query = "SELECT * FROM \(object.qualifiedName)\(filter)\(order) LIMIT \(pageSize + 1) OFFSET \(page * pageSize)"
            result = condition.isEmpty ? try sql(query) : try run(query, readOnly: true)
            result.columns = result.columns.map { col in metadata.first { $0.name == col.name } ?? col }
        }
        result.hasMore = result.rows.count > pageSize
        result.rows = Array(result.rows.prefix(pageSize))
        result.elapsed = Date().timeIntervalSince(start)
        return result
    }

    func postgreSQLStandardConformingStrings() throws -> Bool {
        guard let postgres, let value = PQparameterStatus(postgres, "standard_conforming_strings") else {
            throw DatabaseFailure(String(localized: "无法读取 PostgreSQL 字符串会话设置。"))
        }
        switch String(cString: value) {
        case "on": return true
        case "off": return false
        default: throw DatabaseFailure(String(localized: "无法读取 PostgreSQL 字符串会话设置。"))
        }
    }

    func run(_ query: String, readOnly: Bool = false) throws -> QueryResult {
        if readOnly {
            if let sqlite {
                sqlite3_set_authorizer(sqlite, { _, action, first, second, _, _ in
                    switch action {
                    case SQLITE_SELECT, SQLITE_READ, SQLITE_RECURSIVE: return SQLITE_OK
                    case SQLITE_FUNCTION:
                        let name = second.map { String(cString: $0).lowercased() } ?? ""
                        return ["load_extension", "writefile"].contains(name) ? SQLITE_DENY : SQLITE_OK
                    case SQLITE_PRAGMA:
                        let name = first.map { String(cString: $0).lowercased() } ?? ""
                        return ["table_info", "table_xinfo", "index_list", "index_info", "index_xinfo", "foreign_key_list"].contains(name) ? SQLITE_OK : SQLITE_DENY
                    default: return SQLITE_DENY
                    }
                }, nil)
                defer { sqlite3_set_authorizer(sqlite, nil, nil) }
                return try run(query)
            }
            if let original = postgres {
                let standardStrings = try postgreSQLStandardConformingStrings()
                let words = SQLScript.tokens(query, standardConformingStrings: standardStrings)
                guard let first = words.first, ["SELECT", "WITH", "VALUES", "SHOW", "EXPLAIN"].contains(first),
                      !words.contains("ANALYZE") else { throw DatabaseFailure(String(localized: "只读模式已阻止此命令。")) }
                // A separate short-lived connection also isolates PostgreSQL's temporary
                // object/sequence exceptions to READ ONLY. Never alter the user's session.
                guard let options = PQconninfo(original) else { throw postgresError() }
                defer { PQconninfoFree(options) }
                var keys: [UnsafeMutablePointer<CChar>?] = [], values: [UnsafeMutablePointer<CChar>?] = []
                var index = 0
                while let keyword = options[index].keyword {
                    if let value = options[index].val, value.pointee != 0 { keys.append(strdup(keyword)); values.append(strdup(value)) }
                    index += 1
                }
                keys.append(nil); values.append(nil)
                defer { keys.forEach { free($0) }; values.forEach { free($0) } }
                let keyPointers = keys.map { $0.map { UnsafePointer($0) } }, valuePointers = values.map { $0.map { UnsafePointer($0) } }
                let fresh = keyPointers.withUnsafeBufferPointer { keys in valuePointers.withUnsafeBufferPointer { values in PQconnectdbParams(keys.baseAddress, values.baseAddress, 0) } }
                guard let fresh else { throw DatabaseFailure(String(localized: "无法连接 PostgreSQL。")) }
                guard PQstatus(fresh) == CONNECTION_OK else { let message = String(cString: PQerrorMessage(fresh)); PQfinish(fresh); throw DatabaseFailure(message) }
                let savedProfile = profile
                postgres = fresh
                defer {
                    if postgres == fresh { _ = try? sql("ROLLBACK"); PQfinish(fresh) }
                    postgres = original; profile = savedProfile
                }
                _ = try sql("SET standard_conforming_strings = " + (standardStrings ? "on" : "off"))
                _ = try sql("BEGIN READ ONLY")
                return try run(query)
            }
            if profile?.kind == .mongodb {
                let command = try jsonObject(query)
                guard Self.isReadOnlyMongo(command, name: try Self.mongoCommandName(query)) else { throw DatabaseFailure(String(localized: "只读模式已阻止此 MongoDB 命令。")) }
            }
        }
        let start = Date()
        var result: QueryResult
        if profile?.kind == .mongodb {
            let command = try jsonObject(query)
            let name = try Self.mongoCommandName(query)
            let response = try mongoCommand(command, name: name)
            if response["cursor"] != nil { result = try documentsResult(response) }
            else { result = QueryResult(columns: [ColumnInfo(name: "result", type: "JSON")], rows: [DataRow(cells: [.text(try jsonText(response, pretty: true))])]) }
            // Raw commands expose one batch; release any remaining cursor instead of leaking it.
            if let cursor = response["cursor"] as? [String: Any], numericValue(cursor["id"]) != 0,
               let ns = cursor["ns"] as? String, let dot = ns.firstIndex(of: ".") {
                result.hasMore = true
                _ = try? mongoCommand(["killCursors": String(ns[ns.index(after: dot)...]), "cursors": [cursor["id"]!]])
            }
        } else { result = try sql(query) }
        result.elapsed = Date().timeIntervalSince(start)
        return result
    }

    static func mongoCommandName(_ query: String) throws -> String {
        let regex = try NSRegularExpression(pattern: #"^\s*\{\s*("(?:[^"\\]|\\.)*")\s*:"#)
        guard let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query),
              let name = try JSONSerialization.jsonObject(with: Data(query[range].utf8), options: .fragmentsAllowed) as? String else { throw DatabaseFailure(String(localized: "JSON 的第一个字段必须是 MongoDB 命令名。")) }
        return name
    }
    static func isReadOnlyMongo(_ command: [String: Any], name: String) -> Bool {
        let reads: Set<String> = ["find", "aggregate", "count", "distinct", "listCollections", "listIndexes", "collStats", "dbStats", "ping", "hello"]
        guard reads.contains(name), Set(command.keys).intersection(reads) == [name] else { return false }
        func unsafe(_ value: Any) -> Bool {
            if let object = value as? [String: Any] {
                if object.keys.contains(where: { ["$out", "$merge", "$function", "$accumulator", "$where"].contains($0) }) { return true }
                return object.values.contains(where: unsafe)
            }
            if let array = value as? [Any] { return array.contains(where: unsafe) }
            return false
        }
        return !unsafe(command)
    }

    func estimate(_ query: String) -> QueryEstimate {
        let words = SQLScript.tokens(query)
        do {
            if profile?.kind == .sqlite {
                guard let first = words.first, ["SELECT", "WITH", "UPDATE", "DELETE", "INSERT", "REPLACE"].contains(first) else {
                    return QueryEstimate(severity: .unknown, summary: String(localized: "此命令无法预估规模；执行前请核对。"))
                }
                let plan = try run("EXPLAIN QUERY PLAN " + query, readOnly: true)
                let details = plan.rows.map { $0.cells.map(\.display).joined(separator: " · ") }.joined(separator: "\n")
                let scans = details.components(separatedBy: "\n").filter { $0.contains("SCAN ") && !$0.contains("SCAN CONSTANT ROW") }.count
                if scans == 0 && details.contains("SCAN CONSTANT ROW") && !query.contains("(") {
                    return QueryEstimate(severity: .normal, summary: String(localized: "常量表达式，无表扫描。"), details: details, rows: 1)
                }
                return QueryEstimate(severity: scans > 1 ? .large : .unknown,
                    summary: scans > 1 ? String(localized: "查询计划包含多处扫描，可能产生大量工作。") : scans > 0 ? String(localized: "查询计划包含扫描；SQLite 不提供可靠的预计行数。") : String(localized: "SQLite 计划不提供可靠行数；索引访问仍可能很大。"), details: details)
            }
            if profile?.kind == .postgresql {
                guard let first = words.first, ["SELECT", "WITH", "UPDATE", "DELETE", "INSERT", "VALUES"].contains(first) else {
                    return QueryEstimate(severity: .unknown, summary: String(localized: "此命令无法预估规模；执行前请核对。"))
                }
                let output = try run("EXPLAIN (FORMAT JSON) " + query, readOnly: true)
                let text = output.rows.first?.cells.first?.display ?? ""
                let plans = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]]
                let plan = plans?.first?["Plan"] as? [String: Any] ?? [:]
                func maximum(_ node: [String: Any], key: String) -> Double {
                    max((node[key] as? NSNumber)?.doubleValue ?? 0, (node["Plans"] as? [[String: Any]] ?? []).map { maximum($0, key: key) }.max() ?? 0)
                }
                let rows = maximum(plan, key: "Plan Rows"), cost = maximum(plan, key: "Total Cost")
                return QueryEstimate(severity: rows >= 1_000_000 || cost >= 1_000_000 ? .excessive : rows >= 100_000 || cost >= 100_000 ? .large : .normal,
                    summary: String(localized: "计划估算最大节点行数：") + String(format: "%.0f", rows) + String(localized: "；成本：") + String(format: "%.0f", cost), details: text, rows: rows)
            }
            if profile?.kind == .mongodb {
                let command = try jsonObject(query)
                if let collection = command["find"] as? String {
                    let explained = try mongoCommand(["explain": ["find": collection, "filter": command["filter"] ?? [:], "sort": command["sort"] ?? [:]], "verbosity": "queryPlanner"], name: "explain", explainedCommandName: "find")
                    let details = try jsonText(explained, pretty: true)
                    return QueryEstimate(severity: details.contains("COLLSCAN") ? .large : .unknown,
                        summary: String(localized: "MongoDB queryPlanner 未执行查询，不提供可靠工作量；请检查扫描计划。"), details: details)
                }
            }
        } catch { return QueryEstimate(severity: .unknown, summary: String(localized: "无法取得执行前估算。"), details: error.localizedDescription) }
        return QueryEstimate(severity: .unknown, summary: String(localized: "此入口没有可靠的无执行估算；请确认操作范围。"))
    }

    func update(_ object: DatabaseObject, columns: [ColumnInfo], original: DataRow, values: [CellValue], document: String?) throws {
        if profile?.kind == .mongodb {
            guard let old = original.document, let document else { throw DatabaseFailure(String(localized: "缺少原始文档。")) }
            let oldJSON = try jsonObject(old), newJSON = try jsonObject(document)
            guard let oldID = oldJSON["_id"], let newID = newJSON["_id"], try jsonText(oldID) == jsonText(newID) else { throw DatabaseFailure(String(localized: "编辑文档时不能修改 _id。")) }
            let changed = try Set(oldJSON.keys).union(newJSON.keys).filter { key in
                try oldJSON[key].map { try jsonText($0) } != newJSON[key].map { try jsonText($0) }
            }
            guard !changed.isEmpty else { return }
            guard !changed.contains(where: { $0.contains(".") || $0.hasPrefix("$") }) else { throw DatabaseFailure(String(localized: "包含点号或以 $ 开头的字段请使用 MongoDB 命令编辑。")) }
            // Only write changed top-level fields; preserve concurrent additions and untouched BSON values.
            var conditions: [[String: Any]] = [["_id": ["$eq": oldID]]]
            var set: [String: Any] = [:], unset: [String: Any] = [:]
            for key in changed {
                if let oldValue = oldJSON[key] { conditions.append([key: ["$eq": oldValue, "$exists": true]]) }
                else { conditions.append([key: ["$exists": false]]) }
                if let newValue = newJSON[key] { set[key] = newValue } else { unset[key] = "" }
            }
            var mutation: [String: Any] = [:]
            if !set.isEmpty { mutation["$set"] = set }
            if !unset.isEmpty { mutation["$unset"] = unset }
            let response = try mongoCommand(["update": object.name, "updates": [["q": ["$and": conditions], "u": mutation, "multi": false, "upsert": false]]])
            try checkMongoWrite(response)
            guard numericValue(response["n"]) == 1 else { throw DatabaseFailure(String(localized: "记录已变更或删除，请刷新后重试。")) }
            return
        }
        guard columns.count == original.cells.count, values.count == columns.count else { throw DatabaseFailure(String(localized: "记录字段已变化，请刷新后重试。")) }
        let changed = columns.indices.filter { columns[$0].isEditable && !columns[$0].isPrimaryKey && original.cells[$0] != values[$0] }
        guard !changed.isEmpty else { return }
        guard columns.contains(where: \.isPrimaryKey) else { throw DatabaseFailure(String(localized: "没有主键的表请使用查询编辑器修改。")) }
        var parameters: [CellValue] = []
        func bind(_ value: CellValue) -> String { parameters.append(value); return placeholder(parameters.count) }
        let assignments = changed.map { quoteIdentifier(columns[$0].name) + " = " + bind(values[$0]) }.joined(separator: ", ")
        let identity = columns.indices.filter { columns[$0].isPrimaryKey || changed.contains($0) }
        let condition = identity.map { index in
            let name = quoteIdentifier(columns[index].name)
            if original.cells[index].isNull { return name + " IS NULL" }
            if profile?.kind == .postgresql && !columns[index].isPrimaryKey {
                let originalValue = columns[index].type == "boolean" ? CellValue.text(original.cells[index].display == "t" ? "true" : "false") : original.cells[index]
                return "CAST(\(name) AS text) = " + bind(originalValue)
            }
            return name + " = " + bind(original.cells[index])
        }.joined(separator: " AND ")
        try mutateOne("UPDATE \(object.qualifiedName) SET \(assignments) WHERE \(condition)", parameters: parameters)
    }

    func insert(_ object: DatabaseObject, fields: [(String, CellValue)], document: String?) throws {
        if profile?.kind == .mongodb {
            let response = try mongoCommand(["insert": object.name, "documents": [try jsonObject(document ?? "{}")]])
            try checkMongoWrite(response)
        } else {
            let query: String
            if fields.isEmpty { query = "INSERT INTO \(object.qualifiedName) DEFAULT VALUES" }
            else { query = "INSERT INTO \(object.qualifiedName) (\(fields.map { quoteIdentifier($0.0) }.joined(separator: ", "))) VALUES (\(fields.indices.map { placeholder($0 + 1) }.joined(separator: ", ")))" }
            _ = try sql(query, parameters: fields.map(\.1))
        }
    }

    func delete(_ object: DatabaseObject, columns: [ColumnInfo], row: DataRow) throws {
        if profile?.kind == .mongodb {
            guard let document = row.document, let id = try jsonObject(document)["_id"] else { throw DatabaseFailure(String(localized: "文档没有 _id。")) }
            let response = try mongoCommand(["delete": object.name, "deletes": [["q": ["_id": ["$eq": id]], "limit": 1]]])
            try checkMongoWrite(response)
            guard numericValue(response["n"]) == 1 else { throw DatabaseFailure(String(localized: "记录已被删除，请刷新。")) }
        } else {
            let keys = columns.indices.filter { columns[$0].isPrimaryKey }
            guard !keys.isEmpty else { throw DatabaseFailure(String(localized: "无主键的表不能直接删除记录。")) }
            guard row.cells.count == columns.count else { throw DatabaseFailure(String(localized: "记录字段已变化，请刷新后重试。")) }
            var parameters: [CellValue] = []
            let condition = keys.map { index -> String in
                let name = quoteIdentifier(columns[index].name)
                if row.cells[index].isNull { return name + " IS NULL" }
                parameters.append(row.cells[index])
                return name + " = " + placeholder(parameters.count)
            }.joined(separator: " AND ")
            try mutateOne("DELETE FROM \(object.qualifiedName) WHERE \(condition)", parameters: parameters)
        }
    }

    private func mutateOne(_ query: String, parameters: [CellValue]) throws {
        // SAVEPOINT nests correctly inside a transaction opened by the user's query.
        let ownsTransaction = postgres.map { PQtransactionStatus($0) == PQTRANS_IDLE } ?? false
        if ownsTransaction { _ = try sql("BEGIN") }
        _ = try sql("SAVEPOINT tableviewer_edit")
        do {
            let result = try sql(query, parameters: parameters)
            guard result.affectedRows == 1 else { throw DatabaseFailure(String(localized: "记录已变更、删除或不唯一；本次修改已撤销，请刷新。")) }
            _ = try sql("RELEASE SAVEPOINT tableviewer_edit")
            if ownsTransaction { _ = try sql("COMMIT") }
        } catch {
            _ = try? sql("ROLLBACK TO SAVEPOINT tableviewer_edit")
            _ = try? sql("RELEASE SAVEPOINT tableviewer_edit")
            if ownsTransaction { _ = try? sql("ROLLBACK") }
            throw error
        }
    }

    private func placeholder(_ index: Int) -> String { profile?.kind == .postgresql ? "$\(index)" : "?" }
    private func sqliteError() -> DatabaseFailure {
        let message = sqlite.map { String(cString: sqlite3_errmsg($0)) } ?? String(localized: "无法打开 SQLite 数据库。")
        return DatabaseFailure(message == "not an error" || message == "unable to open database file" ? String(localized: "无法访问 SQLite 文件或日志，请检查文件及所在文件夹的授权，并在编辑连接中重新选择。") : message)
    }
    private func postgresError() -> DatabaseFailure { DatabaseFailure(postgres.map { String(cString: PQerrorMessage($0)) } ?? String(localized: "无法连接 PostgreSQL。")) }
    private func nativeError(_ error: UnsafeMutablePointer<CChar>?) -> DatabaseFailure {
        guard let error else { return DatabaseFailure(String(localized: "MongoDB 操作失败。")) }
        defer { free(error) }
        return DatabaseFailure(String(cString: error))
    }

    /// Metadata SELECTs page through the catalog without changing the user-query row cap.
    func catalogSQL(_ query: String, parameters: [CellValue] = []) throws -> QueryResult {
        var output = QueryResult()
        var offset = 0
        while true {
            let page = try sql("\(query) LIMIT 1000 OFFSET \(offset)", parameters: parameters)
            output.columns = page.columns
            output.rows.append(contentsOf: page.rows)
            if page.rows.count < 1000 { return output }
            offset += page.rows.count
        }
    }

    func sql(_ query: String, parameters: [CellValue] = []) throws -> QueryResult {
        guard !query.contains("\0") else { throw DatabaseFailure(String(localized: "SQL 语句不能包含 NUL 字符。")) }
        if let sqlite { return try sqliteQuery(sqlite, query: query, parameters: parameters) }
        if let postgres { return try postgresQuery(postgres, query: query, parameters: parameters) }
        throw DatabaseFailure(String(localized: "SQL 数据库未连接。"))
    }

    private func sqliteQuery(_ database: OpaquePointer, query: String, parameters: [CellValue]) throws -> QueryResult {
        var statement: OpaquePointer?
        var extra = false
        let code = query.withCString { pointer in
            var tail: UnsafePointer<CChar>?
            let rc = sqlite3_prepare_v2(database, pointer, -1, &statement, &tail)
            if let tail {
                var trailing: OpaquePointer?
                let tailCode = sqlite3_prepare_v2(database, tail, -1, &trailing, nil)
                extra = tailCode != SQLITE_OK || trailing != nil
                sqlite3_finalize(trailing)
            }
            return rc
        }
        defer { sqlite3_finalize(statement) }
        guard code == SQLITE_OK else { throw sqliteError() }
        guard !extra else { throw DatabaseFailure(String(localized: "每次运行一条 SQL 语句；请分别运行多条语句。")) }
        guard let statement else { throw DatabaseFailure(String(localized: "请输入 SQL 语句。")) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .null: rc = sqlite3_bind_null(statement, index)
            case .text(let text): rc = text.withCString { sqlite3_bind_text(statement, index, $0, Int32(text.utf8.count), transient) }
            case .blob(let data): rc = data.isEmpty ? sqlite3_bind_zeroblob(statement, index, 0) : data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            }
            guard rc == SQLITE_OK else { throw sqliteError() }
        }
        let deadline = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        deadline.initialize(to: Date().timeIntervalSinceReferenceDate + 15)
        sqlite3_progress_handler(database, 1000, { context in
            guard let context else { return 0 }
            return Date().timeIntervalSinceReferenceDate > context.assumingMemoryBound(to: Double.self).pointee ? 1 : 0
        }, deadline)
        defer { sqlite3_progress_handler(database, 0, nil, nil); deadline.deinitialize(count: 1); deadline.deallocate() }
        let count = sqlite3_column_count(statement)
        var result = QueryResult(columns: (0..<count).map { ColumnInfo(name: String(cString: sqlite3_column_name(statement, $0)), type: sqlite3_column_decltype(statement, $0).map { String(cString: $0) } ?? "") })
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if result.rows.count < 1000 {
                let cells: [CellValue] = (0..<count).map { col in
                    let length = Int(sqlite3_column_bytes(statement, col))
                    switch sqlite3_column_type(statement, col) {
                    case SQLITE_NULL: return .null
                    case SQLITE_BLOB: return .blob(sqlite3_column_blob(statement, col).map { Data(bytes: $0, count: length) } ?? Data())
                    default:
                        guard let bytes = sqlite3_column_text(statement, col) else { return .text("") }
                        return .text(String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self))
                    }
                }
                result.rows.append(DataRow(cells: cells))
            } else {
                result.hasMore = true
                // Read-only queries need only one lookahead row. Writes with RETURNING
                // must still run to SQLITE_DONE so the whole mutation completes.
                if sqlite3_stmt_readonly(statement) == 1 { break }
            }
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE || (step == SQLITE_ROW && result.hasMore && sqlite3_stmt_readonly(statement) == 1) else { throw sqliteError() }
        result.affectedRows = sqlite3_stmt_readonly(statement) == 1 ? 0 : Int(sqlite3_changes(database))
        return result
    }

    private func postgresQuery(_ database: OpaquePointer, query: String, parameters: [CellValue]) throws -> QueryResult {
        guard !parameters.contains(where: { $0.string?.contains("\0") == true }) else { throw DatabaseFailure(String(localized: "PostgreSQL 文本字段不能包含 NUL 字符。")) }
        let allocated = parameters.map { value -> UnsafeMutablePointer<CChar>? in
            switch value { case .null: nil; case .text(let text): strdup(text); case .blob(let data): strdup("\\x" + data.map { String(format: "%02x", $0) }.joined()) }
        }
        defer { allocated.forEach { free($0) } }
        let values = allocated.map { $0.map { UnsafePointer($0) } }
        let deadline = ProcessInfo.processInfo.systemUptime + postgresQueryTimeout
        func waitForSocket(_ events: Int16) throws {
            while true {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else {
                    disconnect()
                    throw DatabaseFailure(String(localized: "PostgreSQL 响应超时，连接已断开。写入可能已完成，请重新连接并核对数据，勿直接重复提交。"))
                }
                var descriptor = pollfd(fd: PQsocket(database), events: events, revents: 0)
                guard descriptor.fd >= 0 else { throw postgresError() }
                let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 200)))
                if ready > 0 { return }
                if ready < 0 && errno != EINTR { throw postgresError() }
            }
        }
        guard PQsetnonblocking(database, 1) == 0 else { throw postgresError() }
        let sent = values.withUnsafeBufferPointer { buffer in
            PQsendQueryParams(database, query, Int32(values.count), nil, buffer.baseAddress, nil, nil, 0)
        }
        guard sent == 1 else { throw postgresError() }
        PQsetSingleRowMode(database)
        while true {
            let flushed = PQflush(database)
            if flushed == 0 { break }
            guard flushed == 1 else { throw postgresError() }
            try waitForSocket(Int16(POLLOUT))
        }
        var output = QueryResult()
        var failure: DatabaseFailure?
        while true {
            while PQisBusy(database) == 1 {
                try waitForSocket(Int16(POLLIN))
                guard PQconsumeInput(database) == 1 else { throw postgresError() }
            }
            guard let result = PQgetResult(database) else { break }
            defer { PQclear(result) }
            let status = PQresultStatus(result)
            guard status == PGRES_TUPLES_OK || status == PGRES_SINGLE_TUPLE || status == PGRES_COMMAND_OK else {
                if status == PGRES_COPY_IN || status == PGRES_COPY_OUT || status == PGRES_COPY_BOTH {
                    disconnect()
                    throw DatabaseFailure(String(localized: "查询编辑器不支持 COPY，连接已断开；未提交事务会回滚。导出数据请使用 CSV 导出。"))
                }
                failure = DatabaseFailure(String(cString: PQresultErrorMessage(result)).isEmpty ? String(localized: "当前命令不支持，请使用单条 SQL。") : String(cString: PQresultErrorMessage(result)))
                continue
            }
            if output.columns.isEmpty {
                output.columns = (0..<PQnfields(result)).map { ColumnInfo(name: String(cString: PQfname(result, $0)), type: "OID \(PQftype(result, $0))") }
            }
            for row in 0..<PQntuples(result) {
                guard output.rows.count < 1000 else { output.hasMore = true; continue }
                output.rows.append(DataRow(cells: (0..<PQnfields(result)).map { col in
                    PQgetisnull(result, row, col) == 1 ? .null : .text(String(cString: PQgetvalue(result, row, col)))
                }))
            }
            let command = String(cString: PQcmdStatus(result))
            if !command.hasPrefix("SELECT") && !command.hasPrefix("FETCH") { output.affectedRows = Int(String(cString: PQcmdTuples(result))) ?? output.affectedRows }
        }
        if let failure { throw failure }
        return output
    }

    func mongoCommand(_ command: [String: Any], name: String? = nil, database: String? = nil, explainedCommandName: String? = nil) throws -> [String: Any] {
        guard let mongo, let profile else { throw DatabaseFailure(String(localized: "MongoDB 未连接。")) }
        // MongoDB requires the command name to be the FIRST BSON element.
        let known = ["ping", "listCollections", "getMore", "find", "update", "insert", "delete", "killCursors"]
        guard let first = name ?? known.first(where: { command[$0] != nil }), command[first] != nil else { throw DatabaseFailure(String(localized: "缺少 MongoDB 命令名称。")) }
        let keys = [first] + command.keys.filter { $0 != first }.sorted()
        let orderedJSON = "{" + (try keys.map { key in
            let value: String
            if first == "explain", key == "explain", let explainedCommandName,
               let nested = command[key] as? [String: Any], nested[explainedCommandName] != nil {
                // The embedded command also requires its name first. jsonText's
                // sortedKeys would otherwise put "filter" before "find".
                let nestedKeys = [explainedCommandName] + nested.keys.filter { $0 != explainedCommandName }.sorted()
                value = "{" + (try nestedKeys.map { try jsonText($0) + ":" + jsonText(nested[$0]!) }).joined(separator: ",") + "}"
            } else {
                value = try jsonText(command[key]!)
            }
            return try jsonText(key) + ":" + value
        }).joined(separator: ",") + "}"
        var error: UnsafeMutablePointer<CChar>?
        guard let result = tv_mongo_command(mongo, database ?? profile.database, orderedJSON, &error) else { throw nativeError(error) }
        defer { free(result) }
        return try jsonObject(String(cString: result))
    }

    private func checkMongoWrite(_ response: [String: Any]) throws {
        if let errors = response["writeErrors"] as? [[String: Any]], let first = errors.first {
            throw DatabaseFailure(first["errmsg"] as? String ?? String(localized: "MongoDB 写入失败。"))
        }
        if let concern = response["writeConcernError"] as? [String: Any] { throw DatabaseFailure(concern["errmsg"] as? String ?? String(localized: "MongoDB 写入确认失败，请刷新检查。")) }
    }

    private func documentsResult(_ response: [String: Any]) throws -> QueryResult {
        let cursor = response["cursor"] as? [String: Any] ?? [:]
        let documents = cursor["firstBatch"] as? [[String: Any]] ?? cursor["nextBatch"] as? [[String: Any]] ?? []
        var names = Set(documents.flatMap(\.keys)).sorted()
        if names.contains("_id") { names.removeAll { $0 == "_id" }; names.insert("_id", at: 0) }
        return try QueryResult(columns: names.map { ColumnInfo(name: $0, type: "BSON", isPrimaryKey: $0 == "_id") }, rows: documents.map { document in
            let cells: [CellValue] = try names.map { name in
                guard let value = document[name], !(value is NSNull) else { return .null }
                if let text = value as? String { return .text(text) }
                if let extended = value as? [String: Any], extended.count == 1, let key = extended.keys.first,
                   ["$oid", "$numberInt", "$numberLong", "$numberDouble", "$numberDecimal"].contains(key), let scalar = extended[key] as? String { return .text(scalar) }
                return .text(try jsonText(value))
            }
            return DataRow(cells: cells, document: try jsonText(document, pretty: true))
        })
    }
}
