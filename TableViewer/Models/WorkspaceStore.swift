import SwiftUI
import Observation
import UniformTypeIdentifiers

enum WorkspaceTab: String, CaseIterable {
    case overview = "概览", relationships = "关系", data = "数据", structure = "结构", query = "查询", replica = "副本集", shell = "终端", agent = "Agent"
    var title: String {
        switch self {
        case .overview: String(localized: "对象概览")
        case .relationships: String(localized: "实体关系")
        case .data: String(localized: "数据")
        case .structure: String(localized: "结构")
        case .query: String(localized: "查询")
        case .replica: String(localized: "副本集")
        case .shell: String(localized: "终端")
        case .agent: "Agent"
        }
    }
    static let basic: [Self] = [.data, .structure, .query]
    var symbol: String { switch self { case .overview: "square.grid.2x2"; case .relationships: "point.3.connected.trianglepath.dotted"; case .data: "tablecells"; case .structure: "square.stack.3d.up"; case .query: "chevron.left.forwardslash.chevron.right"; case .replica: "point.3.connected.trianglepath.dotted"; case .shell: "terminal"; case .agent: "sparkles" } }
}

struct ShellEntry: Identifiable {
    var id = UUID()
    var command: String
    var output = ""
    var database: String
    var failed = false
}

@MainActor @Observable final class WorkspaceStore {
    let engine = DatabaseEngine()
    var profiles: [ConnectionProfile] = []
    var active: ConnectionProfile?
    var objects: [DatabaseObject] = []
    var selectedObject: DatabaseObject?
    var schemaMetadata: SchemaMetadata?
    var relationships: [TableRelationship] = []
    var structureLoading = false
    var relationshipLoading = false
    var structureError: String?
    var relationshipError: String?
    var result = QueryResult()
    var selectedRowID: UUID?
    var draft: [CellValue] = []
    var documentDraft = ""
    var objectSearch = ""
    var rowSearch = ""
    var tab = WorkspaceTab.overview
    var query = "" { didSet { if let selectedScriptID { do { try scripts.save(selectedScriptID, text: query); scriptSaveError = nil } catch { scriptSaveError = error.localizedDescription; report(error) } } } }
    let scripts: ScriptLibrary
    @ObservationIgnored var queryEditorViews: [UUID: NSScrollView] = [:]
    var selectedScriptID: UUID?
    var querySelection = NSRange(location: 0, length: 0)
    var statementResults: [StatementResult] = []
    var selectedResultIndex = 0
    var queryFailure: String?
    var showScripts = false
    var showScriptName = false
    var renamingScriptID: UUID?
    var scriptName = ""
    var readOnly = false
    var browseEstimate: QueryEstimate?
    var scriptSaveError: String?
    var selectedRowIDs = Set<UUID>()
    var readOnlyNotice = false
    var filterIsCondition = false
    var condition = ""
    var appliedCondition = ""
    var estimates: [QueryEstimate] = []
    var pendingQuery: String?
    var showQueryApproval = false
    var queryResult = QueryResult()
    var queryHasRun = false
    var queryHistory: [String] = []
    var page = 0
    var sortColumn: String?
    var sortAscending = true
    var busy = false
    var status = String(localized: "准备就绪")
    var error: String?
    var showConnectionSheet = false
    var editingProfile: ConnectionProfile?
    var showInspector = false
    var showInsert = false
    var showDelete = false
    var editingCellIndex: Int?
    var showCellEditor = false
    var removingProfile: ConnectionProfile?
    var didStart = false
    var replicaSnapshot: ReplicaSnapshot?
    var replicaError: String?
    var replicaLoading = false
    let shell = ShellSession()
    var shellInput = ""
    var shellEntries: [ShellEntry] = []
    var shellHistory: [String] = []
    var shellHistoryIndex = 0
    var shellDatabase = ""
    var shellRunning = false
    let agentLibrary: AgentLibrary
    var showAgentHistory = false
    typealias AgentExecution = @Sendable (UUID, AgentAction, ConnectionProfile, DatabaseObject?) async throws -> String
    private let agentExecution: @Sendable (UUID, AgentAction, ConnectionProfile, DatabaseObject?, Bool) async throws -> String
    private let readCredential: (UUID) throws -> String
    init(agentLibrary: AgentLibrary? = nil, agentExecution: AgentExecution? = nil, readCredential: @escaping (UUID) throws -> String = { try ConnectionVault.read(id: $0) }, scripts: ScriptLibrary? = nil) {
        self.scripts = scripts ?? ScriptLibrary()
        self.readCredential = readCredential
        self.agentLibrary = agentLibrary ?? AgentLibrary()
        let executor = AgentToolExecutor()
        if let agentExecution { self.agentExecution = { id, action, profile, object, _ in try await agentExecution(id, action, profile, object) } }
        else { self.agentExecution = { id, action, profile, object, readOnly in try await executor.execute(sessionID: id, action: action, profile: profile, object: object, readOnly: readOnly) } }
        bindAutomaticActions()
    }
    var agent: AgentSession? { agentLibrary.selected }
    func newAgentSession(for profile: ConnectionProfile? = nil) {
        guard let profile = profile ?? active else { showAgentHistory = true; return }
        agentLibrary.create(context: AgentContext(connectionID: profile.id, connectionName: profile.name, kind: profile.kind))
        bindAutomaticActions()
        tab = .agent
    }
    func openAgentHistory() { if allowNavigation() { tab = .agent; showAgentHistory = true } }
    func agentContext(for session: AgentSession) -> AgentContext? {
        guard var context = session.connection else { return nil }
        context.schema = session.shareSchema && active?.id == context.connectionID ? schemaDescription : nil
        return context
    }
    func canExecuteAgent(_ session: AgentSession) -> Bool {
        !session.archived && active?.id == session.connection?.connectionID && profiles.contains { $0.id == session.connection?.connectionID } && !busy && !hasChanges && !session.actions.contains { $0.state == .executing }
    }

