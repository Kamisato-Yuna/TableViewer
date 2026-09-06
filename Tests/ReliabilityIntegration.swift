import SwiftUI
import AppKit

@main struct ReliabilityIntegration {
    static func check(_ value: Bool, _ message: String) throws {
        guard value else { throw DatabaseFailure("FAIL: " + message) }
        print("PASS: " + message)
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tableviewer-reliability-\(UUID()).sqlite")
        var handle: OpaquePointer?
        sqlite3_open(file.path, &handle); sqlite3_close(handle)
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = DatabaseEngine()
        let profile = ConnectionProfile(name: "Reliability", kind: .sqlite, path: file.path)
        _ = try await engine.connect(profile, secret: "")
        let start = Date()
        let many = try await engine.run("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n) SELECT x FROM n")
        try check(many.rows.count == 1000 && many.hasMore && Date().timeIntervalSince(start) < 3, "unbounded read returns 1000 rows promptly")
        let comments = try await engine.run("SELECT 1; -- trailing comment\n /* comment */")
        try check(comments.rows.first?.cells.first == .text("1"), "single statement accepts trailing comments")
        do { _ = try await engine.run("SELECT 1; -- comment\n SELECT 2"); throw DatabaseFailure("FAIL: multiple statements accepted") }
        catch { try check(error.localizedDescription.contains("每次运行一条"), "comments cannot hide a second statement") }
        _ = try await engine.run("CREATE TABLE returning_rows(id INTEGER PRIMARY KEY)")
        let write = try await engine.run("WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1500) INSERT INTO returning_rows SELECT x FROM n RETURNING id")
        let count = try await engine.run("SELECT COUNT(*) FROM returning_rows")
        try check(write.rows.count == 1000 && write.hasMore && write.affectedRows == 1500 && count.rows[0].cells[0] == .text("1500"), "RETURNING limit preserves all 1500 writes")
        _ = try await engine.run("CREATE TABLE nullable_keys (a TEXT, b TEXT, PRIMARY KEY(a,b))")
        _ = try await engine.run("INSERT INTO nullable_keys VALUES(NULL, 'one')")
        let object = DatabaseObject(name: "nullable_keys")
        var rows = try await engine.browse(object)
        try await engine.delete(object, columns: rows.columns, row: rows.rows[0])
        rows = try await engine.browse(object)
        try check(rows.rows.isEmpty, "nullable SQLite primary key deletes the selected record")
        _ = try await engine.run("INSERT INTO nullable_keys VALUES(NULL, 'duplicate'),(NULL, 'duplicate')")
        rows = try await engine.browse(object)
        do { try await engine.delete(object, columns: rows.columns, row: rows.rows[0]); throw DatabaseFailure("FAIL: ambiguous deletion accepted") }
        catch { try check(error.localizedDescription.contains("不唯一"), "ambiguous nullable key deletion is rolled back") }
        let after = try await engine.browse(object)
        try check(after.rows.count == 2, "rollback retains both ambiguous records")
        do { try await engine.update(object, columns: rows.columns, original: rows.rows[0], values: [], document: nil); throw DatabaseFailure("FAIL: invalid row accepted") }
        catch { try check(error.localizedDescription.contains("字段已变化"), "stale field count throws instead of crashing") }
        let duplicate = try await engine.run("SELECT 1 AS same, 2 AS same, 3 AS __row_number__")
        let grid = DataGrid(columns: duplicate.columns, rows: duplicate.rows, selectedID: nil)
        let coordinator = DataGrid.Coordinator(grid)
        let table = NSTableView()
        var rendered: [String] = []
        for index in duplicate.columns.indices {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column:\(index)"))
            let cell = coordinator.tableView(table, viewFor: column, row: 0) as? NSTableCellView
            rendered.append(cell?.textField?.stringValue ?? "")
        }
        try check(rendered == ["1", "2", "3"], "AppKit grid preserves duplicate and reserved column names")
        await engine.disconnect()
        let store = WorkspaceStore()
        await store.connect(profile)
        store.query = "SELECT 42"; await store.runQuery()
        try check(store.queryHasRun, "workspace query succeeds before failure test")
        await store.connect(ConnectionProfile(name: "Missing", path: file.path + ".missing"))
        try check(store.active == nil && store.queryResult.rows.isEmpty && !store.queryHasRun && store.queryHistory.isEmpty, "failed connection clears previous query data")
        do { _ = try await store.engine.run("SELECT 1"); throw DatabaseFailure("FAIL: connection survived failure") }
        catch { try check(error.localizedDescription.contains("未连接"), "failed connection releases database handle") }
        await store.connect(profile)
        store.tab = .data
        store.documentDraft = ""
        store.result = QueryResult(columns: [ColumnInfo(name: "id", isPrimaryKey: true), ColumnInfo(name: "name")], rows: [DataRow(cells: [.text("1"), .text("original")])])
        store.selectRow(store.result.rows[0].id)
        store.draft[1] = .text("unsaved")
        try check(store.terminationWarning?.contains("未保存") == true, "quit warns about unsaved record changes")
        store.discard(); store.busy = true
        try check(store.terminationWarning?.contains("仍在进行") == true, "quit warns about in-flight database operations")
        store.busy = false
        try check(store.terminationWarning == nil, "clean idle workspace can quit normally")
        let selected = store.selectedObject!
        _ = try await store.engine.run("DROP TABLE \(selected.qualifiedName)")
        let refreshed = await store.refresh()
        try check(!refreshed && store.result.rows.isEmpty && store.error != nil, "refresh failure is observable without stale data")
        await store.engine.disconnect()
        print("ALL RELIABILITY CHECKS PASSED")
    }
}
