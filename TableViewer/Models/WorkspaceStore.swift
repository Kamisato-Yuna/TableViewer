import SwiftUI
import Observation
import UniformTypeIdentifiers

enum WorkspaceTab: String, CaseIterable {
    case data = "数据", structure = "结构", query = "查询", replica = "副本集", shell = "终端", agent = "Agent"
    var title: String {
        switch self {
        case .data: String(localized: "数据")
        case .structure: String(localized: "结构")
        case .query: String(localized: "查询")
        case .replica: String(localized: "副本集")
        case .shell: String(localized: "终端")
        case .agent: "Agent"
        }
    }
    static let basic: [Self] = [.data, .structure, .query]
    var symbol: String { switch self { case .data: "tablecells"; case .structure: "square.stack.3d.up"; case .query: "chevron.left.forwardslash.chevron.right"; case .replica: "point.3.connected.trianglepath.dotted"; case .shell: "terminal"; case .agent: "sparkles" } }
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
    var result = QueryResult()
    var selectedRowID: UUID?
    var draft: [CellValue] = []
    var documentDraft = ""
    var objectSearch = ""
    var rowSearch = ""
    var tab = WorkspaceTab.data
    var query = "SELECT * FROM projects\nWHERE status = '进行中'\nORDER BY updated_at DESC;"
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
    var showInspector = true
    var showInsert = false
    var showDelete = false
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
    let agent = AgentSession()

    var agentContext: AgentContext? {
        active.map { AgentContext(connectionID: $0.id, connectionName: $0.name, kind: $0.kind, schema: agent.shareSchema ? schemaDescription : nil) }
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
        if busy { return String(localized: "数据库操作仍在进行。退出不会撤销已完成的写入；未提交的 SQL 事务会在连接关闭后回滚。") }
        if hasChanges { return String(localized: "当前记录有未保存的修改，退出会丢失这些修改。请取消退出后保存或撤销。") }
        return nil
    }
    var canEdit: Bool { selectedObject != nil && selectedObject?.isView == false && (active?.kind == .mongodb || result.columns.contains(where: \.isPrimaryKey)) }
    var visibleObjects: [DatabaseObject] { objectSearch.isEmpty ? objects : objects.filter { $0.name.localizedCaseInsensitiveContains(objectSearch) || $0.schema.localizedCaseInsensitiveContains(objectSearch) } }
    var displayedResult: QueryResult { tab == .query ? queryResult : result }
    var visibleRows: [DataRow] {
        let rows = displayedResult.rows
        return rowSearch.isEmpty ? rows : rows.filter { $0.cells.contains { $0.display.localizedCaseInsensitiveContains(rowSearch) } }
    }

