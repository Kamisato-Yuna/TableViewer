import Foundation
import Observation

// Local storage is separate from the provider wire representation, whose IDs/status are omitted.
struct StoredAgentMessage: Codable {
    var id: UUID
    var message: AgentMessage
    var delivery: AgentDelivery
    var usage: AgentTokenUsage?
    init(_ message: AgentMessage) { id = message.id; self.message = message; delivery = message.delivery; usage = message.usage }
    var restored: AgentMessage { var value = message; value.id = id; value.delivery = delivery; value.usage = usage; return value }
}
struct StoredAgentSession: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastInputAt: Date?
    var archived: Bool
    var connection: AgentContext?
    var configuration: AgentConfiguration
    var input: String
    var shareSchema: Bool
    var approvalMode: AgentApprovalMode?
    var automaticResultsConfiguration: AgentConfiguration?
    var messages: [StoredAgentMessage]
    var actions: [AgentAction]
    var error: String?
    var responseID: UUID?
    var requestHistory: [StoredAgentMessage]
    var requestContext: AgentContext?
    @MainActor init(_ session: AgentSession) {
        id = session.id; title = session.title; createdAt = session.createdAt; updatedAt = session.updatedAt
        lastInputAt = session.historyDate
        archived = session.archived; connection = session.connection; configuration = session.configuration
        input = session.input; shareSchema = session.shareSchema; approvalMode = session.approvalMode; messages = session.messages.map(StoredAgentMessage.init)
        automaticResultsConfiguration = session.automaticResultsConfiguration
        actions = session.actions; error = session.error; responseID = session.responseID
        requestHistory = session.requestHistory.map(StoredAgentMessage.init); requestContext = session.requestContext
    }
    @MainActor func restore() -> AgentSession {
        let session = AgentSession(id: id)
        session.title = title; session.createdAt = createdAt; session.archived = archived
        session.connection = connection; session.configuration = configuration; session.input = input; session.shareSchema = shareSchema
        session.approvalMode = approvalMode ?? .manual
        session.automaticResultsConfiguration = automaticResultsConfiguration
        session.messages = messages.map { stored in
            var message = stored.restored
            if message.delivery == .generating { message.delivery = .interrupted }
            return message
        }
        session.actions = actions.map { stored in
            var action = stored
            if action.state == .executing {
                action.state = .uncertain
                action.outcome = (action.outcome.map { $0 + "\n" } ?? "") + String(localized: "应用已退出，无法确认这次操作是否完成。请核实数据库状态；不会自动重执行。")
            }
            return action
        }
        session.error = error; session.responseID = responseID
        session.requestHistory = requestHistory.map(\.restored); session.requestContext = requestContext
        session.updatedAt = updatedAt
        // Older histories have no input timestamp; preserve their existing order.
        session.lastInputAt = lastInputAt ?? updatedAt
        return session
    }
}

@MainActor @Observable final class AgentLibrary {
    private(set) var sessions: [AgentSession] = []
    var selectedID: UUID? { didSet { save() } }
    var persistenceError: String?
    private var savingTask: Task<Void, Never>?
    private var canWrite = true
    private let file: URL
    private struct Archive: Codable { var selectedID: UUID?; var sessions: [StoredAgentSession] }
    init(file: URL = LocalWorkspace.directory.appendingPathComponent("agent-conversations.json")) {
        self.file = file
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                sessions = archive.sessions.map { $0.restore() }
                selectedID = archive.selectedID
            }
            sessions.forEach(observe)
        } catch {
            canWrite = false // Preserve the unreadable original file instead of replacing it with an empty history.
            persistenceError = String(localized: "会话历史读取失败，原文件已保留：") + error.localizedDescription
        }
    }
    var selected: AgentSession? { sessions.first { $0.id == selectedID } }
    var workingCount: Int { sessions.filter { $0.running || $0.actions.contains { $0.state == .executing } }.count }
    var needsAttentionCount: Int { sessions.filter { !$0.pendingActions.isEmpty }.count }
    @discardableResult func create(context: AgentContext, configuration: AgentConfiguration = .load()) -> AgentSession {
        let session = AgentSession(); session.connection = AgentContext(connectionID: context.connectionID, connectionName: context.connectionName, kind: context.kind)
        session.configuration = configuration; add(session); return session
    }
    // Also used by the deterministic state/IO tests; normal UI sessions use create(context:).
    func add(_ session: AgentSession) { sessions.insert(session, at: 0); observe(session); selectedID = session.id }
    func open(_ id: UUID) {
        if sessions.contains(where: { $0.id == id }) {
            selectedID = id
        }
    }
    func rename(_ session: AgentSession, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { session.title = String(title.prefix(120)) }
    }
    func archive(_ session: AgentSession, archived: Bool) { session.archived = archived }
    func matching(_ query: String, archived: Bool) -> [AgentSession] {
        sessions.filter { $0.archived == archived && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.connection?.connectionName.localizedCaseInsensitiveContains(query) ?? false)) }
            .sorted { ($0.historyDate, $0.id.uuidString) > ($1.historyDate, $1.id.uuidString) }
    }
    private func observe(_ session: AgentSession) {
        session.onChange = { [weak self] immediate in
            guard let self else { return }
            if immediate { save() }
            else if savingTask == nil {
                savingTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    self?.save()
                }
            }
        }
    }
    func save() {
        savingTask?.cancel(); savingTask = nil
        guard canWrite else { return }
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Archive(selectedID: selectedID, sessions: sessions.map(StoredAgentSession.init)))
            // Follow the existing workspace atomic-file storage pattern.
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            persistenceError = nil
        } catch { persistenceError = String(localized: "会话历史保存失败：") + error.localizedDescription }
    }
}
