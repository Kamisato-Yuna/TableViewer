import SwiftUI
import Security

@main struct KeychainDenialTests {
    // All secrets in this fixture are invented; no macOS Keychain access occurs.
    final class CredentialBackend: @unchecked Sendable {
        var items: [UUID: String] = [:]
        var reads = 0, writes = 0, deletes = 0
        var failure: OSStatus?
        var duringRead: (() -> Void)?
        func store(enabled: Bool = true) -> CredentialSessionStore {
            CredentialSessionStore(enabled: enabled, load: { id in
                self.reads += 1
                if let failure = self.failure { throw ConnectionVault.readFailure(failure) }
                self.duringRead?()
                return self.items[id]
            }, persist: { secret, id in
                self.writes += 1
                if let failure = self.failure { throw ConnectionVault.readFailure(failure) }
                self.items[id] = secret
            }, delete: { id in
                self.deletes += 1
                if let failure = self.failure { throw ConnectionVault.readFailure(failure) }
                self.items[id] = nil
            })
        }
    }
    static func credentialSession() throws {
        let backend = CredentialBackend(), id = UUID(), other = UUID()
        backend.items = [id: "fixture-api-key", other: "fixture-db-password"]
        let store = backend.store()
        let first = try store.read(id: id), second = try store.read(id: id)
        try check(first == second && backend.reads == 1, "repeated model/settings reads share one authorized read")
        let separate = try store.read(id: other)
        try check(separate == "fixture-db-password" && backend.reads == 2, "different credential IDs remain isolated")
        try store.save(first, id: id)
        try check(backend.writes == 0, "saving unchanged credentials does not request Keychain write access")
        try store.save("replacement", id: id)
        let replacement = try store.read(id: id)
        try check(replacement == "replacement" && backend.writes == 1 && backend.reads == 2, "successful save replaces cached key without readback")
        try store.save("", id: id)
        let empty = try store.read(id: id)
        try check(empty.isEmpty && backend.reads == 2, "saved empty keys support unauthenticated local models")
        try store.remove(id: id)
        let missing = try store.read(id: id)
        backend.items[id] = "externally-created"
        let created = try store.read(id: id)
        try check(missing.isEmpty && created == "externally-created" && backend.deletes == 1, "deletion evicts old credentials and missing items are not cached")
        for status in [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed] {
            store.clear(); backend.failure = status
            var failed = false
            do { _ = try store.read(id: id) } catch { failed = true }
            backend.failure = nil
            let before = backend.reads, retried = try store.read(id: id)
            try check(failed && retried == "externally-created" && backend.reads == before + 1, "failed read is not cached and explicit retry succeeds: \(status)")
        }
        backend.failure = errSecAuthFailed
        var writeFailed = false
        do { try store.save("must-not-cache", id: id) } catch { writeFailed = true }
        backend.failure = nil
        var before = backend.reads
        let afterFailedSave = try store.read(id: id)
        try check(writeFailed && afterFailedSave == "externally-created" && backend.reads == before + 1, "failed save neither caches new input nor retains the old cache")
        backend.failure = errSecUserCanceled
        var deleteFailed = false
        do { try store.remove(id: id) } catch { deleteFailed = true }
        backend.failure = nil; before = backend.reads
        _ = try store.read(id: id)
        try check(deleteFailed && backend.reads == before + 1, "failed deletion still evicts the in-memory credential")
        store.clear(); before = backend.reads
        _ = try store.read(id: id); _ = try store.read(id: other)
        try check(backend.reads == before + 2, "security invalidation clears every credential")
        store.clear(); backend.duringRead = { store.clear() }
        _ = try store.read(id: id)
        backend.duringRead = nil; before = backend.reads
        _ = try store.read(id: id)
        try check(backend.reads == before + 1, "lock during an in-flight read prevents repopulation and does not deadlock")
        store.setEnabled(false); before = backend.reads
        _ = try store.read(id: id); _ = try store.read(id: id)
        try check(backend.reads == before + 2, "unavailable security monitoring falls back to direct Keychain reads")
        store.setEnabled(true); before = backend.reads
        _ = try store.read(id: id); _ = try store.read(id: id)
        try check(backend.reads == before + 1, "re-enabling reuse begins with a fresh authorized read")
        let restarted = backend.store(); before = backend.reads
        _ = try restarted.read(id: id)
        try check(backend.reads == before + 1, "a new process session does not inherit cached credentials")

        // Match concurrent model sessions without issuing real HTTP or Keychain requests.
        let concurrentBackend = CredentialBackend()
        concurrentBackend.items[id] = "parallel-fixture"
        let concurrent = concurrentBackend.store(), resultLock = NSLock()
        nonisolated(unsafe) var correct = 0
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            if (try? concurrent.read(id: id)) == "parallel-fixture" { resultLock.withLock { correct += 1 } }
        }
        try check(correct == 20 && concurrentBackend.reads == 1, "twenty concurrent model reads require one backend authorization")
    }
    static func check(_ value: Bool, _ name: String) throws {
        guard value else { throw DatabaseFailure("FAIL: " + name) }
        print("PASS: " + name)
    }
    static func fixture(_ directory: URL, name: String) throws -> ConnectionProfile {
        let file = directory.appendingPathComponent(name + ".sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(file.path, &db) == SQLITE_OK else { throw DatabaseFailure("fixture open failed") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "CREATE TABLE marker(id INTEGER PRIMARY KEY, value TEXT, detail TEXT); INSERT INTO marker VALUES(1,'fixture','detail');", nil, nil, nil) == SQLITE_OK else { throw DatabaseFailure("fixture seed failed") }
        return ConnectionProfile(name: name, path: file.path)
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        try credentialSession()
        try check(ConnectionVault.startSession() == errSecSuccess && ConnectionVault.startSession() == errSecSuccess, "macOS security notification registration succeeds and is idempotent")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tableviewer-keychain-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try inspectorBindings(directory: directory)
        let a = try fixture(directory, name: "A"), b = try fixture(directory, name: "B")
        let library = AgentLibrary(file: directory.appendingPathComponent("history.json"))
        var readStatus: OSStatus = errSecAuthFailed
        var reads: [UUID] = []
        let store = WorkspaceStore(agentLibrary: library, readCredential: { id in
            reads.append(id)
            if readStatus != errSecSuccess { throw ConnectionVault.readFailure(readStatus) }
            return "invalid-test-uri" // Deliberate local Mongo URI parse failure; never a real credential.
        })
        store.profiles = [a,b]
        await store.connect(a)
        try check(store.active?.id == a.id && reads.isEmpty, "SQLite connection bypasses Keychain")
        let row = store.selectedRow!, object = store.selectedObject!, columns = store.result.columns
        let field = store.fieldBinding(row: row, index: 2, column: columns[2])
        let null = Binding(get: { field.wrappedValue.isNull }, set: { field.wrappedValue = $0 ? .null : .text("detail") })
        store.query = "SELECT 42"; await store.runQuery()
        store.tab = .query; store.page = 3; store.sortColumn = "value"; store.sortAscending = false
        store.rowSearch = "fixture"; store.objectSearch = "marker"
        store.shellInput = "draft"; store.shellHistory = ["previous"]
        store.shellEntries = [ShellEntry(command: "previous", output: "local output", database: "A")]
        store.shellDatabase = "A"; store.replicaError = "retained notice"
        let owner = library.selected!
        owner.input = "Agent draft"; owner.shareSchema = true
        let call = AgentToolCall(id: "local-call", function: AgentFunction(name: "execute_query", arguments: #"{"query":"SELECT 1"}"#))
        let reply = AgentMessage(role: "assistant", content: "visible reply", toolCalls: [call])
        owner.messages.append(reply)
        owner.actions.append(AgentAction(call: call, messageID: reply.id, connectionID: a.id, connectionName: a.name))
        let sessionID = owner.id, actionID = owner.actions[0].id
        // An open transaction proves a denial never disconnects/reconnects the original engine.
        _ = try await store.engine.run("BEGIN")
        _ = try await store.engine.run("UPDATE marker SET value='uncommitted'")
        let remote = ConnectionProfile(name: "Denied remote", kind: .mongodb)
        for status in [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed] {
            readStatus = status
            await store.connect(remote)
            try check(!store.busy && store.error?.contains("尚未切换数据库") == true && store.status == String(localized: "操作未完成"), "credential read error is visible and releases busy: \(status)")
            try check(store.active?.id == a.id && store.selectedObject == object && store.selectedRowID == row.id && store.result.rows.first?.id == row.id && store.draft == row.cells, "credential read error preserves connection, selected row and inspector draft: \(status)")
            try check(store.tab == .query && store.query == "SELECT 42" && store.queryHasRun && store.queryResult.rows.first?.cells.first == .text("42") && store.queryHistory == ["SELECT 42"] && store.page == 3 && store.sortColumn == "value" && !store.sortAscending && store.rowSearch == "fixture" && store.objectSearch == "marker", "credential read error preserves page, query and navigation state: \(status)")
            try check(store.shellInput == "draft" && store.shellHistory == ["previous"] && store.shellEntries.first?.output == "local output" && store.shellDatabase == "A" && store.replicaError == "retained notice", "credential read error preserves shell and replica view state: \(status)")
            try check(library.selectedID == sessionID && owner.messages.last?.id == reply.id && owner.actions[0].id == actionID && owner.actions[0].state == .awaitingApproval && !owner.actions[0].shared && owner.input == "Agent draft" && store.agentContext(for: owner)?.connectionID == a.id, "credential read error preserves Agent history and original connection: \(status)")
            try check(field.wrappedValue == .text("detail") && !null.wrappedValue, "retained field and NULL getters remain readable after denial: \(status)")
            let result = try await store.engine.run("SELECT value FROM marker")
            try check(result.rows.first?.cells.first == .text("uncommitted"), "denial preserves live driver and uncommitted transaction: \(status)")
        }
        try check(reads == [remote.id,remote.id,remote.id], "retry performs a new controlled credential read")
        _ = try await store.engine.run("ROLLBACK")
        try check(ConnectionVault.readFailure(errSecUserCanceled).localizedDescription.contains("取消") && ConnectionVault.readFailure(errSecAuthFailed).localizedDescription.contains("未授权") && ConnectionVault.readFailure(errSecInteractionNotAllowed).localizedDescription == String(localized: "无法读取钥匙串凭据（\(errSecInteractionNotAllowed)）。"), "Keychain cancellation, denial and other statuses have readable diagnostics")
        await store.connect(b)
        try check(store.active?.id == b.id && !store.busy && store.error == nil && reads.count == 3, "can switch to another database after denial without another credential read")
        field.wrappedValue = .text("wrong database"); null.wrappedValue = true
        try check(field.wrappedValue == .text("detail") && store.draft == store.selectedRow?.cells && !store.canExecuteAgent(owner) && store.agentContext(for: owner)?.schema == nil, "retained inspector and Agent actions cannot target B after switching")
        _ = owner.beginExecution(actionID, connectionID: a.id)
        owner.resolve(actionID, output: "A local result", failed: false)
        try check(owner.actions[0].outcome == "A local result" && !owner.actions[0].shared && library.selectedID == sessionID, "late Agent completion retains original owner and separate sharing approval")
        // A credential success followed by a driver error must retain the existing failure contract.
        readStatus = errSecSuccess
        await store.connect(remote)
        try check(reads.count == 4 && store.active == nil && store.result.rows.isEmpty && store.draft.isEmpty && store.queryResult.rows.isEmpty && !store.queryHasRun && !store.busy && store.error != nil && store.error?.contains("尚未切换数据库") == false, "driver failure after credential success is distinct and clears unusable workspace")
        field.wrappedValue = .text("stale"); null.wrappedValue = true
        try check(field.wrappedValue == .text("detail") && !null.wrappedValue && store.draft.isEmpty, "retained field and NULL bindings are safe after async driver failure")
        do { _ = try await store.engine.run("SELECT 1"); throw DatabaseFailure("FAIL: driver stayed connected") }
        catch { try check(error.localizedDescription.contains("未连接"), "driver failure releases its handle") }
        try check(library.selectedID == sessionID && owner.messages.last?.id == reply.id && owner.actions[0].outcome == "A local result", "driver failure preserves global Agent history and local results")
        await store.connect(a)
        try check(store.active?.id == a.id && !store.busy && store.error == nil && store.selectedRow != nil, "workspace recovers normally after driver failure")
        let currentRow = store.selectedRow!, binding = store.fieldBinding(row: store.selectedRow!, index: 1, column: store.result.columns[1])
        binding.wrappedValue = .text("unsaved")
        let count = reads.count
        await store.connect(remote)
        try check(store.active?.id == a.id && store.selectedRow?.id == currentRow.id && store.hasChanges && reads.count == count, "unsaved edits still block navigation before reading credentials")
        store.discard()
        await store.engine.disconnect()
        print("ALL KEYCHAIN DENIAL CHECKS PASSED")
    }
    @MainActor static func inspectorBindings(directory: URL) throws {
        let store = WorkspaceStore(agentLibrary: AgentLibrary(file: directory.appendingPathComponent("bindings.json")))
        store.active = ConnectionProfile(name: "Binding regression")
        store.selectedObject = DatabaseObject(name: "wide")
        let columns = [ColumnInfo(name: "id", isPrimaryKey: true), ColumnInfo(name: "name"), ColumnInfo(name: "detail")]
        let first = DataRow(cells: [.text("1"), .text("first"), .text("detail")])
        let second = DataRow(cells: [.text("2"), .text("second"), .text("other")])
        store.result = QueryResult(columns: columns, rows: [first, second])
        store.selectRow(first.id)
        let name = store.fieldBinding(row: first, index: 1, column: columns[1])
        let detail = store.fieldBinding(row: first, index: 2, column: columns[2])
        name.wrappedValue = .text("edited")
        try check(store.draft[1] == .text("edited") && store.hasChanges, "current inspector binding edits its record")
        name.wrappedValue = .null
        try check(name.wrappedValue.isNull && store.draft[1].isNull, "current inspector binding supports NULL")
        store.discard()
        store.busy = true; name.wrappedValue = .text("late save callback"); store.busy = false
        let primaryKey = store.fieldBinding(row: first, index: 0, column: columns[0])
        primaryKey.wrappedValue = .text("99")
        try check(store.draft == first.cells, "busy and primary-key bindings reject writes")
        store.selectRow(second.id)
        name.wrappedValue = .text("wrong record")
        try check(name.wrappedValue == .text("first") && store.draft == second.cells, "retained binding cannot read or overwrite another row")
        store.selectRow(first.id)
        store.result.columns.swapAt(1, 2)
        name.wrappedValue = .text("wrong column")
        try check(store.draft == first.cells, "retained binding rejects reordered columns")
        store.result.columns = columns
        store.selectedObject = DatabaseObject(name: "narrow")
        name.wrappedValue = .text("during table transition")
        try check(store.draft == first.cells, "binding rejects writes while selected table changes")
        let narrow = DataRow(cells: [.text("3")])
        store.result = QueryResult(columns: [columns[0]], rows: [narrow])
        store.selectRow(narrow.id)
        detail.wrappedValue = .null
        try check(detail.wrappedValue == .text("detail") && store.draft == narrow.cells, "wide-to-narrow transition safely reads and writes retained bindings")
        store.result = QueryResult(); store.selectRow(nil)
        detail.wrappedValue = .text("removed")
        try check(detail.wrappedValue == .text("detail") && store.draft.isEmpty, "empty results safely retire inspector bindings")
        store.result = QueryResult(columns: columns, rows: [first]); store.selectRow(first.id)
        store.selectedObject = DatabaseObject(name: "wide")
        let truncated = store.fieldBinding(row: first, index: 2, column: columns[2])
        store.draft = []
        truncated.wrappedValue = .null
        try check(truncated.wrappedValue == .text("detail") && store.draft.isEmpty, "temporarily truncated draft does not index out of bounds")
        store.draft = first.cells
        let oldConnection = store.fieldBinding(row: first, index: 1, column: columns[1])
        store.active = ConnectionProfile(name: "Different connection")
        oldConnection.wrappedValue = .text("wrong connection")
        try check(oldConnection.wrappedValue == .text("first") && store.draft == first.cells, "retained binding rejects another connection even with identical row identity")
        store.active = ConnectionProfile(name: "Documents", kind: .mongodb)
        let document = DataRow(cells: [], document: "{\"name\":\"first\"}")
        store.result = QueryResult(rows: [document]); store.selectRow(document.id)
        let json = store.documentBinding(row: document)
        json.wrappedValue = "{\"name\":\"edited\"}"
        try check(store.hasChanges && store.documentDraft.contains("edited"), "current document binding edits JSON")
        store.discard()
        store.busy = true; json.wrappedValue = "{}"; store.busy = false
        try check(store.documentDraft == document.document, "busy document binding rejects writes")
        let otherDocument = DataRow(cells: [], document: "{\"name\":\"second\"}")
        store.result = QueryResult(rows: [otherDocument]); store.selectRow(otherDocument.id)
        json.wrappedValue = "{}"
        try check(json.wrappedValue == document.document && store.documentDraft == otherDocument.document, "retained document binding cannot overwrite another document")
        store.active = nil; store.result = QueryResult(); store.selectedRowID = nil; store.documentDraft = ""
        json.wrappedValue = "{}"
        try check(json.wrappedValue == document.document && store.documentDraft.isEmpty, "retained document binding safely retires after failed connection")
    }
}
