import Foundation

@main struct DatabaseIntegration {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw DatabaseFailure("FAIL: " + message) }
        print("PASS: " + message)
    }
    static func main() async throws {
        setbuf(stdout, nil)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("tableviewer-tests-" + UUID().uuidString + ".sqlite")
        var db: OpaquePointer?
        sqlite3_open(temporary.path, &db); sqlite3_close(db)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let engine = DatabaseEngine()
        let profile = ConnectionProfile(name: "Integration", kind: .sqlite, path: temporary.path)
        _ = try await engine.connect(profile, secret: "")
        try await relational(engine, kind: .sqlite)
        await engine.disconnect()
        if let port = ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_PG_PORT"] {
            let postgres = ConnectionProfile(name: "Integration", kind: .postgresql, host: "127.0.0.1", port: port, database: "tableviewer_test", user: "postgres", sslMode: "disable")
            _ = try await engine.connect(postgres, secret: ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_PG_PASSWORD"] ?? "")
            try await relational(engine, kind: .postgresql)
            await engine.disconnect()
            let timed = DatabaseEngine(postgresQueryTimeout: 1)
            _ = try await timed.connect(postgres, secret: ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_PG_PASSWORD"] ?? "")
            _ = try await timed.run("SET statement_timeout = 0")
            let started = Date()
            do { _ = try await timed.run("SELECT pg_sleep(30)"); throw DatabaseFailure("Expected client timeout") }
            catch { try require(error.localizedDescription.contains("响应超时") && Date().timeIntervalSince(started) < 4, "PostgreSQL client timeout survives disabled server timeout") }
            _ = try await timed.connect(postgres, secret: ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_PG_PASSWORD"] ?? "")
            let recovered = try await timed.run("SELECT 1")
            try require(recovered.rows.first?.cells.first == .text("1"), "PostgreSQL reconnects after client timeout")
            do { _ = try await timed.run("COPY (SELECT 1) TO STDOUT"); throw DatabaseFailure("Expected unsupported COPY") }
            catch { try require(error.localizedDescription.contains("不支持 COPY"), "PostgreSQL unsupported COPY terminates without hanging") }
            await timed.disconnect()
        }
        if let port = ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_MONGO_PORT"] {
            let mongo = ConnectionProfile(name: "Integration", kind: .mongodb, host: "127.0.0.1", port: port, database: "tableviewer_test")
            let password = ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_MONGO_PASSWORD"]
            let uri = password.map { "mongodb://tableviewer:\($0)@127.0.0.1:\(port)/?authSource=admin" } ?? "mongodb://127.0.0.1:\(port)"
            _ = try await engine.connect(mongo, secret: uri)
            try await documents(engine)
            await engine.disconnect()
        }
        print("ALL REQUESTED DATABASE TESTS PASSED")
    }

    static func relational(_ engine: DatabaseEngine, kind: DatabaseKind) async throws {
        let object = DatabaseObject(name: "test records", schema: kind == .postgresql ? "public" : "")
        _ = try await engine.run("CREATE TABLE \(object.qualifiedName) (tenant INTEGER NOT NULL, id INTEGER NOT NULL, title TEXT, note TEXT, PRIMARY KEY(tenant,id))")
        let objects = try await engine.objects()
        try require(objects.contains(where: { $0.name == object.name }), "\(kind.rawValue) catalog")
        try await engine.insert(object, fields: [("tenant", .text("1")), ("id", .text("1")), ("title", .text("O'Reilly'); DROP TABLE x; --")), ("note", .null)], document: nil)
        try await engine.insert(object, fields: [("tenant", .text("2")), ("id", .text("1")), ("title", .text("other tenant")), ("note", .text(""))], document: nil)
        var data = try await engine.browse(object)
        try require(data.rows.count == 2 && data.columns.filter(\.isPrimaryKey).count == 2, "\(kind.rawValue) compound primary key")
        try require(data.rows[0].cells[2] == .text("O'Reilly'); DROP TABLE x; --") && data.rows[0].cells[3] == .null && data.rows[1].cells[3] == .text(""), "\(kind.rawValue) parameter binding / NULL vs empty")
        let original = data.rows[0]
        var values = original.cells; values[2] = .text("更新 · ✓"); values[3] = .text("was null")
        try await engine.update(object, columns: data.columns, original: original, values: values, document: nil)
        data = try await engine.browse(object)
        try require(data.rows[0].cells[2] == .text("更新 · ✓") && data.rows[1].cells[2] == .text("other tenant"), "\(kind.rawValue) update exactly one record")
        do {
            try await engine.update(object, columns: data.columns, original: original, values: values, document: nil)
            throw DatabaseFailure("Expected stale row rejection")
        } catch { try require(error.localizedDescription.contains("记录已变更"), "\(kind.rawValue) stale edit rollback") }
        _ = try await engine.run("BEGIN")
        var next = data.rows[0].cells; next[2] = .text("uncommitted")
        try await engine.update(object, columns: data.columns, original: data.rows[0], values: next, document: nil)
        _ = try await engine.run("ROLLBACK")
        data = try await engine.browse(object)
        try require(data.rows[0].cells[2] == .text("更新 · ✓"), "\(kind.rawValue) respects explicit transaction rollback")
        try await engine.delete(object, columns: data.columns, row: data.rows[0])
        data = try await engine.browse(object)
        try require(data.rows.count == 1 && data.rows[0].cells[0] == .text("2"), "\(kind.rawValue) delete uses complete primary key")
        do { _ = try await engine.run("SELECT 1; SELECT 2"); throw DatabaseFailure("Expected multiple statement rejection") }
        catch { try require(error.localizedDescription.contains("每次运行一条") || error.localizedDescription.contains("multiple commands"), "\(kind.rawValue) single-statement query validation") }
        let many = try await engine.run(kind == .sqlite ? "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1005) SELECT x FROM n" : "SELECT generate_series(1,1005)")
        try require(many.rows.count == 1000 && many.hasMore, "\(kind.rawValue) bounded query display")
        _ = try await engine.run("CREATE TABLE pages (id INTEGER PRIMARY KEY)")
        _ = try await engine.run(kind == .sqlite ? "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<205) INSERT INTO pages SELECT x FROM n" : "INSERT INTO pages SELECT generate_series(1,205)")
        let pages = DatabaseObject(name: "pages", schema: kind == .postgresql ? "public" : "")
        let first = try await engine.browse(pages), second = try await engine.browse(pages, page: 1)
        try require(first.rows.count == 200 && first.hasMore && second.rows.count == 5 && !second.hasMore, "\(kind.rawValue) pagination")
        if kind == .sqlite {
            _ = try await engine.run("CREATE TABLE binary_data (id INTEGER PRIMARY KEY, payload BLOB, text_value TEXT)")
            let binary = DatabaseObject(name: "binary_data")
            try await engine.insert(binary, fields: [("id", .text("1")), ("payload", .blob(Data([0, 1, 255]))), ("text_value", .text("a\0b"))], document: nil)
            let value = try await engine.browse(binary)
            try require(value.rows[0].cells[1] == .blob(Data([0,1,255])) && value.rows[0].cells[2] == .text("a\0b"), "SQLite BLOB and embedded NUL round-trip")
            try await engine.insert(binary, fields: [("id", .text("2")), ("payload", .blob(Data()))], document: nil)
            let empty = try await engine.browse(binary)
            try require(empty.rows[1].cells[1] == .blob(Data()), "SQLite empty BLOB is not NULL")
        } else {
            _ = try await engine.run("CREATE TABLE rich_types (id INTEGER PRIMARY KEY, metadata JSON, enabled BOOLEAN)")
            _ = try await engine.run("INSERT INTO rich_types VALUES (1, '{\"old\":true}', true)")
            let rich = DatabaseObject(name: "rich_types", schema: "public")
            let before = try await engine.browse(rich)
            var values = before.rows[0].cells; values[1] = .text("{\"new\":true}"); values[2] = .text("false")
            try await engine.update(rich, columns: before.columns, original: before.rows[0], values: values, document: nil)
            let after = try await engine.browse(rich)
            try require(after.rows[0].cells[1] == .text("{\"new\":true}") && after.rows[0].cells[2] == .text("f"), "PostgreSQL JSON and boolean edits")
            do { try await engine.insert(object, fields: [("tenant", .text("9")), ("id", .text("9")), ("title", .text("a\0b"))], document: nil); throw DatabaseFailure("Expected NUL validation") }
            catch { try require(error.localizedDescription.contains("NUL"), "PostgreSQL rejects text truncation") }
        }
    }

    static func documents(_ engine: DatabaseEngine) async throws {
        let object = DatabaseObject(name: "documents")
        let source = """
        {"_id":{"$oid":"507f1f77bcf86cd799439011"},"name":"原始文档","large":{"$numberLong":"9223372036854775806"},"price":{"$numberDecimal":"123.450"},"date":{"$date":{"$numberLong":"1700000000000"}},"nullable":null,"nested":{"tags":["a","b"]}}
        """
        try await engine.insert(object, fields: [], document: source)
        let objects = try await engine.objects()
        try require(objects.contains(where: { $0.name == object.name }), "MongoDB list collections")
        var result = try await engine.browse(object)
        try require(result.rows.count == 1 && result.columns.first?.name == "_id", "MongoDB find documents")
        let original = result.rows[0]
        var updated = try jsonObject(original.document!)
        updated["name"] = "编辑后的文档"
        try await engine.update(object, columns: result.columns, original: original, values: [], document: jsonText(updated))
        result = try await engine.browse(object)
        let actual = try jsonObject(result.rows[0].document!)
        try require(actual["name"] as? String == "编辑后的文档" && (actual["large"] as? [String:String])?["$numberLong"] == "9223372036854775806" && (actual["price"] as? [String:String])?["$numberDecimal"] == "123.450" && actual["date"] != nil, "MongoDB edits preserve BSON int64 / decimal / date")
        do { try await engine.update(object, columns: result.columns, original: original, values: [], document: jsonText(updated)); throw DatabaseFailure("Expected conflict") }
        catch { try require(error.localizedDescription.contains("记录已变更"), "MongoDB stale document rejection") }
        updated["_id"] = ["$oid": "507f1f77bcf86cd799439099"]
        do { try await engine.update(object, columns: result.columns, original: result.rows[0], values: [], document: jsonText(updated)); throw DatabaseFailure("Expected immutable ID") }
        catch { try require(error.localizedDescription.contains("_id"), "MongoDB immutable _id") }
        _ = try await engine.run("{\"update\":\"documents\",\"updates\":[{\"q\":{},\"u\":{\"$set\":{\"concurrent\":\"preserve me\"}}}]}")
        var local = actual; local["name"] = "local edit"; local.removeValue(forKey: "nullable")
        try await engine.update(object, columns: result.columns, original: result.rows[0], values: [], document: jsonText(local))
        result = try await engine.browse(object)
        let merged = try jsonObject(result.rows[0].document!)
        try require(merged["concurrent"] as? String == "preserve me" && merged["nullable"] == nil, "MongoDB preserves concurrent additions and unsets removed fields")
        try await engine.delete(object, columns: result.columns, row: result.rows[0])
        result = try await engine.browse(object)
        try require(result.rows.isEmpty, "MongoDB delete one document")
        let reply = try await engine.run("{\"ping\":1}")
        try require(reply.rows.count == 1, "MongoDB command editor")
    }
}
