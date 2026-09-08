import Foundation

actor ExecutionHold {
    var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0; waiting = true } }
    func release() { continuation?.resume(); continuation = nil; waiting = false }
}
actor ReplyHold {
    private var delta: (@Sendable (String) async -> Void)?
    private var continuation: CheckedContinuation<AgentMessage, Error>?
    var waiting: Bool { continuation != nil }
    func wait(delta: @escaping @Sendable (String) async -> Void) async throws -> AgentMessage {
        self.delta = delta
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func emit(_ value: String) async { await delta?(value) }
    func finish(_ value: String) { continuation?.resume(returning: AgentMessage(role: "assistant", content: value)); continuation = nil }
}
@main struct AgentWorkspaceTests {
    static func check(_ value: Bool, _ name: String) throws { guard value else { throw DatabaseFailure("FAIL: " + name) }; print("PASS: " + name) }
    @MainActor static func eventually(_ predicate: () async -> Bool) async throws {
        for _ in 0..<400 { if await predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        throw DatabaseFailure("Timed out")
    }
    static func fixture(_ directory: URL, name: String) throws -> ConnectionProfile {
        let file = directory.appendingPathComponent(name + ".sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw DatabaseFailure("fixture open failed") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "CREATE TABLE marker(id INTEGER PRIMARY KEY, value TEXT); INSERT INTO marker VALUES(1,'\(name)');", nil, nil, nil) == SQLITE_OK else { throw DatabaseFailure("fixture seed failed") }
        return ConnectionProfile(name: name, path: file.path)
    }
    @MainActor static func addAction(_ session: AgentSession, name: String, query: String = "SELECT value FROM marker") -> AgentAction {
        let arguments = name == "ask_user" ? #"{"question":"选择范围？","options":["全部","前十项"]}"# : name == "inspect_schema" ? "{}" : "{\"query\":\"\(query)\",\"reason\":\"fixture only\"}"
        let call = AgentToolCall(id: "call-" + UUID().uuidString, function: AgentFunction(name: name, arguments: arguments))
        let message = AgentMessage(role: "assistant", toolCalls: [call])
        session.messages.append(message)
        let action = AgentAction(call: call, messageID: message.id, connectionID: session.connection!.connectionID, connectionName: session.connection!.connectionName)
        session.actions.append(action); return action
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tableviewer-agent-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try fixture(directory, name: "Fixture-A"), b = try fixture(directory, name: "Fixture-B")
        let file = directory.appendingPathComponent("agent-conversations.json")
        let library = AgentLibrary(file: file), hold = ExecutionHold(), executor = AgentToolExecutor()
        let store = WorkspaceStore(agentLibrary: library, agentExecution: { id, action, profile, object in
            await hold.wait()
            return try await executor.execute(sessionID: id, action: action, profile: profile, object: object)
        }, scripts: ScriptLibrary(directory: directory.appendingPathComponent("Scripts")))
        store.profiles = [a,b]
        await store.connect(a)
        try check(library.sessions.isEmpty, "connecting alone does not create an Agent session")
        store.newAgentSession()
        let initial = library.selected!
        let schemaCall = AgentToolCall(id: "schema-test", function: AgentFunction(name: "inspect_schema", arguments: "{}"))
        let schemaAction = AgentAction(call: schemaCall, messageID: UUID(), connectionID: a.id, connectionName: a.name)
        let schemaText = try await executor.execute(sessionID: initial.id, action: schemaAction, profile: a, object: DatabaseObject(name: "marker"))
        let schemaObject = try jsonObject(schemaText)
        let fields = schemaObject["columns"] as? [[String: Any]]
        try check(fields?.first { $0["name"] as? String == "id" }?["primaryKey"] as? Bool == true && fields?.first { $0["name"] as? String == "value" }?["primaryKey"] as? Bool == false, "schema inspection preserves actual primary-key metadata")
        let plan = try await store.engine.run("EXPLAIN QUERY PLAN SELECT * FROM marker WHERE id = 1")
        let indexes = try await store.engine.run("PRAGMA index_list('marker')")
        try check(indexes.rows.isEmpty && plan.rows.contains { $0.cells.contains { $0.display.contains("INTEGER PRIMARY KEY") } }, "SQLite rowid primary-key lookup works without a separate index-list entry")
        initial.input = "unsent draft"
        store.newAgentSession()
        try check(library.sessions.count == 2 && initial.input == "unsent draft" && initial.id != library.selected?.id, "new conversation preserves previous history and draft")
        let owner = library.selected!
        let action = addAction(owner, name: "execute_query")
        let execution = Task { await store.executeAgentAction(action.id, in: owner, automatic: true) }
        try await eventually { await hold.waiting }
        try check(owner.actions.last?.state == .executing && !store.busy, "tool owns separate execution state without blocking database navigation")
        await store.connect(b); store.newAgentSession()
        let other = library.selected!
        store.queryResult = QueryResult(affectedRows: 987)
        owner.shareSchema = true
        try check(store.active?.id == b.id && store.agentContext(for: owner)?.connectionID == a.id && store.agentContext(for: owner)?.schema == nil, "opening A history while B is active cannot attach B schema")
        try check(!store.canExecuteAgent(owner) && owner.actions.last?.state == .executing, "switch to B preserves executing A session and disallows wrong-connection approval")
        await hold.release(); await execution.value
        try check(owner.actions.last?.state == .completed && owner.actions.last?.outcome?.contains("Fixture-A") == true && owner.actions.last?.outcome?.contains("Fixture-B") == false, "actual SQLite result completes in original A session after switching to B")
        try check(other.actions.isEmpty && store.queryResult.affectedRows == 987 && library.selectedID == other.id && !owner.actions.last!.shared, "late tool result never overwrites selected B session, query result or sharing approval")
        await store.connect(a); library.open(owner.id)
        try check(owner.actions.last?.outcome?.contains("Fixture-A") == true, "returning to A retains unshared result")
        let rejected = addAction(owner, name: "inspect_schema"); owner.reject(rejected.id)
        let question = addAction(owner, name: "ask_user"); owner.answer(question.id, text: "前十项，保留备注")
        let pending = addAction(owner, name: "inspect_schema")
        await store.connect(b)
        try check(owner.actions.first { $0.id == rejected.id }?.state == .rejected && owner.actions.last?.state == .awaitingApproval && owner.actions.first { $0.id == question.id }?.outcome == "前十项，保留备注", "switching retains rejected, awaiting-approval and clarification-answer states")
        await store.executeAgentAction(pending.id, in: owner)
        try check(owner.actions.last?.state == .awaitingApproval, "cannot execute A pending action while B is active")
        let reply = ReplyHold()
        let generating = AgentSession { _, _, _, delta in try await reply.wait(delta: delta) }
        generating.configuration = AgentConfiguration(baseURL: "https://example.invalid/v1", model: "fixture")
        generating.connection = AgentContext(connectionID: a.id, connectionName: a.name, kind: .sqlite)
        library.add(generating); generating.input = "生成测试"; generating.send(context: generating.connection!)
        try await eventually { await reply.waiting }
        await reply.emit("A 的部分回复")
        library.open(other.id); await store.connect(a); await store.connect(b)
        library.rename(generating, to: "待处理的 A 分页")
        library.archive(generating, archived: true)
        try check(generating.running && generating.messages.last?.content == "A 的部分回复" && library.matching("Fixture-A", archived: true).contains { $0.id == generating.id }, "rename/search/archive keep background generation alive across database and session changes")
        library.save()
        let restarted = AgentLibrary(file: file)
        let interrupted = restarted.sessions.first { $0.id == generating.id }!
        try check(!interrupted.running && interrupted.messages.last?.delivery == .interrupted && interrupted.messages.last?.content == "A 的部分回复" && interrupted.archived, "restart restores partial reply as interrupted without replaying request")
        await reply.emit("，后来完成")
        await reply.finish("A 的完整回复")
        try await eventually { !generating.running }
        try check(generating.messages.last?.content == "A 的完整回复" && library.selectedID == other.id, "archived background reply finishes into original owner")
        library.archive(generating, archived: false)
        try check(library.matching("分页", archived: false).contains { $0.id == generating.id }, "restore and title search retain full history")
        let uncertain = addAction(other, name: "execute_query")
        _ = other.beginExecution(uncertain.id, connectionID: b.id)
        let questionDraft = addAction(owner, name: "ask_user")
        owner.setAnswerDraft(questionDraft.id, text: "尚未确认的选项补充")
        library.save()
        let restored = AgentLibrary(file: file)
        let restoredA = restored.sessions.first { $0.id == owner.id }!, restoredB = restored.sessions.first { $0.id == other.id }!
        try check(restoredA.actions.first?.outcome?.contains("Fixture-A") == true && restoredA.actions.first?.shared == false && restoredA.messages.first?.id == action.messageID, "local reload preserves message IDs, tool results and unshared state")
        try check(restoredA.actions.first { $0.id == rejected.id }?.state == .rejected && restoredA.actions.first { $0.id == question.id }?.outcome == "前十项，保留备注" && restoredA.actions.last?.state == .awaitingApproval, "local reload preserves rejection, clarification and pending approval")
        try check(restoredB.actions.last?.state == .uncertain && restoredB.actions.last?.outcome?.contains("不会自动重执行") == true && restoredB.beginExecution(uncertain.id, connectionID: b.id) == nil, "restart marks executing action uncertain and forbids replay")
        try check(restoredA.actions.first { $0.id == questionDraft.id }?.draftAnswer == "尚未确认的选项补充", "clarification draft survives switching and local restoration")
        let saved = try String(contentsOf: file, encoding: .utf8)
        try check(!saved.contains(a.path) && !saved.contains(b.path) && !saved.contains("password") && !saved.contains("Authorization"), "archive stores connection identity without database paths, credentials or auth headers")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue == 0o600, "history file is user-readable and writable only")
        library.open(owner.id)
        await store.removeConnection(a)
        try check(library.sessions.contains { $0.id == owner.id } && owner.actions.first?.outcome != nil && !store.canExecuteAgent(owner), "removing a connection preserves history and prevents implicit rebinding")
        await store.chooseObject(DatabaseObject(name: "marker"))
        store.selectRow(store.result.rows.first?.id)
        if store.draft.count > 1 { store.draft[1] = .text("unsaved") }
        await store.connect(a)
        try check(store.active?.id == b.id && store.hasChanges, "existing unsaved database edit protection still prevents navigation")
        store.discard()
        let corruptFile = directory.appendingPathComponent("corrupt.json")
        try Data("not JSON".utf8).write(to: corruptFile)
        let corrupt = AgentLibrary(file: corruptFile)
        corrupt.create(context: generating.connection!); corrupt.save()
        try check(corrupt.persistenceError != nil && (try String(contentsOf: corruptFile, encoding: .utf8)) == "not JSON", "unreadable history is reported and never overwritten")
        await executor.close(); await store.engine.disconnect()
        print("ALL AGENT WORKSPACE CHECKS PASSED")
    }
}
