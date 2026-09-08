import Foundation
import Darwin

@main struct Workbench053Extensions {
    @MainActor static func check(_ ok: Bool, _ name: String) { print("\(ok ? "PASS" : "FAIL"): \(name)"); if !ok { exit(1) } }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--databases-only") { try await databases(); return }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await crossConnectionHistory(root.appendingPathComponent("cross-history"))
        if CommandLine.arguments.contains("--history-only") { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "queryEstimatesEnabled")
        defaults.removeObject(forKey: "slowQuerySuggestionShown")
        defaults.set(true, forKey: "showAutomaticEstimates")
        let scripts = ScriptLibrary(directory: root.appendingPathComponent("scripts"))
        let store = WorkspaceStore(agentLibrary: AgentLibrary(file: root.appendingPathComponent("agent.json")), readCredential: { _ in "" }, scripts: scripts)
        check(!store.estimatesEnabled, "legacy visible bar does not enable optional estimates")
        store.setEstimatesEnabled(true)
        let restored = WorkspaceStore(agentLibrary: AgentLibrary(file: root.appendingPathComponent("agent2.json")), scripts: scripts)
        check(restored.estimatesEnabled, "explicit estimate preference survives recreation")
        store.setEstimatesEnabled(false)
        let db = root.appendingPathComponent("qa.sqlite")
        var handle: OpaquePointer?
        sqlite3_open(db.path, &handle); sqlite3_close(handle)
        let profile = ConnectionProfile(name: "Synthetic 053", path: db.path)
        store.profiles = [profile]
        await store.connect(profile)
        _ = try await store.engine.run("CREATE TABLE records(id INTEGER PRIMARY KEY, label TEXT)")
        _ = try await store.engine.run("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<53) INSERT INTO records SELECT x, '示例' FROM n")
        await store.chooseObject(DatabaseObject(name: "records"))
        for size in [1, 7, 20, 53, 100] {
            await store.updatePageSize(size)
            var values: [String] = []
            repeat {
                values += store.result.rows.map { $0.cells[0].display }
                if !store.result.hasMore { break }
                await store.changePage(1)
            } while true
            check(values.count == 53 && Set(values).count == 53 && values.first == "1" && values.last == "53", "page size \(size) no skipped/duplicate rows")
        }
        await store.updatePageSize(7)
        check(store.page == 0 && store.result.rows.count == 7, "page size change resets page and refreshes")
        let a = try scripts.create(name: "Same name", connectionID: profile.id, text: "SELECT 11; SELECT 12;")
        let b = try scripts.create(name: "Same name", connectionID: profile.id, text: "SELECT 22;")
        store.openScript(a); await store.runQuery()
        check(store.statementResults.count == 2 && store.queryResult.rows.first?.cells.first?.display == "11", "default query runs without optional planning")
        store.selectedResultIndex = 1; store.queryResult = store.statementResults[1].result!
        store.openScript(b); await store.runQuery(); store.openScript(a)
        check(store.selectedResultIndex == 1 && store.queryResult.rows.first?.cells.first?.display == "12", "script restores selected result without rerun")
        store.query = "SELECT missing_column;"
        await store.runQuery(); store.openScript(b); store.openScript(a)
        check(store.queryFailure != nil && store.statementResults.count == 1, "error belongs to script")
        store.query = "DELETE FROM records;"; await store.runQuery()
        check(store.showQueryApproval, "optional estimates off retains modification confirmation")
        store.showQueryApproval = false; store.pendingQuery = nil
        store.readOnly = true; await store.runQuery(approved: true)
        check(store.queryFailure != nil, "read-only blocks approved writes")
        store.readOnly = false
        store.closeScript(a)
        check(store.scriptResults[a] == nil, "close releases in-memory results")
        check(await store.openHistoricalScript(a), "closed script reopens from history")
        check(!store.queryHasRun, "history reopening does not execute SQL")
        let textBefore = store.query
        let missing = try scripts.create(name: "Missing", connectionID: profile.id, text: "SELECT 99;")
        try FileManager.default.removeItem(at: scripts.directory.appendingPathComponent(missing.uuidString + ".sql"))
        check(!(await store.openHistoricalScript(missing)) && store.query == textBefore && store.error != nil, "missing history preserves current draft and reports error")
        store.error = nil
        let orphan = try scripts.create(name: "Orphan", connectionID: UUID(), text: "SELECT 98;")
        check(!(await store.openHistoricalScript(orphan)) && store.query == textBefore && store.error != nil, "deleted connection preserves script with feedback")
        store.error = nil
        store.openScript(a)
        store.query = "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<150000000) SELECT sum(x) FROM n;"
        let task = Task { await store.runQuery() }
        try await Task.sleep(for: .milliseconds(100))
        store.openScript(b)
        await task.value
        check(store.selectedScriptID == b && store.queryResult.rows.first?.cells.first?.display == "22", "async completion does not replace selected script result")
        check(!store.showSlowQuerySuggestion && !defaults.bool(forKey: "slowQuerySuggestionShown"), "context switch suppresses stale slow prompt")
        store.openScript(a)
        let slow = Task { await store.runQuery() }
        try await Task.sleep(for: .milliseconds(5100))
        check(store.showSlowQuerySuggestion, "still-running query prompts after five seconds")
        await slow.value
        check(!store.showSlowQuerySuggestion, "completion clears slow prompt")
        let again = Task { await store.runQuery() }
        try await Task.sleep(for: .milliseconds(5100))
        check(!store.showSlowQuerySuggestion, "slow query suggestion appears at most once")
        await again.value
        store.tab = .query; store.openSettings(); check(store.settingsSection == "editor", "settings route editor context")
        store.showSettings = false; store.tab = .data; store.openSettings(); check(store.settingsSection == "data", "settings route data context")
        store.showSettings = false
        defaults.removeObject(forKey: "slowQuerySuggestionShown")
        store.openScript(a)
        let cancelled = Task { await store.runQuery() }
        try await Task.sleep(for: .milliseconds(100))
        cancelled.cancel()
        try await Task.sleep(for: .milliseconds(5100))
        check(!store.showSlowQuerySuggestion, "cancellation suppresses slow-query suggestion")
        await cancelled.value
        var estimateCalls = 0
        let estimateStore = WorkspaceStore(agentLibrary: AgentLibrary(file: root.appendingPathComponent("estimate-agent.json")), scripts: scripts, browseEstimator: { _ in estimateCalls += 1; return QueryEstimate(severity: .normal, summary: "test") })
        await estimateStore.connect(profile)
        await estimateStore.chooseObject(DatabaseObject(name: "records"))
        await estimateStore.setBrowseEstimateVisible(true)
        check(estimateCalls == 0, "showing estimate bar while disabled makes no estimate request")
        estimateStore.setEstimatesEnabled(true)
        await estimateStore.setBrowseEstimateVisible(true)
        check(estimateCalls == 1, "explicit enable permits optional browse planning")
        estimateStore.setEstimatesEnabled(false)
        _ = await estimateStore.refresh()
        check(estimateCalls == 1 && estimateStore.browseEstimate == nil, "disable prevents later optional browse planning")
        await estimateStore.engine.disconnect()
        await store.engine.disconnect()
        try await databases()
    }
    @MainActor static func crossConnectionHistory(_ root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = ScriptLibrary(directory: root.appendingPathComponent("scripts"))
        let store = WorkspaceStore(agentLibrary: AgentLibrary(file: root.appendingPathComponent("agents.json")), scripts: library)
        store.setEstimatesEnabled(false)
        var profiles: [ConnectionProfile] = []
        for name in ["First", "Second"] {
            let path = root.appendingPathComponent(name + ".sqlite").path
            var handle: OpaquePointer?; sqlite3_open(path, &handle); sqlite3_close(handle)
            profiles.append(ConnectionProfile(name: name, path: path))
        }
        store.profiles = profiles
        await store.connect(profiles[0])
        let a = try library.create(name: "Duplicate", connectionID: profiles[0].id, text: "SELECT 111;")
        store.openScript(a); await store.runQuery()
        await store.connect(profiles[1])
        let b = try library.create(name: "Duplicate", connectionID: profiles[1].id, text: "SELECT 222;")
        store.openScript(b); await store.runQuery()
        check(await store.openHistoricalScript(a), "history opens script on inactive original connection")
        check(store.active?.id == profiles[0].id && store.queryResult.rows.first?.cells.first?.display == "111", "connection switch restores only original script result")
        check(await store.openHistoricalScript(b), "duplicate name on another connection resolves by script ID")
        check(store.active?.id == profiles[1].id && store.queryResult.rows.first?.cells.first?.display == "222", "second connection retains separate session results")
        await store.engine.disconnect()
    }
    @MainActor static func databases() async throws {
        for kind in [DatabaseKind.postgresql, .mongodb] {
            let key = kind == .postgresql ? "TV053_PG_PORT" : "TV053_MONGO_PORT"
            guard let port = ProcessInfo.processInfo.environment[key] else { print("SKIP: \(key)"); continue }
            let engine = DatabaseEngine()
            let profile = ConnectionProfile(name: "Synthetic 053", kind: kind, host: "127.0.0.1", port: port, database: kind == .postgresql ? "postgres" : "extensions053", user: kind == .postgresql ? "postgres" : "")
            _ = try await engine.connect(profile, secret: kind == .mongodb ? "mongodb://127.0.0.1:\(port)/extensions053" : "")
            if kind == .postgresql {
                _ = try await engine.run("CREATE TABLE page_records(id INTEGER PRIMARY KEY)")
                _ = try await engine.run("INSERT INTO page_records SELECT generate_series(1,53)")
            } else {
                _ = try await engine.run("{\"insert\":\"page_records\",\"documents\":" + jsonText((1...53).map { ["_id": $0] }) + "}")
            }
            for size in [1, 7, 20, 53, 100] {
                var values: [String] = [], page = 0
                while true {
                    let result = try await engine.browse(DatabaseObject(name: "page_records"), page: page, pageSize: size)
                    values += result.rows.map { $0.cells[0].display }
                    if !result.hasMore { break }; page += 1
                }
                check(values.count == 53 && Set(values).count == 53, "\(kind.rawValue) page size \(size) boundaries")
            }
            await engine.disconnect()
        }
    }
}