    var schemaDescription: String {
        let names = objects.prefix(100).map { $0.schema.isEmpty ? $0.name : $0.schema + "." + $0.name }.joined(separator: ", ")
        return String(localized: "表/集合：\(names)\n当前对象：\(selectedObject?.name ?? String(localized: "无"))\n字段：") + result.columns.map { "\($0.name) \($0.type)\($0.isPrimaryKey ? " PRIMARY KEY" : "")" }.joined(separator: ", ")
    }

    var selectedRow: DataRow? { result.rows.first { $0.id == selectedRowID } }
    var hasChanges: Bool {
        guard let row = selectedRow else { return false }
        return active?.kind == .mongodb ? documentDraft != row.document : draft != row.cells
    }
    var terminationWarning: String? {
        if let scriptSaveError { return scriptSaveError }
        if busy { return String(localized: "数据库操作仍在进行。退出不会撤销已完成的写入；未提交的 SQL 事务会在连接关闭后回滚。") }
        if hasChanges { return String(localized: "当前记录有未保存的修改，退出会丢失这些修改。请取消退出后保存或撤销。") }
        if agentLibrary.workingCount > 0 { return String(localized: "Agent 仍在生成或执行。历史会保存在本机；退出后中断的操作不会自动重放，数据库执行结果可能需要核实。") }
        if let historyError = agentLibrary.persistenceError { return historyError }
        return nil
    }
    var canEdit: Bool { !readOnly && selectedObject != nil && selectedObject?.isView == false && (active?.kind == .mongodb || result.columns.contains(where: \.isPrimaryKey)) }
    var visibleObjects: [DatabaseObject] { objectSearch.isEmpty ? objects : objects.filter { $0.name.localizedCaseInsensitiveContains(objectSearch) || $0.schema.localizedCaseInsensitiveContains(objectSearch) } }
    var displayedResult: QueryResult { tab == .query ? queryResult : result }
    var visibleRows: [DataRow] {
        let rows = displayedResult.rows
        return rowSearch.isEmpty ? rows : rows.filter { $0.cells.contains { $0.display.localizedCaseInsensitiveContains(rowSearch) } }
    }

