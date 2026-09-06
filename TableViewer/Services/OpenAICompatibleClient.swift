import Foundation

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct CompletionAccumulator {
    var content = ""
    var calls: [Int: AgentToolCall] = [:]
    var finished = false
    mutating func consume(_ object: [String: Any]) throws -> String {
        if let error = object["error"] as? [String: Any] { throw DatabaseFailure(error["message"] as? String ?? String(localized: "API 返回错误。")) }
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return "" }
        let delta = choice["delta"] as? [String: Any] ?? choice["message"] as? [String: Any] ?? [:]
        let text = delta["content"] as? String ?? delta["refusal"] as? String ?? ""
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
            if reason == "length" { throw DatabaseFailure(String(localized: "模型输出达到上限，请缩小请求范围后重试；未执行任何工具。")) }
            finished = true
        }
        guard content.utf8.count + calls.values.reduce(0, { $0 + $1.function.arguments.utf8.count }) <= 1_000_000 else { throw DatabaseFailure(String(localized: "API 返回内容过大。")) }
        return text
    }
    func message() throws -> AgentMessage {
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
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
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
    private static let tools: [[String: Any]] = [
        ["type": "function", "function": ["name": "inspect_schema", "description": String(localized: "请求用户批准后检查当前数据库的表/集合及当前表字段；不会读取记录。"), "parameters": ["type": "object", "properties": [:], "additionalProperties": false]]],
        ["type": "function", "function": ["name": "execute_query", "description": String(localized: "提出一条 SQL 或 MongoDB JSON 命令，由用户确认后执行；结果只有用户选择发送后才返回模型。"), "parameters": ["type": "object", "properties": ["query": ["type": "string", "description": String(localized: "一条 SQL，或命令名位于首位的 MongoDB JSON 命令")], "reason": ["type": "string", "description": String(localized: "说明目的和可能的写入影响")]], "required": ["query", "reason"], "additionalProperties": false]]]
    ]
}
