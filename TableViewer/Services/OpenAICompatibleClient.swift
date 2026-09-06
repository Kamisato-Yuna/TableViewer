import Foundation

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

// Hold partial tag prefixes across chunks so provider reasoning never flashes in the answer.
struct AgentReasoningFilter {
    private var pending = ""
    private var thinking = false
    mutating func consume(_ text: String) -> String {
        var output = ""
        let opening = ["<think>", "&lt;think&gt;"]
        let closing = ["</think>", "&lt;/think&gt;"]
        for character in text {
            pending.append(character)
            while !pending.isEmpty {
                let lower = pending.lowercased()
                let tags = opening + closing
                if let tag = tags.first(where: { lower.hasPrefix($0) }) {
                    thinking = opening.contains(tag); pending.removeFirst(tag.count)
                } else if tags.contains(where: { $0.hasPrefix(lower) }) { break }
                else {
                    let character = pending.removeFirst()
                    if !thinking { output.append(character) }
                }
            }
        }
        return output
    }

}

struct CompletionAccumulator {
    var content = ""
    var calls: [Int: AgentToolCall] = [:]
    var finished = false
    private var filter = AgentReasoningFilter()
    private var completionError: String?
    private var receivedContentBytes = 0
    mutating func consume(_ object: [String: Any]) throws -> String {
        if let error = object["error"] as? [String: Any] { throw DatabaseFailure(error["message"] as? String ?? String(localized: "API 返回错误。")) }
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return "" }
        let delta = choice["delta"] as? [String: Any] ?? choice["message"] as? [String: Any] ?? [:]
        let rawText = delta["content"] as? String ?? delta["refusal"] as? String ?? ""
        receivedContentBytes += rawText.utf8.count
        let text = filter.consume(rawText)
        content += text
        if let fragments = delta["tool_calls"] as? [[String: Any]] {
            for (offset, fragment) in fragments.enumerated() {
                let index = fragment["index"] as? Int ?? offset
                var call = calls[index] ?? AgentToolCall(id: "", function: AgentFunction(name: "", arguments: ""))
                if let id = fragment["id"] as? String { call.id += id }
                if let function = fragment["function"] as? [String: Any] {
                    call.function.name += function["name"] as? String ?? ""
                    call.function.arguments += function["arguments"] as? String ?? ""
                }
                calls[index] = call
            }
        }
        if let reason = choice["finish_reason"] as? String {
            if reason == "length" { completionError = String(localized: "模型输出达到上限，已保留部分回复；可继续或重新生成。未执行本次工具。") }
            finished = true
        }
        guard receivedContentBytes + calls.values.reduce(0, { $0 + $1.function.arguments.utf8.count }) <= 1_000_000 else { throw DatabaseFailure(String(localized: "API 返回内容过大。")) }
        return text
    }
    func message() throws -> AgentMessage {
        if let completionError { throw DatabaseFailure(completionError) }
        let ordered = calls.keys.sorted().compactMap { calls[$0] }
        guard !content.isEmpty || !ordered.isEmpty else { throw DatabaseFailure(String(localized: "模型没有返回内容或工具调用。")) }
        guard Set(ordered.map(\.id)).count == ordered.count, ordered.allSatisfy({ !$0.id.isEmpty && !$0.function.name.isEmpty && (try? jsonObject($0.function.arguments)) != nil }) else { throw DatabaseFailure(String(localized: "API 返回的工具调用不完整；未执行操作。")) }
        return AgentMessage(role: "assistant", content: content.isEmpty ? nil : content, toolCalls: ordered.isEmpty ? nil : ordered)
    }
}