    func start() async {
        guard !didStart else { return }; didStart = true
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
        busy = true; status = String(localized: "正在连接…")
        defer { busy = false }
        agent.reset(); await shell.stop(); shellEntries = []; shellHistory = []; shellInput = ""; shellDatabase = profile.database
        replicaSnapshot = nil; replicaError = nil
        queryResult = QueryResult(); queryHasRun = false; queryHistory = []; query = ""
        do {
            let credential = try secret ?? (profile.kind == .sqlite ? "" : ConnectionVault.read(id: profile.id))
            let loaded = try await engine.connect(profile, secret: credential)
            active = profile; objects = loaded
            selectedObject = nil; result = QueryResult(); selectedRowID = nil
            page = 0; sortColumn = nil; rowSearch = ""; objectSearch = ""; tab = .data
            queryResult = QueryResult(); queryHasRun = false; queryHistory = []
            query = profile.kind == .mongodb ? "{\n  \"find\": \"\(loaded.first?.name ?? "collection")\",\n  \"filter\": {},\n  \"limit\": 100\n}" : "SELECT * FROM \(loaded.first?.qualifiedName ?? "table_name") LIMIT 100;"
            if let first = loaded.first(where: { $0.name == "projects" }) ?? loaded.first {
                selectedObject = first
                result = try await engine.browse(first)
                selectRow(result.rows.first?.id)
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
        selectedObject = object; page = 0; sortColumn = nil; rowSearch = ""; tab = .data
        await refresh()
    }

    @discardableResult func refresh(reloadObjects: Bool = false) async -> Bool {
        guard !hasChanges, !busy else { return false }
        busy = true; status = String(localized: "读取数据…")
        defer { busy = false }
        do {
            if reloadObjects { objects = try await engine.objects() }
            if let selectedObject {
                result = try await engine.browse(selectedObject, page: page, sort: sortColumn, ascending: sortAscending)
                selectRow(result.rows.first?.id)
            }
            status = String(localized: "已刷新")
            return true
        } catch { result = QueryResult(); selectedRowID = nil; report(error); return false }
    }

    func selectRow(_ id: UUID?) {
        if hasChanges, id != selectedRowID { error = String(localized: "请先保存或撤销当前记录的修改。"); return }
        selectedRowID = id
        draft = selectedRow?.cells ?? []
        documentDraft = selectedRow?.document ?? ""
    }

    func discard() { draft = selectedRow?.cells ?? []; documentDraft = selectedRow?.document ?? "" }

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
        guard !busy, let selectedObject else { return false }
        busy = true
        do {
            try await engine.insert(selectedObject, fields: fields, document: document)
            busy = false; status = await refresh() ? String(localized: "记录已添加") : String(localized: "记录已添加，但刷新失败；请勿重复提交"); return true
        } catch { busy = false; report(error); return false }
    }

    func deleteRow() async {
        guard !busy, canEdit, let selectedObject, let selectedRow else { return }
        busy = true
        do {
            try await engine.delete(selectedObject, columns: result.columns, row: selectedRow)
            discard(); busy = false; status = await refresh() ? String(localized: "记录已删除") : String(localized: "记录已删除，但刷新失败")
        } catch { busy = false; report(error) }
    }

    func runQuery() async {
        guard allowNavigation(), active != nil, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; status = String(localized: "执行查询…")
        defer { busy = false }
        do {
            queryResult = try await engine.run(query)
            queryHasRun = true; rowSearch = ""
            if queryHistory.first != query { queryHistory.insert(query, at: 0); queryHistory = Array(queryHistory.prefix(20)) }
            objects = try await engine.objects()
            status = String(localized: "查询完成 · \(queryResult.affectedRows) 行受影响")
        } catch { queryResult = QueryResult(); queryHasRun = false; report(error) }
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
                agent.reset(); await shell.stop(); shellEntries = []; shellHistory = []; shellInput = ""; shellDatabase = ""
                await engine.disconnect(); active = nil; objects = []; result = QueryResult(); selectedObject = nil; selectedRowID = nil
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

    func executeAgentAction(_ id: String) async {
        guard allowNavigation(), let active, let action = agent.actions.first(where: { $0.id == id }), action.outcome == nil, action.connectionID == active.id else { return }
        busy = true; status = String(localized: "执行已确认的 Agent 操作…")
        defer { busy = false }
        do {
            var output: String
            switch action.call.function.name {
            case "inspect_schema":
                objects = try await engine.objects()
                output = schemaDescription
            case "execute_query":
                guard let query = action.query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DatabaseFailure(String(localized: "工具调用缺少 query。")) }
                let result = try await engine.run(query)
                let columns = result.columns.map(\.name)
                let rows: [[Any]] = result.rows.prefix(100).map { $0.cells.map { value -> Any in value.isNull ? NSNull() : value.display } }
                output = try jsonText(["columns": columns, "rows": rows, "affectedRows": result.affectedRows, "truncated": result.hasMore || result.rows.count > 100], pretty: true)
            default: throw DatabaseFailure(String(localized: "不支持模型提出的工具：\(action.call.function.name)"))
            }
            agent.resolve(id, output: output, failed: false); status = String(localized: "操作完成 · 结果仅保留在本机，待你选择是否发送")
        } catch { agent.resolve(id, output: String(localized: "操作失败：") + error.localizedDescription, failed: true); status = String(localized: "Agent 操作未完成") }
    }

    func exportCSV() {
        let result = displayedResult
        guard !result.columns.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (selectedObject?.name ?? "query") + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            func escape(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            let lines = [result.columns.map { escape($0.name) }.joined(separator: ",")] + visibleRows.map { $0.cells.map { $0.isNull ? "" : escape($0.display) }.joined(separator: ",") }
            try (lines.joined(separator: "\r\n") + "\r\n").write(to: url, atomically: true, encoding: .utf8)
            status = String(localized: "已导出当前结果 · \(visibleRows.count) 行")
        } catch { report(error) }
    }
}