    func start() async {
        guard !didStart else { return }; didStart = true
        if UserDefaults.standard.bool(forKey: "scriptAutoCleanup") {
            do { try scripts.delete(Set(scripts.unused(days: UserDefaults.standard.integer(forKey: "scriptCleanupDays") == 0 ? 90 : UserDefaults.standard.integer(forKey: "scriptCleanupDays")).map(\.id))) }
            catch { report(error) }
        }
        var loadFailure: Error?
        do { profiles = try LocalWorkspace.loadProfiles() }
        catch { loadFailure = error }
        do {
            let demo = try LocalWorkspace.createDemo()
            profiles.append(demo)
            await connect(demo)
        } catch { report(error) }
        if let loadFailure { report(DatabaseFailure(String(localized: "连接配置读取失败，原文件已保留：") + loadFailure.localizedDescription)) }
    }

    func report(_ failure: Error) {
        error = failure.localizedDescription
        status = String(localized: "操作未完成")
    }

    func allowNavigation() -> Bool {
        guard !busy else { return false }
        if hasChanges { error = String(localized: "当前记录有未保存的修改，请先保存或撤销。"); return false }
        return true
    }

    func connect(_ profile: ConnectionProfile, secret: String? = nil) async {
        guard allowNavigation() else { return }
        error = nil
        busy = true; status = String(localized: "正在连接…")
        defer { busy = false }
        // A denied/cancelled Keychain read must not retire the current workspace or driver.
        let credential: String
        do { credential = try secret ?? (profile.kind == .sqlite ? "" : readCredential(profile.id)) }
        catch {
            report(DatabaseFailure(String(localized: "未能读取连接凭据，尚未切换数据库。请重试或选择其他连接。") + "\n" + error.localizedDescription))
            return
        }
        await shell.stop(); shellEntries = []; shellHistory = []; shellInput = ""; shellDatabase = profile.database
        replicaSnapshot = nil; replicaError = nil
        queryEditorViews.removeAll()
        selectedScriptID = nil; queryResult = QueryResult(); queryHasRun = false; queryHistory = []; query = ""
        do {
            let loaded = try await engine.connect(profile, secret: credential)
            active = profile; objects = loaded
            schemaMetadata = nil; relationships = []; structureError = nil; relationshipError = nil; browseEstimate = nil
            if agentLibrary.selected == nil { newAgentSession(for: profile) }
            selectedObject = nil; result = QueryResult(); selectedRowID = nil
            page = 0; sortColumn = nil; rowSearch = ""; objectSearch = ""; tab = .overview
            queryResult = QueryResult(); queryHasRun = false; queryHistory = []
            query = profile.kind == .mongodb ? "{\n  \"find\": \"\(loaded.first?.name ?? "collection")\",\n  \"filter\": {},\n  \"limit\": 100\n}" : "SELECT * FROM \(loaded.first?.qualifiedName ?? "table_name") LIMIT 100;"
            if let script = scripts.scripts.first(where: { $0.connectionID == profile.id && $0.isOpen }) {
                query = try scripts.open(script.id); selectedScriptID = script.id
            }
            status = String(localized: "已连接")
        } catch {
            await engine.disconnect()
            active = nil; objects = []; selectedObject = nil; result = QueryResult(); selectedRowID = nil
            draft = []; documentDraft = ""
            report(error)
        }
    }

    func chooseObject(_ object: DatabaseObject) async {
        guard allowNavigation() else { return }
        if selectedObject == object { tab = .data; return }
        selectedObject = object; schemaMetadata = nil; structureError = nil; appliedCondition = ""; condition = ""; page = 0; sortColumn = nil; rowSearch = ""; tab = .data
        await refresh()
    }

    @discardableResult func refresh(reloadObjects: Bool = false) async -> Bool {
        guard !hasChanges, !busy else { return false }
        busy = true; status = String(localized: "读取数据…")
        defer { busy = false }
        do {
            if reloadObjects { objects = try await engine.objects() }
            if let selectedObject {
                let estimateSQL = active?.kind == .mongodb ? "{\"find\": " + (try jsonText(selectedObject.name)) + ", \"filter\": " + (appliedCondition.isEmpty ? "{}" : appliedCondition) + "}" : "SELECT * FROM " + selectedObject.qualifiedName + (appliedCondition.isEmpty ? "" : " WHERE (" + appliedCondition + ")")
                let estimate = await engine.estimate(estimateSQL)
                browseEstimate = estimate
                if estimate.severity == .large || estimate.severity == .excessive {
                    guard await confirmEstimate(estimate) else { status = String(localized: "已取消"); return false }
                }
                result = try await engine.browse(selectedObject, page: page, sort: sortColumn, ascending: sortAscending, condition: appliedCondition)
                selectRow(result.rows.first?.id)
            }
            status = String(localized: "已刷新")
            return true
        } catch { result = QueryResult(); selectedRowID = nil; report(error); return false }
    }