final class OpenAICompatibleClient: @unchecked Sendable {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 180
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    func models(configuration: AgentConfiguration, key: String) async throws -> [String] {
        var request = URLRequest(url: try configuration.endpoint("models"))
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        try validate(response, body: data, key: key)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((object?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.sorted()
    }

    func complete(configuration: AgentConfiguration, key: String, messages: [AgentMessage], context: AgentContext, onDelta: @escaping @Sendable (String) async -> Void) async throws -> AgentMessage {
        do {
            return try await performCompletion(configuration: configuration, key: key, messages: messages, context: context, onDelta: onDelta)
        } catch is CancellationError { throw CancellationError() }
        catch {
            let message = key.isEmpty ? error.localizedDescription : error.localizedDescription.replacingOccurrences(of: key, with: "<API Key>")
            throw DatabaseFailure(String(message.prefix(1000)))
        }
    }

    private func performCompletion(configuration: AgentConfiguration, key: String, messages: [AgentMessage], context: AgentContext, onDelta: @escaping @Sendable (String) async -> Void) async throws -> AgentMessage {
        guard !configuration.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw DatabaseFailure(String(localized: "请先设置模型名称。")) }
        let encoded = try JSONEncoder().encode([AgentMessage(role: "system", content: context.instruction)] + messages)
        let body: [String: Any] = ["model": configuration.model, "messages": try JSONSerialization.jsonObject(with: encoded), "stream": configuration.streaming, "tools": Self.tools, "tool_choice": "auto"]
        var request = URLRequest(url: try configuration.endpoint("chat/completions"))
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.streaming ? "text/event-stream, application/json" : "application/json", forHTTPHeaderField: "Accept")
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count >= 4096 { break } }
            try validate(response, body: data, key: key)
            throw DatabaseFailure(String(localized: "API 请求失败。"))
        }
        var accumulator = CompletionAccumulator()
        if http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
            var event: [String] = []
            var totalBytes = 0
            var done = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                totalBytes += line.utf8.count
                guard totalBytes <= 2_000_000 else { throw DatabaseFailure(String(localized: "API 流式响应过大。")) }
                // OpenAI-compatible providers send one JSON payload per data line.
                if line.hasPrefix("data:") {
                    let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { done = true; break }
                    event.append(payload)
                    if let object = try? jsonObject(event.joined(separator: "\n")) {
                        let delta = try accumulator.consume(object); event.removeAll()
                        if !delta.isEmpty { await onDelta(delta) }
                    }
                }
            }
            guard event.isEmpty, done || accumulator.finished else { throw DatabaseFailure(String(localized: "流式连接提前结束，请重试；未执行任何工具。")) }
        } else {
            var data = Data()
            for try await byte in bytes { data.append(byte); guard data.count <= 2_000_000 else { throw DatabaseFailure(String(localized: "API 响应过大。")) } }
            let object = try jsonObject(String(decoding: data, as: UTF8.self))
            let delta = try accumulator.consume(object)
            if !delta.isEmpty { await onDelta(delta) }
        }
        return try accumulator.message()
    }

    private func validate(_ response: URLResponse, body: Data, key: String) throws {
        guard let response = response as? HTTPURLResponse else { throw DatabaseFailure(String(localized: "无效的 HTTP 响应。")) }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            var message = (error?["error"] as? [String: Any])?["message"] as? String ?? String(localized: "请检查地址、模型与 API Key。")
            if !key.isEmpty { message = message.replacingOccurrences(of: key, with: "<API Key>") }
            if (300..<400).contains(response.statusCode) { message = String(localized: "API 地址发生重定向，已停止请求。请直接填写最终 API 地址。") }
            throw DatabaseFailure("API HTTP \(response.statusCode)：\(String(message.prefix(1000)))")
        }
    }
    static let tools: [[String: Any]] = [
        ["type": "function", "function": ["name": "ask_user", "description": String(localized: "信息不足时向用户提出一个短问题。通常提供两到三个选项，选择表或字段时最多十二个；也可不提供选项让用户自由回答。回答不代表数据库操作授权。"), "parameters": ["type": "object", "properties": ["question": ["type": "string", "maxLength": 240], "options": ["type": "array", "items": ["type": "string", "maxLength": 100], "maxItems": AgentQuestion.maximumOptions]], "required": ["question"], "additionalProperties": false]]],
        ["type": "function", "function": ["name": "inspect_schema", "description": String(localized: "请求用户批准后检查当前数据库的表/集合及当前表字段；不会读取记录。"), "parameters": ["type": "object", "properties": [:], "additionalProperties": false]]],
        ["type": "function", "function": ["name": "execute_query", "description": String(localized: "提出一条 SQL 或 MongoDB JSON 命令，由用户确认后执行；结果只有用户选择发送后才返回模型。"), "parameters": ["type": "object", "properties": ["query": ["type": "string", "description": String(localized: "一条 SQL，或命令名位于首位的 MongoDB JSON 命令")], "reason": ["type": "string", "description": String(localized: "说明目的和可能的写入影响")]], "required": ["query", "reason"], "additionalProperties": false]]]
    ]
}
