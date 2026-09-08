import Foundation
import Observation

@MainActor @Observable final class AgentSession: Identifiable {
    nonisolated let id: UUID
    var title = String(localized: "新会话") { didSet { changed(true) } }
    var createdAt = Date()
    var updatedAt = Date()
    var lastInputAt: Date?
    var historyDate: Date { lastInputAt ?? createdAt }
    var archived = false { didSet { changed(true) } }
    var connection: AgentContext?
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    private func changed(_ immediate: Bool = false) { updatedAt = Date(); onChange?(immediate) }
    typealias Completion = @Sendable (AgentConfiguration, [AgentMessage], AgentContext, @escaping @Sendable (String) async -> Void) async throws -> AgentMessage
    var configuration = AgentConfiguration.load()
    var input = "" { didSet { changed(false) } }
    var messages: [AgentMessage] = [] {
        didSet {
            if messages.contains(where: { message in message.role == "user" && !oldValue.contains(where: { $0.id == message.id }) }) {
                lastInputAt = Date()
            }
            changed(false)
        }
    }
    var actions: [AgentAction] = [] { didSet { changed(true) } }
    var running = false { didSet { changed(true) } }
    var error: String? { didSet { changed(true) } }
    var shareSchema = false { didSet { changed(true) } }
    var showSettings = false
    var approvalMode: AgentApprovalMode = .manual { didSet { changed(true) } }
    /// Called only for freshly generated actions; restoring a session never executes history.
    @ObservationIgnored var onAutomaticActions: (([String], Bool) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = 0
    var responseID: UUID?
    private var responseFallback: String?
    var requestHistory: [AgentMessage] = []
    var requestContext: AgentContext?
    private let complete: Completion

    private let checksProviderConfiguration: Bool
    init(id: UUID = UUID(), complete: Completion? = nil) {
        self.id = id
        checksProviderConfiguration = complete == nil
        self.complete = complete ?? { configuration, messages, context, onDelta in
            let key = try ConnectionVault.read(id: AgentConfiguration.secretID)
            return try await OpenAICompatibleClient().complete(configuration: configuration, key: key, messages: messages, context: context, onDelta: onDelta)
        }
    }
    var providerMatches: Bool { !checksProviderConfiguration || configuration == AgentConfiguration.load() }

    var ready: Bool { !configuration.baseURL.isEmpty && !configuration.model.isEmpty }
    var pendingActions: [AgentAction] { actions.filter { !$0.shared } }
    var canContinue: Bool { providerMatches && !archived && !pendingActions.isEmpty && pendingActions.allSatisfy { $0.outcome != nil } && !running }
    var canRetry: Bool { providerMatches && !archived && !running && pendingActions.isEmpty && messages.last?.id == responseID && [.stopped, .failed, .interrupted].contains(messages.last?.delivery) }
    var canSend: Bool { providerMatches && !archived && pendingActions.isEmpty && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var quickReplies: [String] {
        guard !running, !archived, providerMatches, pendingActions.isEmpty,
              let message = messages.last, message.role == "assistant", message.delivery == .complete,
              message.toolCalls?.isEmpty != false else { return [] }
        return AgentQuickReply.options(in: message.content ?? "")
    }
    var phase: String {
        if running { return messages.last?.content?.isEmpty == false ? String(localized: "正在生成回复…") : String(localized: "正在准备回复…") }
        if pendingActions.contains(where: { $0.state == .executing }) { return String(localized: "正在执行已批准的操作…") }
        if pendingActions.contains(where: { $0.question != nil && $0.outcome == nil }) { return String(localized: "等待你回答问题") }
        if pendingActions.contains(where: { $0.outcome == nil }) { return String(localized: "等待你批准或拒绝操作") }
        if pendingActions.contains(where: { $0.state == .uncertain }) { return String(localized: "结果待核实 · 不会自动重执行") }
        if !pendingActions.isEmpty && pendingActions.allSatisfy({ $0.outcome != nil }) { return String(localized: "等待你确认发送结果") }
        if messages.last?.delivery == .interrupted { return String(localized: "生成已中断 · 可手动继续") }
        return ""
    }
    func reset() {
        generation += 1; task?.cancel(); task = nil
        messages = []; actions = []; running = false; error = nil
        responseID = nil; responseFallback = nil; requestHistory = []; requestContext = nil
    }
    func stop() {
        guard running else { return }
        generation += 1; task?.cancel(); task = nil; running = false
        if let index = messages.firstIndex(where: { $0.id == responseID }) {
            if messages[index].content?.isEmpty != false { messages[index].content = responseFallback ?? "" }
            messages[index].delivery = .stopped
        }
        error = nil
    }
    func send(context: AgentContext) {
        guard canSend, connection == nil || connection?.connectionID == context.connectionID else { return }
        if connection == nil { connection = AgentContext(connectionID: context.connectionID, connectionName: context.connectionName, kind: context.kind) }
        if !ready { showSettings = true; return }
        // A supplement stops the old HTTP request and starts a new request with its visible partial answer.
        if running { stop() }
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if messages.isEmpty { title = String(prompt.prefix(48)) }
        messages.append(AgentMessage(role: "user", content: prompt)); input = ""
        start(context: context, history: messages)
    }
    @discardableResult func reply(with option: String, to messageID: UUID, context: AgentContext) -> Bool {
        guard messages.last?.id == messageID, quickReplies.contains(option), ready,
              connection == nil || connection?.connectionID == context.connectionID else { return false }
        // Quick replies use the ordinary user-message path, without consuming a composed draft.
        let draft = input
        input = option
        send(context: context)
        input = draft
        return true
    }
    func continueReply(context: AgentContext) {
        guard canRetry, requestContext?.connectionID == context.connectionID else { return }
        messages.append(AgentMessage(role: "user", content: String(localized: "请接着上面的未完成回复继续，避免重复已有内容。")))
        start(context: context, history: messages)
    }
    func continueWithResults(context: AgentContext) {
        guard canContinue, pendingActions.allSatisfy({ $0.connectionID == context.connectionID }) else { return }
        for index in actions.indices where !actions[index].shared {
            messages.append(AgentMessage(role: "tool", content: actions[index].outcome, toolCallID: actions[index].call.id))
            actions[index].shared = true
        }
        start(context: context, history: messages)
    }
    func reject(_ id: String) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].state == .awaitingApproval else { return }
        actions[index].outcome = String(localized: "用户拒绝此操作。未执行查询。")
        actions[index].state = .rejected
    }
    func setAnswerDraft(_ id: String, text: String) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].state == .awaitingApproval else { return }
        actions[index].draftAnswer = text
    }
    func restoreQuestion(_ id: String) {
        guard !archived, !running, let index = actions.firstIndex(where: { $0.id == id }), actions[index].canRestoreQuestion else { return }
        actions[index].outcome = nil
        actions[index].state = .awaitingApproval
    }
    func canReaskQuestion(_ id: String) -> Bool {
        canContinue && pendingActions.count == 1 && pendingActions[0].id == id && pendingActions[0].state == .failed &&
            pendingActions[0].call.function.name == "ask_user" && pendingActions[0].question == nil
    }
    func reaskQuestion(_ id: String, context: AgentContext) {
        guard canReaskQuestion(id) else { return }
        // Only this failed question is shared. Never include another action's local result in a retry.
        continueWithResults(context: context)
    }
    func answer(_ id: String, text: String) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, let index = actions.firstIndex(where: { $0.id == id }), actions[index].question != nil, actions[index].state == .awaitingApproval else { return }
        actions[index].outcome = String(answer.prefix(24_000))
        actions[index].state = .completed
    }
    func beginExecution(_ id: String, connectionID: UUID) -> AgentAction? {
        guard !archived, !actions.contains(where: { $0.state == .executing }), let index = actions.firstIndex(where: { $0.id == id }), actions[index].connectionID == connectionID,
              actions[index].state == .awaitingApproval, actions[index].call.function.name != "ask_user" else { return nil }
        actions[index].state = .executing
        return actions[index]
    }
    func resolve(_ id: String, output: String, failed: Bool) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].state == .executing else { return }
        actions[index].outcome = String(output.prefix(24_000)) + (output.count > 24_000 ? String(localized: "\n…结果已截断。") : "")
        actions[index].state = failed ? .failed : .completed
    }
    func retry(context: AgentContext) {
        guard canRetry, let original = requestContext, original.connectionID == context.connectionID, let id = responseID else { return }
        // Reuse the original prompt snapshot (including already shared tool results), never add another user turn.
        start(context: original, history: requestHistory, replacing: id)
    }
    private func appendDelta(_ text: String, generation: Int, id: UUID) {
        guard self.generation == generation, running, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = (messages[index].content ?? "") + text
    }
    private func start(context: AgentContext, history: [AgentMessage], replacing: UUID? = nil) {
        generation += 1
        let current = generation
        let id = replacing ?? UUID()
        let previous = messages.first(where: { $0.id == id })?.content
        let placeholder = AgentMessage(id: id, role: "assistant", content: "", delivery: .generating)
        if let index = messages.firstIndex(where: { $0.id == id }) { messages[index] = placeholder }
        else { messages.append(placeholder) }
        let history = history.filter { $0.role != "assistant" || $0.content?.isEmpty == false || $0.toolCalls?.isEmpty == false }
        responseFallback = previous
        responseID = id; requestHistory = history; requestContext = context
        running = true; error = nil
        let configuration = configuration
        task = Task { [weak self, complete] in
            do {
                try Task.checkCancellation()
                var message = try await complete(configuration, history, context) { [weak self] delta in
                    await self?.appendDelta(delta, generation: current, id: id)
                }
                guard let self, generation == current, !Task.isCancelled, let index = messages.firstIndex(where: { $0.id == id }) else { return }
                message.id = id; message.delivery = .complete; messages[index] = message
                let newActions = (message.toolCalls ?? []).map {
                    var action = AgentAction(call: $0, messageID: id, connectionID: context.connectionID, connectionName: context.connectionName)
                    if $0.function.name == "ask_user", let failure = AgentQuestion.validationFailure($0.function.arguments) {
                        action.state = .failed; action.outcome = failure
                    }
                    return action
                }
                actions += newActions
                running = false; task = nil
                let automatic = newActions.filter { self.approvalMode.permitsAutomaticExecution($0, kind: context.kind) }.map(\.id)
                if !automatic.isEmpty { onAutomaticActions?(automatic, approvalMode == .sensitiveOnly) }
            } catch {
                guard let self, generation == current, let index = messages.firstIndex(where: { $0.id == id }) else { return }
                if messages[index].content?.isEmpty != false { messages[index].content = previous ?? "" }
                messages[index].delivery = error is CancellationError ? .stopped : .failed
                self.error = error is CancellationError ? nil : error.localizedDescription
                running = false; task = nil
            }
        }
    }
}