    func selectRow(_ id: UUID?) {
        if hasChanges, id != selectedRowID { error = String(localized: "请先保存或撤销当前记录的修改。"); return }
        selectedRowID = id
        selectedRowIDs = id.map { [$0] } ?? []
        if UserDefaults.standard.bool(forKey: "openInspectorOnSelection") && id != nil { showInspector = true }
        draft = selectedRow?.cells ?? []
        documentDraft = selectedRow?.document ?? ""
    }

    func discard() { draft = selectedRow?.cells ?? []; documentDraft = selectedRow?.document ?? "" }

    // SwiftUI can retain a field binding after its record has left the inspector.
    // Resolve against the captured record before touching the current draft.
    func fieldBinding(row: DataRow, index: Int, column: ColumnInfo) -> Binding<CellValue> {
        let original = row.cells.indices.contains(index) ? row.cells[index] : .null
        let connectionID = active?.id
        let object = selectedObject
        func isCurrent() -> Bool {
            active?.id == connectionID && selectedObject == object && selectedRow?.id == row.id
                && draft.indices.contains(index) && result.columns.indices.contains(index)
                && result.columns[index].name == column.name
        }
        return Binding(get: {
            isCurrent() ? self.draft[index] : original
        }, set: { value in
            guard isCurrent(), !self.busy, self.tab == .data, self.canEdit,
                  self.result.columns[index].isEditable, !self.result.columns[index].isPrimaryKey else { return }
            if case .blob = original { return }
            self.draft[index] = value
        })
    }

    func documentBinding(row: DataRow) -> Binding<String> {
        let connectionID = active?.id
        let object = selectedObject
        func isCurrent() -> Bool {
            active?.id == connectionID && selectedObject == object && selectedRow?.id == row.id
        }
        return Binding(get: {
            isCurrent() ? self.documentDraft : (row.document ?? "")
        }, set: { value in
            guard isCurrent(), !self.busy, self.tab == .data, self.canEdit,
                  self.active?.kind == .mongodb else { return }
            self.documentDraft = value
        })
    }

    func saveRow() async {
        guard !busy, canEdit, let selectedObject, let selectedRow else { return }
        busy = true; status = String(localized: "保存中…")
        do {
            try await engine.update(selectedObject, columns: result.columns, original: selectedRow, values: draft, document: documentDraft)
            discard(); busy = false
            status = await refresh() ? String(localized: "修改已保存") : String(localized: "修改已保存，但刷新失败；请勿重复提交")
        } catch { busy = false; report(error) }
    }

    func insert(fields: [(String, CellValue)], document: String?) async -> Bool {
        guard !readOnly, !busy, let selectedObject else { return false }
        busy = true
        do {
            try await engine.insert(selectedObject, fields: fields, document: document)
            busy = false; status = await refresh() ? String(localized: "记录已添加") : String(localized: "记录已添加，但刷新失败；请勿重复提交"); return true
        } catch { busy = false; report(error); return false }
    }

