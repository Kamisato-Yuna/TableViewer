import Foundation

/// Real driver tests against disposable data only. No ports means SQLite-only.
/// Optional servers must be the dedicated acceptance040 fixtures, not user connections.
@main struct Workbench040Integration {
    @MainActor static var failures: [String] = []
    @MainActor static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL"): \(label)")
        if !value { failures.append(label) }
    }
    @MainActor static func rejects(_ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); check(false, label) }
        catch { check(true, label) }
    }
    static func scalar(_ engine: DatabaseEngine, _ query: String) async throws -> String {
        try await engine.run(query).rows.first?.cells.first?.display ?? ""
    }
    @MainActor static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("tv040-integration-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        do { try await sqlite(temporary) } catch { check(false, "SQLite unexpected error: \(error.localizedDescription)") }
        let environment = ProcessInfo.processInfo.environment
        if let port = environment["TV040_PG_PORT"], !port.isEmpty {
            do { try await postgres(port: port, temporary: temporary) } catch { check(false, "PostgreSQL unexpected error: \(error.localizedDescription)") }
        } else { print("SKIP: PostgreSQL; set TV040_PG_PORT for the dedicated acceptance040 server") }
        if let port = environment["TV040_MONGO_PORT"], !port.isEmpty {
            do { try await mongo(port: port) } catch { check(false, "MongoDB unexpected error: \(error.localizedDescription)") }
        } else { print("SKIP: MongoDB; set TV040_MONGO_PORT for the dedicated acceptance040 server") }
        guard failures.isEmpty else { throw DatabaseFailure("\(failures.count) workbench integration checks failed") }
        print("ALL REQUESTED WORKBENCH 0.4.0 CHECKS PASSED (SKIP is not engine acceptance)")
    }
    @MainActor static func sqlite(_ temporary: URL) async throws {
        let path = temporary.appendingPathComponent("fixture.sqlite").path
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else { throw DatabaseFailure("Cannot create fixture") }
        sqlite3_close(handle)
        let profile = ConnectionProfile(name: "SQLite synthetic 040", path: path)
        let engine = DatabaseEngine()
        _ = try await engine.connect(profile, secret: "")
        try await sqliteChecks(engine, profile: profile, temporary: temporary)
        await engine.disconnect()
    }
    @MainActor static func sqliteChecks(_ engine: DatabaseEngine, profile: ConnectionProfile, temporary: URL) async throws {
        for statement in [
            "CREATE TABLE parent(a INTEGER, b INTEGER, PRIMARY KEY(a,b))",
            "CREATE TABLE child(id INTEGER PRIMARY KEY, a INTEGER NOT NULL, b INTEGER, value TEXT DEFAULT '', nullable TEXT, computed INTEGER GENERATED ALWAYS AS (a+1) STORED, CHECK(a>0), FOREIGN KEY(a,b) REFERENCES parent(a,b), UNIQUE(a,b))",
            "CREATE INDEX child_value ON child(value)",
            "INSERT INTO parent VALUES(1,2)",
            "INSERT INTO child(id,a,b,value,nullable) VALUES(1,1,2,'',NULL)",
            "CREATE TEMP TABLE local_temp(id INTEGER)"] { _ = try await engine.run(statement) }
        await rejects("SQLite read-only blocks CTE write") { _ = try await engine.run("WITH input(x) AS (VALUES(1)) DELETE FROM child WHERE id IN (SELECT x FROM input)", readOnly: true) }
        await rejects("SQLite read-only blocks temporary table write") { _ = try await engine.run("INSERT INTO local_temp VALUES(1)", readOnly: true) }
        await rejects("SQLite read-only blocks extension loading function") { _ = try await engine.run("SELECT load_extension('missing-fixture-extension')", readOnly: true) }
        check(try await scalar(engine, "SELECT count(*) FROM child") == "1", "SQLite blocked actions leave data unchanged")
        let before = try await scalar(engine, "SELECT total_changes()")
        let estimate = await engine.estimate("UPDATE child SET value='changed'")
        check(!estimate.summary.isEmpty, "SQLite estimate describes known or unknown work")
        let after = try await scalar(engine, "SELECT total_changes()")
        let value = try await scalar(engine, "SELECT value FROM child")
        check(after == before && value == "", "SQLite write estimate does not execute the write")
        _ = try await engine.run("UPDATE child SET value='' WHERE id=1")
        check(try await scalar(engine, "SELECT count(*) FROM child") == "1", "SQLite read-only scope releases authorizer for later allowed work")
        let object = DatabaseObject(name: "child")
        let schema = try await engine.schemaMetadata(for: object)
        check(schema.ddl.contains("CHECK") && schema.ddl.contains("GENERATED") && schema.ddl.contains("child_value"), "SQLite DDL preserves checks/generated expression/index")
        check(schema.fields.first { $0.name == "a" }?.constraints.contains("NOT NULL") == true, "SQLite NOT NULL field constraint")
        check(schema.fields.first { $0.name == "a" }?.constraints.contains("UNIQUE") == false, "SQLite composite uniqueness does not label each column UNIQUE")
        check(schema.relationships.first?.sourceColumns == ["a", "b"] && schema.relationships.first?.targetColumns == ["a", "b"], "SQLite composite foreign key order")
        let filtered = try await engine.browse(object, condition: "id=1 AND value='' AND nullable IS NULL")
        check(filtered.rows.count == 1, "SQLite condition filter preserves empty string and NULL")
        await rejects("SQLite condition cannot append a write") { _ = try await engine.browse(object, condition: "1); DELETE FROM child; --") }
        try await exportSQLite(engine)
        try await multiResult(profile: profile, temporary: temporary, table: "batch_log")
    }
    static func scalarValue(_ result: QueryResult) -> String { result.rows.first?.cells.first?.display ?? "" }
    @MainActor static func exportSQLite(_ engine: DatabaseEngine) async throws {
        _ = try await engine.run("CREATE TABLE export_copy(empty TEXT, nullable TEXT, binary BLOB, text_value TEXT)")
        let result = try await engine.run("SELECT '' AS empty, NULL AS nullable, X'00ff5c' AS binary, 'a''b' || char(10) || '=SUM(1)' AS text_value")
        let text = try ResultExporter(format: .sql, sourceKind: .sqlite, table: DatabaseObject(name: "export_copy")).encode(result)
        for statement in try SQLScript.statements(text, kind: .sqlite) { _ = try await engine.run(statement) }
        let restored = try await engine.run("SELECT * FROM export_copy")
        check(restored.rows.first?.cells == result.rows.first?.cells, "SQLite INSERT export round-trips NULL/empty/blob/quotes/newline")
        try checkTabularExports(result, kind: .sqlite)
    }
    @MainActor static func checkTabularExports(_ result: QueryResult, kind: DatabaseKind) throws {
        let json = try ResultExporter(format: .json, sourceKind: kind).encode(result)
        let data = try jsonObject(json)
        let rows = data["rows"] as? [[Any]]
        check(rows?.first?[0] as? String == "" && rows?.first?[1] is NSNull, "\(kind.rawValue) JSON separates empty string and NULL")
        check((rows?.first?[2] as? [String: Any])?["base64"] as? String == "AP9c", "\(kind.rawValue) JSON exports actual binary bytes")
        let yaml = try ResultExporter(format: .yaml, sourceKind: kind).encode(result)
        check((try? JSONSerialization.jsonObject(with: Data(yaml.utf8))) != nil, "\(kind.rawValue) YAML uses valid JSON subset")
        let xml = try ResultExporter(format: .xml, sourceKind: kind).encode(result)
        check(xml.contains("null=\"true\"") && xml.contains("AP9c") && xml.contains("&apos;"), "\(kind.rawValue) XML retains NULL/binary/escaped quote")
        let csv = try ResultExporter(format: .csv, sourceKind: kind).encode(result)
        let txt = try ResultExporter(format: .txt, sourceKind: kind).encode(result)
        check(csv.contains("\\N") && csv.contains("\"\"") && txt.contains("\t"), "\(kind.rawValue) delimited export distinguishes NULL and empty")
    }
    @MainActor static func multiResult(profile: ConnectionProfile, temporary: URL, table: String) async throws {
        let store = WorkspaceStore(agentLibrary: AgentLibrary(file: temporary.appendingPathComponent(UUID().uuidString + ".json")), readCredential: { _ in "" }, scripts: ScriptLibrary(directory: temporary.appendingPathComponent(UUID().uuidString)))
        _ = try await store.engine.connect(profile, secret: "")
        store.active = profile
        _ = try await store.engine.run("CREATE TABLE \(table)(id INTEGER)")
        store.query = "INSERT INTO \(table) VALUES(1); SELECT id FROM \(table); SELECT missing_column FROM \(table); INSERT INTO \(table) VALUES(2);"
        await store.runQuery()
        if store.pendingQuery != nil { await store.runQuery(approved: true) }
        check(store.statementResults.count == 3 && store.statementResults[1].result?.rows.first?.cells.first?.display == "1" && store.statementResults[2].failure != nil, "\(profile.kind.rawValue) ordered multi-results retain success and first failure")
        check(try await scalar(store.engine, "SELECT count(*) FROM \(table)") == "1", "\(profile.kind.rawValue) stops subsequent statement; prior autocommit remains")
        _ = try await store.engine.run("DELETE FROM \(table)")
        store.query = "BEGIN; INSERT INTO \(table) VALUES(5); SELECT missing_column FROM \(table); COMMIT;"
        await store.runQuery(approved: true)
        _ = try await store.engine.run("ROLLBACK")
        check(try await scalar(store.engine, "SELECT count(*) FROM \(table)") == "0", "\(profile.kind.rawValue) explicit transaction remains user-owned after failure")
        await store.engine.disconnect()
    }
    @MainActor static func postgres(port: String, temporary: URL) async throws {
        guard Int(port).map({ (1...65535).contains($0) }) == true else { throw DatabaseFailure("Invalid TV040_PG_PORT") }
        let profile = ConnectionProfile(name: "Dedicated PostgreSQL 040", kind: .postgresql, host: "127.0.0.1", port: port, database: "acceptance040", user: "postgres", sslMode: "disable")
        let engine = DatabaseEngine()
        _ = try await engine.connect(profile, secret: "")
        let schema = "tv040_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        _ = try await engine.run("CREATE SCHEMA \(schema)")
        do { try await postgresChecks(engine, profile: profile, schema: schema, temporary: temporary) }
        catch { _ = try? await engine.run("ROLLBACK"); _ = try? await engine.run("DROP SCHEMA \(schema) CASCADE"); await engine.disconnect(); throw error }
        _ = try await engine.run("DROP SCHEMA \(schema) CASCADE")
        await engine.disconnect()
    }
    @MainActor static func postgresChecks(_ engine: DatabaseEngine, profile: ConnectionProfile, schema: String, temporary: URL) async throws {
        for query in [
            "CREATE TABLE \(schema).parent(a INTEGER,b INTEGER,PRIMARY KEY(a,b))",
            "CREATE TABLE \(schema).child(id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,a INTEGER NOT NULL,b INTEGER,label TEXT DEFAULT '', computed INTEGER GENERATED ALWAYS AS(a+1) STORED,CHECK(a>0),UNIQUE(a,b),FOREIGN KEY(a,b) REFERENCES \(schema).parent(a,b))",
            "CREATE INDEX child_label ON \(schema).child(label)",
            "INSERT INTO \(schema).parent VALUES(1,2)",
            "INSERT INTO \(schema).child(a,b) VALUES(1,2)",
            "CREATE FUNCTION \(schema).write_row() RETURNS integer LANGUAGE plpgsql VOLATILE AS $$ BEGIN UPDATE \(schema).child SET label='modified'; RETURN 1; END $$",
            "CREATE TEMP TABLE tv040_temp(id INTEGER)",
            "CREATE FUNCTION \(schema).write_temp() RETURNS integer LANGUAGE plpgsql VOLATILE AS $$ BEGIN INSERT INTO pg_temp.tv040_temp VALUES(1); RETURN 1; END $$",
            "CREATE TEMP SEQUENCE tv040_temp_seq START 1"] { _ = try await engine.run(query) }
        await rejects("PostgreSQL read-only blocks writing CTE") { _ = try await engine.run("WITH changed AS (DELETE FROM \(schema).child RETURNING *) SELECT * FROM changed", readOnly: true) }
        await rejects("PostgreSQL read-only blocks SELECT calling write function") { _ = try await engine.run("SELECT \(schema).write_row()", readOnly: true) }
        _ = try? await engine.run("SELECT \(schema).write_temp()", readOnly: true)
        check(try await scalar(engine, "SELECT count(*) FROM pg_temp.tv040_temp") == "0", "PostgreSQL temporary-table exception cannot retain writes")
        let sequenceBefore = try await scalar(engine, "SELECT is_called::text FROM pg_temp.tv040_temp_seq")
        _ = try? await engine.run("SELECT nextval('pg_temp.tv040_temp_seq')", readOnly: true)
        check(try await scalar(engine, "SELECT is_called::text FROM pg_temp.tv040_temp_seq") == sequenceBefore, "PostgreSQL read-only blocks nontransactional temporary sequence mutation")
        check(try await scalar(engine, "SELECT label FROM \(schema).child") == "", "PostgreSQL blocked function leaves persistent data unchanged")
        let estimate = await engine.estimate("UPDATE \(schema).child SET label='estimate must not run'")
        let afterEstimate = try await scalar(engine, "SELECT label FROM \(schema).child")
        check(!estimate.summary.isEmpty && afterEstimate == "", "PostgreSQL write estimate never executes write")
        let metadata = try await engine.schemaMetadata(for: DatabaseObject(name: "child", schema: schema))
        check(metadata.ddl.contains("IDENTITY") && metadata.ddl.contains("GENERATED") && metadata.ddl.contains("CHECK") && metadata.indexes.contains { $0.name == "child_label" }, "PostgreSQL DDL contains identity/generated/check/index metadata")
        check(metadata.relationships.first?.sourceColumns == ["a", "b"] && metadata.relationships.first?.targetColumns == ["a", "b"], "PostgreSQL composite foreign key column order")
        check(try await engine.browse(DatabaseObject(name: "child", schema: schema), condition: "a=1 AND label=''").rows.count == 1, "PostgreSQL condition mode uses WHERE predicate")
        await rejects("PostgreSQL condition rejects appended write") { _ = try await engine.browse(DatabaseObject(name: "child", schema: schema), condition: "1=1); DELETE FROM \(schema).child; --") }
        _ = try await engine.run("CREATE TABLE \(schema).export_source(empty TEXT,nullable TEXT,binary BYTEA,text_value TEXT,n NUMERIC(30,8),b BOOLEAN,u UUID,j JSONB,a INTEGER[],t TIMESTAMP)")
        _ = try await engine.run("INSERT INTO \(schema).export_source VALUES('',NULL,decode('00ff5c','hex'),E'a''b\\n=SUM(1)',1234567890123456789012.12345678,true,'00000000-0000-0000-0000-000000000001','{\"s\":\"x\"}',ARRAY[1,2],TIMESTAMP '2026-09-08 12:34:56')")
        _ = try await engine.run("CREATE TABLE \(schema).export_copy (LIKE \(schema).export_source INCLUDING ALL)")
        let exported = try await engine.run("SELECT * FROM \(schema).export_source")
        let insert = try ResultExporter(format: .sql, sourceKind: .postgresql, sqlDialect: .postgresql, table: DatabaseObject(name: "export_copy", schema: schema)).encode(exported)
        for query in try SQLScript.statements(insert, kind: .postgresql) { _ = try await engine.run(query) }
        check(try await scalar(engine, "SELECT count(*) FROM ((SELECT * FROM \(schema).export_source EXCEPT SELECT * FROM \(schema).export_copy) UNION ALL (SELECT * FROM \(schema).export_copy EXCEPT SELECT * FROM \(schema).export_source)) AS differences") == "0", "PostgreSQL INSERT round-trip retains numeric/bool/uuid/jsonb/array/timestamp/bytea/NULL/empty")
        try checkTabularExports(exported, kind: .postgresql)
        try await multiResult(profile: profile, temporary: temporary, table: schema + ".batch_log")
    }
    @MainActor static func mongo(port: String) async throws {
        guard Int(port).map({ (1...65535).contains($0) }) == true else { throw DatabaseFailure("Invalid TV040_MONGO_PORT") }
        let profile = ConnectionProfile(name: "Dedicated MongoDB 040", kind: .mongodb, host: "127.0.0.1", port: port, database: "acceptance040")
        let engine = DatabaseEngine()
        _ = try await engine.connect(profile, secret: "mongodb://127.0.0.1:\(port)/acceptance040")
        let name = "tv040_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        do { try await mongoChecks(engine, name: name) }
        catch { _ = try? await engine.run("{\"drop\":\"\(name)\"}"); await engine.disconnect(); throw error }
        _ = try await engine.run("{\"drop\":\"\(name)\"}")
        await engine.disconnect()
    }
    @MainActor static func mongoChecks(_ engine: DatabaseEngine, name: String) async throws {
        _ = try await engine.run("{\"create\":\"\(name)\",\"validator\":{\"$jsonSchema\":{\"bsonType\":\"object\",\"required\":[\"label\"],\"properties\":{\"label\":{\"bsonType\":\"string\"}}}}}")
        _ = try await engine.run("{\"insert\":\"\(name)\",\"documents\":[{\"label\":\"\",\"nullable\":null,\"exact\":{\"$numberDecimal\":\"1234567890123456789012.12345678\"},\"nested\":{\"items\":[1,2]}},{\"label\":\"second\"}]}")
        _ = try await engine.run("{\"createIndexes\":\"\(name)\",\"indexes\":[{\"key\":{\"label\":1},\"name\":\"label_unique\",\"unique\":true}]}")
        await rejects("MongoDB mixed command cannot hide delete behind find field") { _ = try await engine.run("{\"delete\":\"\(name)\",\"find\":\"\(name)\",\"deletes\":[{\"q\":{},\"limit\":0}]}", readOnly: true) }
        await rejects("MongoDB read-only blocks aggregate output") { _ = try await engine.run("{\"aggregate\":\"\(name)\",\"pipeline\":[{\"$out\":\"\(name)\"}],\"cursor\":{}}", readOnly: true) }
        let estimate = await engine.estimate("{\"delete\":\"\(name)\",\"deletes\":[{\"q\":{},\"limit\":0}]}")
        check(!estimate.summary.isEmpty, "MongoDB unavailable estimate is explicit")
        let all = try await engine.run("{\"find\":\"\(name)\",\"filter\":{}}", readOnly: true)
        check(all.rows.count == 2, "MongoDB blocked writes and estimate leave documents intact")
        let result = try await engine.browse(DatabaseObject(name: name), condition: "{\"label\":\"\"}")
        check(result.rows.count == 1, "MongoDB condition filters without interpreting SQL")
        let metadata = try await engine.schemaMetadata(for: DatabaseObject(name: name))
        check(metadata.fields.first { $0.name == "label" }?.constraints.contains("REQUIRED") == true && metadata.indexes.contains { $0.name == "label_unique" && $0.unique }, "MongoDB metadata retains declared required field and unique index")
        check(try await engine.relationships(for: [DatabaseObject(name: name)]).isEmpty, "MongoDB does not invent relational foreign keys")
        for format in [ResultExportFormat.json, .yaml] {
            let output = try ResultExporter(format: format, sourceKind: .mongodb).encode(result)
            check(output.contains("1234567890123456789012.12345678") && output.contains("$numberDecimal") && output.contains("nested"), "MongoDB \(format.rawValue) preserves Extended JSON decimal and nested document")
            check((try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])?.count == 1, "MongoDB \(format.rawValue) exports a valid document array")
        }
        await rejects("MongoDB SQL export refuses lossy relational conversion") { _ = try ResultExporter(format: .sql, sourceKind: .mongodb, table: DatabaseObject(name: name)).encode(result) }
    }
}
