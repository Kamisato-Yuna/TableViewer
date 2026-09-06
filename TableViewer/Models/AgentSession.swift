import Foundation
import Observation

@MainActor @Observable final class AgentSession {
    var configuration = AgentConfiguration.load()
    var input = ""
    var messages: [AgentMessage] = []
    var actions: [AgentAction] = []
    var streamingText = ""
    var running = false
    var error: String?
    var shareSchema = false
    var showSettings = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private let client = OpenAICompatibleClient()

    var ready: Bool { !configuration.baseURL.isEmpty && !configuration.model.isEmpty }
    var canContinue: Bool { !actions.isEmpty && actions.allSatisfy { $0.outcome != nil } && !running }
    func reset() {
        generation += 1; task?.cancel(); task = nil
        messages = []; actions = []; streamingText = ""; running = false; error = nil
    }
    func stop() { generation += 1; task?.cancel(); task = nil; running = false; streamingText = ""; error = String(localized: "已停止生成，未执行新的数据库操作。") }

    func send(context: AgentContext) {
        guard !running, actions.isEmpty else { return }
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if !ready { showSettings = true; return }
        messages.append(AgentMessage(role: "user", content: prompt)); input = ""
        request(context: context)
    }
    func continueWithResults(context: AgentContext) {
        guard canContinue, actions.allSatisfy({ $0.connectionID == context.connectionID }) else { return }
        for action in actions { messages.append(AgentMessage(role: "tool", content: action.outcome ?? String(localized: "用户拒绝执行。"), toolCallID: action.id)) }
        actions = []
        request(context: context)
    }
    func reject(_ id: String) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].outcome == nil else { return }
        actions[index].outcome = String(localized: "用户拒绝此操作。未执行查询。")
    }
    func retry(context: AgentContext) { guard !running, actions.isEmpty, !messages.isEmpty else { return }; request(context: context) }
    func resolve(_ id: String, output: String, failed: Bool) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].outcome == nil else { return }
        actions[index].outcome = String(output.prefix(24_000)) + (output.count > 24_000 ? String(localized: "\n…结果已截断。") : "")
        actions[index].failed = failed
    }

    private func appendDelta(_ text: String, generation: Int) {
        guard self.generation == generation else { return }
        streamingText += text
    }

    private func request(context: AgentContext) {
        running = true; streamingText = ""; error = nil
        let current = generation, configuration = configuration, messages = messages
        task = Task { [weak self, client] in
            do {
                let key = try ConnectionVault.read(id: AgentConfiguration.secretID)
                let message = try await client.complete(configuration: configuration, key: key, messages: messages, context: context) { [weak self] delta in
                    await self?.appendDelta(delta, generation: current)
                }
                guard let self, generation == current, !Task.isCancelled else { return }
                self.messages.append(message)
                self.actions = (message.toolCalls ?? []).map { AgentAction(call: $0, connectionID: context.connectionID, connectionName: context.connectionName) }
                streamingText = ""; running = false
            } catch {
                guard let self, generation == current else { return }
                self.error = error is CancellationError ? String(localized: "已停止生成。") : error.localizedDescription
                streamingText = ""; running = false
            }
        }
    }
}
