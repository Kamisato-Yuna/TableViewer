import Foundation

@main struct SchemaIntegration {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw DatabaseFailure("FAIL: " + message) }
        print("PASS: " + message)
    }
    static func main() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("schema-\(UUID()).sqlite")
        var db: OpaquePointer?
        sqlite3_open(url.path, &db); sqlite3_close(db)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = DatabaseEngine()
        _ = try await engine.connect(ConnectionProfile(name: "Schema test", path: url.path), secret: "")
        _ = try await engine.run("CREATE TABLE parent(a INTEGER, b INTEGER, PRIMARY KEY(a,b))")
        _ = try await engine.run("CREATE TABLE \"child's data\" (id INTEGER PRIMARY KEY, a INTEGER NOT NULL, b INTEGER, email TEXT UNIQUE, note TEXT DEFAULT '', CHECK(a>0), FOREIGN KEY(a,b) REFERENCES parent(a,b), UNIQUE(a,b))")
        _ = try await engine.run("CREATE INDEX child_note ON \"child's data\"(note) WHERE note <> ''")
        let object = DatabaseObject(name: "child's data")
        let metadata = try await engine.schemaMetadata(for: object)
        try require(metadata.fields.count == 5, "all declared fields")
        try require(metadata.fields.first { $0.name == "a" }?.constraints.contains("NOT NULL") == true, "NOT NULL catalog flag")
        try require(metadata.fields.first { $0.name == "a" }?.constraints.contains("UNIQUE") == false, "composite uniqueness is not single-field uniqueness")
        try require(metadata.fields.first { $0.name == "email" }?.constraints.contains("UNIQUE") == true, "single-field unique constraint")
        try require(metadata.fields.first { $0.name == "note" }?.defaultValue == "''", "empty default stays empty SQL literal")
        try require(metadata.relationships.first?.sourceColumns == ["a", "b"] && metadata.relationships.first?.targetColumns == ["a", "b"], "composite FK order")
        try require(metadata.ddl.contains("CHECK(a>0)") && metadata.ddl.contains("WHERE note <> ''"), "DDL preserves CHECK and partial index")
        _ = try await engine.run("CREATE VIEW child_view AS SELECT email FROM \"child's data\"")
        let view = try await engine.schemaMetadata(for: DatabaseObject(name: "child_view", isView: true))
        try require(view.ddl.contains("CREATE VIEW"), "view original DDL")
        _ = try await engine.run("CREATE TABLE implicit_child(a INTEGER,b INTEGER, FOREIGN KEY(a,b) REFERENCES parent)")
        let implicit = try await engine.schemaMetadata(for: DatabaseObject(name: "implicit_child"))
        try require(implicit.relationships.first?.targetColumns == ["a", "b"], "implicit FK resolves actual primary key fields")
        let relationships = try await engine.relationships(for: engine.objects())
        try require(relationships.count == 2, "catalog relationship enumeration")
        await engine.disconnect()
        print("SQLite schema integration passed; PostgreSQL/MongoDB not run by this test.")
    }
}