    func editCell(rowID: UUID, column: Int) {
        if readOnly { readOnlyNotice = true; return }
        guard !busy, canEdit, result.columns.indices.contains(column), result.columns[column].isEditable, !result.columns[column].isPrimaryKey else { return }
        selectRow(rowID)
        guard selectedRowID == rowID, let row = selectedRow, row.cells.indices.contains(column) else { return }
        if case .blob = row.cells[column] { return }
        editingCellIndex = column; showCellEditor = true
    }
    func selectRows(_ ids: Set<UUID>) {
        if hasChanges && !ids.contains(selectedRowID ?? UUID()) { return }
        let primary = selectedRowID.flatMap { ids.contains($0) ? $0 : nil } ?? result.rows.first(where: { ids.contains($0.id) })?.id
        selectRow(primary); selectedRowIDs = ids
    }
    func deleteRow() async {
        guard !busy, canEdit, let selectedObject else { return }
        let rows = result.rows.filter { selectedRowIDs.contains($0.id) || (selectedRowIDs.isEmpty && $0.id == selectedRowID) }
        busy = true; var deleted = 0
        do {
            for row in rows { try await engine.delete(selectedObject, columns: result.columns, row: row); deleted += 1 }
            discard(); busy = false; _ = await refresh()
            status = String(localized: "已删除记录数：") + String(deleted)
        } catch {
            busy = false
            report(DatabaseFailure(String(localized: "已删除记录数：") + String(deleted) + "\n" + error.localizedDescription))
        }
    }
    func applyCondition() async {
        guard allowNavigation() else { return }
        let alert = NSAlert(); alert.messageText = String(localized: "执行条件筛选？")
        alert.informativeText = active?.kind == .mongodb ? condition : "WHERE " + condition
        alert.addButton(withTitle: String(localized: "取消")); alert.addButton(withTitle: String(localized: "执行"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        appliedCondition = condition; page = 0; _ = await refresh()
    }
    func confirmEstimate(_ estimate: QueryEstimate) async -> Bool {
        let alert = NSAlert(); alert.messageText = String(localized: "执行前规模预估")
        alert.informativeText = estimate.summary + "\n" + String(estimate.details.prefix(900))
        alert.alertStyle = estimate.severity == .excessive ? .critical : .warning
        alert.addButton(withTitle: String(localized: "取消")); alert.addButton(withTitle: String(localized: "继续执行"))
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "workspace" }) ?? NSApp.windows.first(where: { $0.isVisible }) else { return false }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0 == .alertSecondButtonReturn) }
        }
    }

    var openScripts: [SavedScript] { scripts.scripts.filter { $0.connectionID == active?.id && $0.isOpen } }
    func openScript(_ id: UUID) {
        guard allowNavigation(), scripts.scripts.first(where: { $0.id == id })?.connectionID == active?.id else { return }
        do {
            let text = try scripts.open(id)
            selectedScriptID = nil; query = text; selectedScriptID = id
            querySelection = NSRange(location: 0, length: 0); tab = .query
            statementResults = []; queryResult = QueryResult(); queryHasRun = false; queryFailure = nil
        } catch { report(error) }
    }
    func nameScript(_ id: UUID? = nil) {
        guard allowNavigation() else { return }
        renamingScriptID = id; scriptName = scripts.scripts.first(where: { $0.id == id })?.name ?? ""; showScriptName = true
    }
    func saveScriptName() {
        guard let active else { return }
        do {
            if let id = renamingScriptID { try scripts.rename(id, name: scriptName) }
            else { let id = try scripts.create(name: scriptName, connectionID: active.id); openScript(id) }
            showScriptName = false
        } catch { report(error) }
    }
    func runQuery(approved: Bool = false) async {
        guard allowNavigation(), let active else { return }
        let source = query as NSString
        let selected = querySelection.length > 0 && NSMaxRange(querySelection) <= source.length ? source.substring(with: querySelection) : query
        let sql = approved ? pendingQuery ?? selected : selected
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; status = String(localized: "执行查询…")
        defer { busy = false }
        do {
            let isPostgres = active.kind == .postgresql
            var statements: [String] = []
            var remaining = sql
            if isPostgres {
                let standardStrings = try await engine.postgreSQLStandardConformingStrings()
                guard let first = try SQLScript.nextPostgreSQLStatement(sql, standardConformingStrings: standardStrings) else { return }
                statements = [first.statement]
                if !approved {
                    estimates = [await engine.estimate(first.statement)]
                    if !first.remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        estimates.append(QueryEstimate(severity: .unknown, summary: String(localized: "后续语句规模未知；先前语句可能改变对象或会话设置，将按执行时状态逐条解析。")))
                    }
                }
            } else {
                statements = try SQLScript.statements(sql, kind: active.kind)
                if !approved {
                    estimates = []
                    for statement in statements { estimates.append(await engine.estimate(statement)) }
                }
            }
            if !approved && estimates.contains(where: { $0.severity != .normal }) { pendingQuery = sql; showQueryApproval = true; return }
            pendingQuery = nil; queryFailure = nil; statementResults = []; selectedResultIndex = 0
            var index = 0
            while isPostgres || index < statements.count {
                var statement = remaining
                do {
                    if isPostgres {
                        let standardStrings = try await engine.postgreSQLStandardConformingStrings()
                        guard let next = try SQLScript.nextPostgreSQLStatement(remaining, standardConformingStrings: standardStrings) else { break }
                        statement = next.statement; remaining = next.remainder
                    } else {
                        statement = statements[index]; index += 1
                    }
                    let result = try await engine.run(statement, readOnly: readOnly)
                    statementResults.append(StatementResult(statement: statement, result: result))
                } catch {
                    statementResults.append(StatementResult(statement: statement, failure: error.localizedDescription))
                    queryFailure = error.localizedDescription; break
                }
            }
            queryResult = statementResults.first?.result ?? QueryResult(); queryHasRun = !statementResults.isEmpty; rowSearch = ""
            if selectedScriptID == nil {
                let id = try scripts.create(name: String(localized: "查询") + " " + Date().formatted(date: .omitted, time: .shortened), connectionID: active.id, text: query)
                selectedScriptID = id
            }
            objects = try await engine.objects()
            status = queryFailure == nil ? String(localized: "查询完成") : String(localized: "执行失败，后续语句未运行；先前自动提交的写入不会回滚。")
        } catch { queryFailure = error.localizedDescription; status = String(localized: "操作未完成") }
    }

    func changePage(_ delta: Int) async { guard allowNavigation() else { return }; page = max(0, page + delta); await refresh() }
    func sort(by column: String) async {
        guard allowNavigation(), tab == .data else { return }
        sortAscending = sortColumn == column ? !sortAscending : true
        sortColumn = column; page = 0; await refresh()
    }

    func saveConnection(_ profile: ConnectionProfile, secret: String) throws {
        guard !profile.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw DatabaseFailure(String(localized: "请填写连接名称。")) }
        if profile.kind != .sqlite { try ConnectionVault.save(secret, id: profile.id) }
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) { updated[index] = profile } else { updated.insert(profile, at: 0) }
        try LocalWorkspace.saveProfiles(updated)
        profiles = updated
    }

    func removeConnection(_ profile: ConnectionProfile) async {
        guard allowNavigation() else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = profiles.filter { $0.id != profile.id }
            if profile.kind != .sqlite { try ConnectionVault.remove(id: profile.id) }
            try LocalWorkspace.saveProfiles(updated); profiles = updated
            if active?.id == profile.id {
                await shell.stop(); shellEntries = []; shellHistory = []; shellInput = ""; shellDatabase = ""
                await engine.disconnect(); queryEditorViews.removeAll(); active = nil; objects = []; result = QueryResult(); selectedObject = nil; selectedRowID = nil
                queryResult = QueryResult(); queryHasRun = false; queryHistory = []; query = ""; draft = []; documentDraft = ""
                replicaSnapshot = nil; replicaError = nil; status = String(localized: "连接已移除")
            }
        } catch { report(error) }
    }

    func refreshReplica() async {
        guard let active, active.kind == .mongodb, !replicaLoading, !busy else { return }
        replicaLoading = true
        defer { replicaLoading = false }
        do {
            let snapshot = try await engine.replicaSetStatus()
            guard self.active?.id == active.id else { return }
            replicaSnapshot = snapshot; replicaError = nil
        } catch { if self.active?.id == active.id { replicaError = error.localizedDescription } }
    }

    func runShell() async {
        guard allowNavigation(), let active, active.kind == .mongodb else { return }
        guard !readOnly else { readOnlyNotice = true; return }
        guard await confirmEstimate(QueryEstimate(severity: .unknown, summary: String(localized: "Shell 可运行任意 JavaScript，无法在不执行的情况下可靠预估；请确认范围。"))) else { return }
        let command = shellInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        if command == "clear" || command == "cls" { shellEntries = []; shellInput = ""; return }
        let entry = ShellEntry(command: command, database: shellDatabase.isEmpty ? active.database : shellDatabase)
        shellEntries.append(entry); shellEntries = Array(shellEntries.suffix(100))
        shellHistory.append(command); shellHistory = Array(shellHistory.suffix(100)); shellHistoryIndex = shellHistory.count
        shellInput = ""; busy = true; shellRunning = true; status = String(localized: "Shell 运行中…")
        defer { busy = false; shellRunning = false }
        do {
            let secret = try ConnectionVault.read(id: active.id)
            let reply = try await shell.execute(command, profile: active, secret: secret)
            guard let index = shellEntries.firstIndex(where: { $0.id == entry.id }) else { return }
            shellEntries[index].output = reply.output ?? reply.error ?? ""
            shellEntries[index].failed = !reply.ok
            shellDatabase = reply.database ?? shellDatabase
            status = reply.ok ? String(localized: "Shell 执行完成") : String(localized: "Shell 命令失败")
        } catch {
            if let index = shellEntries.firstIndex(where: { $0.id == entry.id }) { shellEntries[index].output = error.localizedDescription; shellEntries[index].failed = true }
            status = String(localized: "Shell 已停止")
        }
    }
    func navigateShellHistory(_ offset: Int) {
        shellHistoryIndex = min(shellHistory.count, max(0, shellHistoryIndex + offset))
        shellInput = shellHistoryIndex < shellHistory.count ? shellHistory[shellHistoryIndex] : ""
    }
    func resetShell() async { guard !shellRunning else { return }; await shell.stop(); shellEntries = []; shellDatabase = active?.database ?? "" }

    func bindAutomaticActions() {
        for session in agentLibrary.sessions {
            session.onAutomaticActions = { [weak self, weak session] ids, requiresReadOnly in
                Task { @MainActor in
                    guard let self, let session else { return }
                    for id in ids { await self.executeAgentAction(id, in: session, requiresReadOnly: requiresReadOnly, automatic: true) }
                }
            }
        }
    }
    func executeAgentAction(_ id: String, in session: AgentSession, requiresReadOnly: Bool = false, automatic: Bool = false) async {
        guard canExecuteAgent(session), allowNavigation(), let profile = active,
              let proposed = session.actions.first(where: { $0.id == id }), proposed.state == .awaitingApproval else { return }
        // Planning uses the workbench connection; execution owns an independent connection.
        do {
            busy = true
            defer { busy = false }
            if let query = proposed.query {
                let estimate = await engine.estimate(query)
                if let index = session.actions.firstIndex(where: { $0.id == id }) { session.actions[index].executionEstimate = estimate.summary + "\n" + estimate.details }
                if estimate.severity != .normal {
                    if automatic && requiresReadOnly { return } // Await manual review when automatic read planning is uncertain/large.
                    if !automatic { guard await confirmEstimate(estimate) else { return } }
                }
            }
        }
        guard let action = session.beginExecution(id, connectionID: profile.id) else { return }
        let object = selectedObject
        do {
            let output = try await agentExecution(session.id, action, profile, object, readOnly || requiresReadOnly)
            session.resolve(id, output: output, failed: false)
        } catch { session.resolve(id, output: String(localized: "操作失败：") + error.localizedDescription, failed: true) }
    }
    func loadStructure() async {
        guard let object = selectedObject, let active else { return }
        structureLoading = true; structureError = nil; schemaMetadata = nil
        defer { structureLoading = false }
        do {
            let metadata = try await engine.schemaMetadata(for: object)
            guard self.active?.id == active.id && selectedObject == object else { return }
            schemaMetadata = metadata
        } catch { if self.active?.id == active.id && selectedObject == object { structureError = error.localizedDescription } }
    }
    func loadRelationships() async {
        guard let active, !relationshipLoading else { return }
        relationshipLoading = true; relationshipError = nil
        defer { relationshipLoading = false }
        do {
            let value = try await engine.relationships(for: objects)
            guard self.active?.id == active.id else { return }; relationships = value
        } catch { if self.active?.id == active.id { relationshipError = error.localizedDescription } }
    }

    func exportCSV() { exportResult(.csv) }
    func exportResult(_ format: ResultExportFormat, dialect: ResultSQLDialect = .sqlite) {
        var exported = displayedResult
        exported.rows = visibleRows
        guard !exported.columns.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = (selectedObject?.name ?? "query") + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try ResultExporter(format: format, sourceKind: active?.kind ?? .sqlite, sqlDialect: dialect, table: selectedObject ?? DatabaseObject(name: "query_result")).encode(exported)
            try text.write(to: url, atomically: true, encoding: .utf8)
            status = String(localized: "已导出当前结果 · \(exported.rows.count) 行")
        } catch { report(error) }
    }
}
