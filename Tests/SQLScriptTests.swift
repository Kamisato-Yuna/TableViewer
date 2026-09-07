import Foundation
@main struct SQLScriptTests {
    @MainActor static func main() async throws {
        func check(_ value: Bool, _ name: String) { precondition(value, name); print("PASS \(name)") }
        let pg = "SELECT ';'; /* nested /* ; */ ok */ SELECT $$a;b$$; SELECT E'x\\\';y'; SELECT $tag$one;two$tag$; -- end;"
        check(try SQLScript.statements(pg, kind: .postgresql).count == 4, "PostgreSQL strings, dollar quotes, nested comments")
        let trigger = "CREATE TRIGGER example AFTER INSERT ON a BEGIN UPDATE a SET b=';'; INSERT INTO a VALUES(1); END; SELECT 2;"
        check(try SQLScript.statements(trigger, kind: .sqlite).count == 2, "SQLite trigger stays one statement")
        check(try SQLScript.statements("-- only comment;", kind: .sqlite).isEmpty, "comment-only script")
        do { _ = try SQLScript.statements("SELECT $tag$unfinished;", kind: .postgresql); preconditionFailure("must reject unterminated quote") } catch {}
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ScriptLibrary(directory: directory)
        let connection = UUID()
        let id = try library.create(name: "A / B", connectionID: connection, text: "SELECT '🦊';")
        try library.rename(id, name: "重命名")
        let reloaded = ScriptLibrary(directory: directory)
        check(try reloaded.open(id) == "SELECT '🦊';", "script text survives rename and reload")
        check(reloaded.scripts.first?.name == "重命名", "display name independent of path")
        try reloaded.close(id)
        check(reloaded.unused(days: 90, now: Date().addingTimeInterval(91*86400)).count == 1, "unused closed scripts eligible")
        try reloaded.delete([id]); check(ScriptLibrary(directory: directory).scripts.isEmpty, "cleanup persists")
    }
}
