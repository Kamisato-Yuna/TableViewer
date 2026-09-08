import Foundation
import AppKit

actor DeltaCapture {
    var text = ""
    func append(_ value: String) { text += value }
}

actor ControlledCompletion {
    struct Request {
        var messages: [AgentMessage]
        var delta: @Sendable (String) async -> Void
        var continuation: CheckedContinuation<AgentMessage, Error>
    }
    var requests: [Request] = []
    func complete(_ messages: [AgentMessage], delta: @escaping @Sendable (String) async -> Void) async throws -> AgentMessage {
        try await withCheckedThrowingContinuation { continuation in requests.append(Request(messages: messages, delta: delta, continuation: continuation)) }
    }
    var count: Int { requests.count }
    func emit(_ index: Int, _ text: String) async { await requests[index].delta(text) }
    func succeed(_ index: Int, _ message: AgentMessage) { requests[index].continuation.resume(returning: message) }
    func fail(_ index: Int) { requests[index].continuation.resume(throwing: DatabaseFailure("fixture connection interrupted")) }
    func history(_ index: Int) -> [AgentMessage] { requests[index].messages }
}

@main struct AgentExperienceTests {
    static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw DatabaseFailure("FAIL: " + label) }; print("PASS: " + label)
    }
    @MainActor static func eventually(_ predicate: () async -> Bool) async throws {
        for _ in 0..<300 { if await predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
        throw DatabaseFailure("Timed out waiting for test request")
    }
    static func chunk(_ text: String, reason: String? = nil) -> [String: Any] {
        var choice: [String: Any] = ["delta": ["content": text, "reasoning_content": "PRIVATE_FIELD"]]
        if let reason { choice["finish_reason"] = reason }
        return ["choices": [choice]]
    }
    static func tool(_ name: String, _ arguments: String = "{}") -> AgentMessage {
        AgentMessage(role: "assistant", toolCalls: [AgentToolCall(id: "provider-reused-id", function: AgentFunction(name: name, arguments: arguments))])
    }
    @MainActor static func approvalTests() async throws {
        let context = AgentContext(connectionID: UUID(), connectionName: "Approval fixture", kind: .sqlite)
        let queryCall = AgentToolCall(id: "query", function: AgentFunction(name: "execute_query", arguments: #"{"query":"SELECT 1"}"#))
        let action = AgentAction(call: queryCall, messageID: UUID(), connectionID: context.connectionID, connectionName: context.connectionName)
        try check(!AgentApprovalMode.manual.permitsAutomaticExecution(action, kind: .sqlite), "manual never automatically executes")
        try check(AgentApprovalMode.sensitiveOnly.permitsAutomaticExecution(action, kind: .sqlite), "sensitive mode selects read-only candidate")
        var write = action; write.call.function.arguments = #"{"query":"DELETE FROM private_data"}"#
        try check(!AgentApprovalMode.sensitiveOnly.permitsAutomaticExecution(write, kind: .sqlite), "sensitive writes require approval")
        try check(AgentApprovalMode.automatic.permitsAutomaticExecution(write, kind: .sqlite), "automatic mode honors write approval choice")
        var question = action; question.call.function.name = "ask_user"
        try check(!AgentApprovalMode.automatic.permitsAutomaticExecution(question, kind: .sqlite), "automatic never answers for the user")
        var analyze = action; analyze.call.function.arguments = #"{"query":"EXPLAIN ANALYZE DELETE FROM data"}"#
        try check(!AgentApprovalMode.sensitiveOnly.permitsAutomaticExecution(analyze, kind: .postgresql), "EXPLAIN ANALYZE is not an automatic read candidate")
        var mongo = action
        mongo.call.function.arguments = try jsonText(["query": #"{"delete":"data","find":"data","deletes":[{"q":{},"limit":0}]}"#])
        try check(!AgentApprovalMode.sensitiveOnly.permitsAutomaticExecution(mongo, kind: .mongodb), "Mongo approval uses the first command field rather than a decoy read key")
        let session = AgentSession(complete: { _, _, _, _ in AgentMessage(role: "assistant", toolCalls: [queryCall]) })
        session.configuration = AgentConfiguration(baseURL: "http://localhost:1", model: "controlled")
        session.approvalMode = .sensitiveOnly
        var callbackIDs: [String] = []; var forcedReadOnly = false
        session.onAutomaticActions = { callbackIDs = $0; forcedReadOnly = $1 }
        session.input = "fixture"; session.send(context: context)
        try await eventually { !session.running }
        try check(callbackIDs == session.actions.map(\.id) && forcedReadOnly, "fresh automatic actions require driver read-only enforcement")
        let stored = StoredAgentSession(session)
        let restored = try JSONDecoder().decode(StoredAgentSession.self, from: JSONEncoder().encode(stored)).restore()
        try check(restored.approvalMode == .sensitiveOnly && restored.actions.first?.state == .awaitingApproval, "restore retains policy without running pending history")
        var oldArchive = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stored)) as! [String: Any]
        oldArchive.removeValue(forKey: "approvalMode")
        let old = try JSONDecoder().decode(StoredAgentSession.self, from: JSONSerialization.data(withJSONObject: oldArchive)).restore()
        try check(old.approvalMode == .manual, "existing archives migrate to manual approval")
        let id = callbackIDs[0]
        _ = session.beginExecution(id, connectionID: context.connectionID)
        session.resolve(id, output: "synthetic result", failed: false)
        try check(session.canContinue && !session.actions[0].shared && !session.messages.contains { $0.role == "tool" }, "automatic execution never shares local results")
        try check(ConnectionVault.service(for: "local.yuna.TableViewer") == "local.yuna.TableViewer.connections", "production Keychain namespace stays unchanged")
        try check(ConnectionVault.service(for: "local.yuna.TableViewer.Acceptance040") != ConnectionVault.service(for: "local.yuna.TableViewer"), "test bundle isolates fixed Agent credential ID")
    }
    @MainActor static func automaticResultTests() async throws {
        let context = AgentContext(connectionID: UUID(), connectionName: "Synthetic Auto Results", kind: .sqlite)
        let control = ControlledCompletion()
        let session = AgentSession(complete: { _, messages, _, delta in try await control.complete(messages, delta: delta) })
        session.configuration = AgentConfiguration(baseURL: "http://127.0.0.1:1", model: "fixture")
        session.input = "synthetic"; session.send(context: context)
        try await eventually { await control.count == 1 }
        await control.succeed(0, tool("execute_query", #"{"query":"SELECT 1"}"#))
        try await eventually { !session.running }
        let first = session.pendingActions[0]
        _ = session.beginExecution(first.id, connectionID: context.connectionID)
        session.resolve(first.id, output: "1", failed: false)
        try check(!session.running && !first.shared, "results remain local by default")
        session.authorizeAutomaticResults(true)
        session.continueWithResults(context: context)
        try await eventually { await control.count == 2 }
        var batch = tool("execute_query", #"{"query":"SELECT 2"}"#)
        batch.toolCalls!.append(AgentToolCall(id: "question", function: AgentFunction(name: "ask_user", arguments: #"{"question":"范围？","options":["一","二"]}"#)))
        await control.succeed(1, batch)
        try await eventually { !session.running }
        let query = session.pendingActions[0], question = session.pendingActions[1]
        _ = session.beginExecution(query.id, connectionID: context.connectionID)
        session.resolve(query.id, output: "2", failed: false)
        try check(!session.running && session.pendingActions.count == 2, "automatic results cannot skip unanswered question")
        session.answer(question.id, text: "一")
        try await eventually { await control.count == 3 }
        session.resolve(query.id, output: "duplicate", failed: false)
        session.continueWithResults(context: context)
        try check(session.messages.filter { $0.role == "tool" }.count == 3, "multi-tool batch sent exactly once")
        await control.succeed(2, tool("execute_query", #"{"query":"SELECT 3"}"#))
        try await eventually { !session.running }
        try check(session.pendingActions[0].state == .awaitingApproval, "automatic send does not approve database execution")
        let restored = StoredAgentSession(session).restore()
        try check(restored.automaticResultsConfiguration == session.configuration, "session authorization persists")
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredAgentSession(session))) as! [String: Any]
        oldJSON.removeValue(forKey: "automaticResultsConfiguration")
        let old = try JSONDecoder().decode(StoredAgentSession.self, from: JSONSerialization.data(withJSONObject: oldJSON)).restore()
        try check(old.automaticResultsConfiguration == nil && AgentSession().automaticResultsConfiguration == nil, "old archive and new session default off")
        session.authorizeAutomaticResults(false)
        let next = session.pendingActions[0]
        _ = session.beginExecution(next.id, connectionID: context.connectionID)
        session.resolve(next.id, output: "3", failed: false)
        try check(!session.running && session.canContinue, "revocation leaves next result local")
        session.authorizeAutomaticResults(true)
        session.actions.append(AgentAction(call: AgentToolCall(id: "failure", function: AgentFunction(name: "execute_query", arguments: #"{"query":"SELECT 4"}"#)), messageID: UUID(), connectionID: context.connectionID, connectionName: context.connectionName))
        let failing = session.pendingActions.last!
        _ = session.beginExecution(failing.id, connectionID: context.connectionID)
        session.resolve(failing.id, output: "synthetic failure", failed: true)
        try check(!session.running && session.canContinue, "failed result requires explicit sending despite authorization")
        session.authorizeAutomaticResults(true); session.configuration.model = "changed"
        try check(!session.automaticallySendsResults, "API configuration change invalidates authorization")
        session.authorizeAutomaticResults(true); session.stop()
        try check(!session.automaticallySendsResults, "stop revokes authorization")
        session.authorizeAutomaticResults(true); session.archived = true; session.archived = false
        try check(!session.automaticallySendsResults, "archive and restore cannot reactivate authorization")
    }
    @MainActor static func main() async throws {
        try await automaticResultTests()
        try await approvalTests()
        let editor = ComposerTextView()
        var submits = 0
        editor.canSubmit = true; editor.submit = { submits += 1 }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        editor.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        _ = editor.performKeyEquivalent(with: event)
        try check(editor.hasMarkedText() && submits == 0, "Command-Return does not submit active IME composition")
        editor.unmarkText(); editor.string = "中文草稿"
        _ = editor.performKeyEquivalent(with: event)
        try check(submits == 1 && editor.string == "中文草稿", "Command-Return submits committed Chinese text")
        editor.canSubmit = false; _ = editor.performKeyEquivalent(with: event)
        try check(submits == 1, "shortcut respects pending approval / disabled submission")
        editor.insertNewline(nil)
        try check(editor.string.contains("\n"), "native Return inserts a newline")
        // Exercise every possible chunk boundary, including escaped and mixed-case tags.
        for source in ["<think>PRIVATE</think># 答案\n```sql\nSELECT 1;\n```", "&lt;think&gt;PRIVATE&lt;/think&gt;# 答案\n```sql\nSELECT 1;\n```", "<THINK>PRIVATE</THINK># 答案\n```sql\nSELECT 1;\n```"] {
            for split in 0...source.count {
                var accumulator = CompletionAccumulator()
                let first = String(source.prefix(split)), second = String(source.dropFirst(split))
                let visible = try accumulator.consume(chunk(first)) + accumulator.consume(chunk(second, reason: "stop"))
                let message = try accumulator.message()
                try check(visible == "# 答案\n```sql\nSELECT 1;\n```" && message.content == visible, "reasoning boundary \(split) / \(source.count)")
            }
        }
        var filter = AgentReasoningFilter()
        var visible = ""
        for character in "<think>SECRET</think>正文" { visible += filter.consume(String(character)) }
        try check(visible == "正文", "single-character chunks never expose tags or reasoning")
        var incomplete = CompletionAccumulator()
        let held = try incomplete.consume(chunk("<think>private"))
        try check(held.isEmpty, "unclosed reasoning is withheld")
        var length = CompletionAccumulator()
        let partial = try length.consume(chunk("可保留", reason: "length"))
        do { _ = try length.message(); throw DatabaseFailure("missing length error") } catch { try check(partial == "可保留" && error.localizedDescription.contains("上限"), "length delivers last delta before failure and rejects tools") }
        let blocks = AgentMarkdownBlock.parse("# 标题\n\n段落 **加粗**\n\n- 列表\n2. 第二项\n> 引用\n```sql\nSELECT 1;\nSELECT 2;\n```")
        try check(blocks == [.heading(1,"标题"), .paragraph("段落 **加粗**"), .list("•","列表"), .list("2.","第二项"), .quote("引用"), .code("sql","SELECT 1;\nSELECT 2;")], "Markdown headings, paragraphs, lists, quotes and code retain block boundaries")
        try check(AgentMarkdownBlock.parse("```sql\nSELECT") == [.code("sql","SELECT")], "unfinished streamed code fence renders as code")
        let tableMarkdown = "# 数据库\n\n| 表名 | 数量 | 说明 |\n| :--- | ---: | :---: |\n| `projects` | **5** | 项目 \\| 计划 |\n| notes | 2 |\n\n结束"
        try check(AgentMarkdownBlock.parse(tableMarkdown) == [
            .heading(1, "数据库"),
            .table(headers: ["表名", "数量", "说明"], alignments: [.leading, .trailing, .center], rows: [["`projects`", "**5**", "项目 | 计划"], ["notes", "2", ""]]),
            .paragraph("结束")
        ], "Markdown table preserves alignment, inline formatting, escaped pipes and partial rows")
        try check(AgentMarkdownBlock.parse("表名 | 说明\r\n--- | ---\r\nprojects | 项目") == [.table(headers: ["表名", "说明"], alignments: [.leading, .leading], rows: [["projects", "项目"]])], "tables support CRLF and optional outer pipes")
        try check(AgentMarkdownBlock.parse("| A | B |\n| -- | -- |\n| 1 | 2 |") == [.paragraph("| A | B |\n| -- | -- |\n| 1 | 2 |")], "invalid separator stays readable text")
        try check(AgentMarkdownBlock.parse("```text\n| A | B |\n| --- | --- |\n```") == [.code("text", "| A | B |\n| --- | --- |")], "table syntax inside fences remains literal code")
        let overflow = AgentMarkdownBlock.parse("| A | B |\n| --- | --- |\n| 1 | 2 | 3 |")
        try check(overflow.last == .paragraph("| 1 | 2 | 3 |"), "extra table values are retained rather than silently discarded")
        for split in 0...tableMarkdown.count {
            for block in AgentMarkdownBlock.parse(String(tableMarkdown.prefix(split))) {
                if case .table(let headers, let alignments, let rows) = block {
                    guard !headers.isEmpty, headers.count == alignments.count, rows.allSatisfy({ $0.count == headers.count }) else { throw DatabaseFailure("invalid streamed table shape") }
                }
            }
        }
        try check(true, "every streamed table prefix has safe column and row bounds")
        let choices = "当前表：`projects`\n\n需要我帮你做什么？例如：\n1. 查看某个表的数据\n2. 编写查询条件\n3. 了解数据关系\n4. 其他操作"
        let options = ["查看某个表的数据", "编写查询条件", "了解数据关系", "其他操作"]
        try check(AgentQuickReply.options(in: choices) == options, "screenshot-style invitation becomes four quick reply options")
        try check(AgentQuickReply.options(in: "Which approach would you like?\n- Offset\n- Cursor") == ["Offset", "Cursor"], "English invitations support bullet options")
        for ordinary in ["操作步骤：\n1. 打开连接\n2. 执行查询", "```text\n你想使用哪种？\n1. A\n2. B\n```", "需要我做什么？\n1. 重复\n2. 重复", "你想了解什么？\n1. A\n2. B\n\n下面介绍实现步骤。"] {
            try check(AgentQuickReply.options(in: ordinary).isEmpty, "ordinary, fenced, duplicate or nonfinal lists are not quick replies")
        }
        let quickControl = ControlledCompletion()
        let quickSession = AgentSession { _, history, _, delta in try await quickControl.complete(history, delta: delta) }
        quickSession.configuration = AgentConfiguration(baseURL: "https://example.invalid/v1", model: "fixture")
        let quickContext = AgentContext(connectionID: UUID(), connectionName: "Quick reply fixture", kind: .sqlite)
        quickSession.connection = quickContext
        let choiceMessage = AgentMessage(role: "assistant", content: choices)
        quickSession.messages = [choiceMessage]; quickSession.input = "尚未发送的中文草稿"
        try check(!quickSession.reply(with: options[0], to: UUID(), context: quickContext), "stale reply buttons cannot send")
        try check(!quickSession.reply(with: "未提供的选项", to: choiceMessage.id, context: quickContext), "quick reply must match an offered choice")
        try check(!quickSession.reply(with: options[0], to: choiceMessage.id, context: AgentContext(connectionID: UUID(), connectionName: "Other", kind: .sqlite)), "quick reply respects original database binding")
        quickSession.archived = true
        try check(quickSession.quickReplies.isEmpty, "archived sessions have no actionable quick replies")
        quickSession.archived = false
        quickSession.messages[0].delivery = .generating
        try check(quickSession.quickReplies.isEmpty, "partial streamed options cannot be clicked")
        quickSession.messages[0].delivery = .complete
        let guardedAction = AgentAction(call: AgentToolCall(id: "approval", function: AgentFunction(name: "execute_query", arguments: #"{"query":"SELECT 1"}"#)), messageID: choiceMessage.id, connectionID: quickContext.connectionID, connectionName: quickContext.connectionName)
        quickSession.actions = [guardedAction]
        try check(!quickSession.reply(with: options[0], to: choiceMessage.id, context: quickContext) && quickSession.actions[0].state == .awaitingApproval, "quick reply cannot bypass a pending database approval")
        quickSession.actions = []
        try check(quickSession.reply(with: options[1], to: choiceMessage.id, context: quickContext), "click sends the selected option through normal user-message flow")
        try check(quickSession.input == "尚未发送的中文草稿" && quickSession.messages.filter({ $0.role == "user" }).map(\.content) == [options[1]], "option sends once and preserves existing composer draft")
        try check(!quickSession.reply(with: options[1], to: choiceMessage.id, context: quickContext), "repeated click cannot send a duplicate turn")
        try await eventually { await quickControl.count == 1 }
        let quickHistory = await quickControl.history(0)
        try check(quickHistory.last?.content == options[1] && quickHistory.last?.role == "user", "provider receives the selected option as a normal user message")
        await quickControl.succeed(0, AgentMessage(role: "assistant", content: "已收到"))
        try await eventually { !quickSession.running }
        try check(AgentQuestion.parse(#"{"question":"哪一种分页？","options":["偏移","游标"]}"#) != nil && AgentQuestion.parse(#"{"question":"","options":[]}"#) == nil, "clarification validation")
        let fiveOptions = #"{"question":"当前数据库有 5 个表，你想查看哪个表的数据？","options":["active_projects","activity","members","notes","projects"]}"#
        try check(AgentQuestion.parse(fiveOptions)?.options.count == 5, "real five-table choice is valid instead of an execution failure")
        try check(AgentQuestion.parse(#"{"question":" 请描述筛选条件 "}"#)?.question == "请描述筛选条件" && AgentQuestion.parse(#"{"question":"补充条件？","options":null}"#)?.options == [], "missing or null options allow freeform clarification")
        try check(AgentQuestion.parse(#"{"question":"选择表？","options":[" projects ","projects"," ","notes"]}"#)?.options == ["projects", "notes"], "formatting noise is normalized without losing distinct choices")
        let twelveOptions = try jsonText(["question": "选择字段？", "options": (1...12).map { "field_\($0)" }], pretty: false)
        try check(AgentQuestion.parse(twelveOptions)?.options.count == 12, "twelve concrete objects remain selectable")
        for invalid in [#"{"question":"选择？","options":[{"label":"项目"}]}"#, #"{"question":"选择？","options":"projects"}"#, try jsonText(["question": "选择？", "options": (1...13).map(String.init)], pretty: false), try jsonText(["question": "选择？", "options": [String(repeating: "x", count: 101)]], pretty: false)] {
            try check(AgentQuestion.parse(invalid) == nil && AgentQuestion.validationFailure(invalid) != nil, "invalid or excessive options retain explicit bounds and useful failure details")
        }
        let recoverable = AgentSession { _, _, _, _ in throw DatabaseFailure("recovery must not request model") }
        recoverable.connection = quickContext
        var historicalQuestion = AgentAction(call: AgentToolCall(id: "historical-five", function: AgentFunction(name: "ask_user", arguments: fiveOptions)), messageID: UUID(), connectionID: quickContext.connectionID, connectionName: "Studio")
        historicalQuestion.state = .failed; historicalQuestion.outcome = "澄清问题格式无效，请模型重新提问。"
        recoverable.actions = [historicalQuestion]
        try check(recoverable.actions[0].canRestoreQuestion && recoverable.actions[0].status != String(localized: "执行失败"), "old failed five-option history offers question recovery")
        recoverable.restoreQuestion(historicalQuestion.id)
        try check(recoverable.actions[0].state == .awaitingApproval && recoverable.actions[0].outcome == nil && !recoverable.running, "restoring old choices does not send, execute or recreate the question")
        recoverable.answer(historicalQuestion.id, text: "projects")
        try check(recoverable.actions[0].outcome == "projects" && !recoverable.actions[0].shared, "restored table choice remains a local answer")
        recoverable.restoreQuestion(historicalQuestion.id)
        try check(recoverable.actions[0].outcome == "projects", "completed historical question cannot be reset by a stale recovery button")
        historicalQuestion.shared = true; recoverable.actions = [historicalQuestion]
        recoverable.restoreQuestion(historicalQuestion.id)
        try check(recoverable.actions[0].state == .failed && recoverable.actions[0].shared, "already shared failure is not rewritten or replayed")
        let restoredFailure = StoredAgentSession(recoverable).restore()
        try check(restoredFailure.actions[0].shared && restoredFailure.actions[0].outcome == historicalQuestion.outcome, "history roundtrip preserves already shared failure")
        let control = ControlledCompletion()
        let session = AgentSession { _, history, _, delta in try await control.complete(history, delta: delta) }
        session.configuration = AgentConfiguration(baseURL: "https://example.invalid/v1", model: "fixture")
        let context = AgentContext(connectionID: UUID(), connectionName: "Fixture", kind: .sqlite)
        session.input = "解释分页"; session.send(context: context)
        try await eventually { await control.count == 1 }
        await control.emit(0, "已生成的文字")
        let responseID = session.messages.last!.id
        session.input = "中文草稿"; session.stop()
        try check(session.messages.last?.content == "已生成的文字" && session.messages.last?.delivery == .stopped && session.input == "中文草稿" && session.error == nil, "stop preserves content, neutral status and draft")
        await control.emit(0, "迟到增量")
        await control.succeed(0, tool("execute_query", #"{"query":"DELETE FROM x"}"#))
        try check(session.messages.last?.content == "已生成的文字" && session.actions.isEmpty, "cancelled request ignores late delta and tool completion")
        session.retry(context: context)
        try await eventually { await control.count == 2 }
        let retried = await control.history(1)
        try check(retried.count == 1 && retried.first?.role == "user" && session.messages.count == 2 && session.messages.last?.id == responseID, "retry replaces same response and reuses prompt without duplicate turn")
        await control.fail(1)
        try await eventually { !session.running }
        try check(session.messages.last?.content == "已生成的文字" && session.messages.last?.delivery == .failed, "empty failed retry restores previous visible reply")
        session.retry(context: context)
        try await eventually { await control.count == 3 }
        await control.emit(2, "新部分")
        await control.fail(2)
        try await eventually { !session.running }
        try check(session.messages.last?.content == "新部分", "failure retains streamed partial reply")
        session.retry(context: context)
        try await eventually { await control.count == 4 }
        session.stop()
        try check(session.messages.last?.content == "新部分", "stopping an empty retry preserves its previous partial answer")
        await control.fail(3)
        session.continueReply(context: context)
        try await eventually { await control.count == 5 }
        let continued = await control.history(4)
        try check(continued.count == 3 && continued[1].content == "新部分", "continue includes visible partial answer and an explicit continuation turn")
        await control.emit(4, "继续的部分")
        session.input = "补充条件"; session.send(context: context)
        try await eventually { await control.count == 6 }
        let supplemented = await control.history(5)
        try check(supplemented.last?.content == "补充条件" && supplemented[supplemented.count-2].content == "继续的部分", "supplement cancels old request and carries partial content into new request")
        await control.emit(4, "stale")
        await control.succeed(4, tool("inspect_schema"))
        await control.succeed(5, tool("execute_query", #"{"query":"SELECT 1","reason":"fixture"}"#))
        try await eventually { !session.running }
        let action = session.pendingActions[0]
        try check(session.actions.count == 1 && session.beginExecution(action.id, connectionID: UUID()) == nil, "late tools are ignored and connection binding enforced")
        try check(session.beginExecution(action.id, connectionID: context.connectionID) != nil && session.beginExecution(action.id, connectionID: context.connectionID) == nil, "explicit execution can be claimed only once")
        session.reject(action.id)
        try check(session.actions[0].state == .executing, "rejection cannot race an executing action")
        session.resolve(action.id, output: "fixture rows", failed: false)
        session.resolve(action.id, output: "duplicate", failed: true)
        try check(session.actions[0].outcome == "fixture rows" && session.canContinue && session.messages.last?.role == "assistant", "results retained locally until separate sharing approval; duplicate resolution ignored")
        session.continueWithResults(context: AgentContext(connectionID: UUID(), connectionName: "Other", kind: .sqlite))
        try check(!session.running, "wrong connection cannot share results")
        session.continueWithResults(context: context)
        try await eventually { await control.count == 7 }
        let shared = await control.history(6)
        try check(session.actions[0].shared && session.actions[0].messageID == action.messageID && shared.last?.toolCallID == action.call.id, "sharing retains original action card and provider protocol ID")
        let archivedData = try JSONEncoder().encode(StoredAgentSession(session))
        let restoredShared = try JSONDecoder().decode(StoredAgentSession.self, from: archivedData).restore()
        try check(restoredShared.actions[0].shared && restoredShared.actions[0].messageID == action.messageID, "local serialization preserves shared-result state and message identity")
        await control.fail(6)
        try await eventually { !session.running }
        session.retry(context: context)
        try await eventually { await control.count == 8 }
        let toolRetry = await control.history(7)
        try check(toolRetry.filter { $0.role == "tool" }.count == 1 && session.beginExecution(action.id, connectionID: context.connectionID) == nil, "retry after shared result never repeats execution or tool reply")
        await control.succeed(7, tool("inspect_schema"))
        try await eventually { !session.running }
        let second = session.pendingActions[0]
        try check(second.id != action.id && second.call.id == action.call.id, "reused provider IDs cannot collide with prior actions")
        session.reject(second.id)
        try check(session.actions.last?.state == .rejected && session.beginExecution(second.id, connectionID: context.connectionID) == nil, "rejection has distinct status and cannot execute")
        session.continueWithResults(context: context)
        try await eventually { await control.count == 9 }
        await control.succeed(8, tool("ask_user", #"{"question":"选择分页方式？","options":["偏移","游标"]}"#))
        try await eventually { !session.running }
        let question = session.pendingActions[0]
        try check(session.beginExecution(question.id, connectionID: context.connectionID) == nil, "clarification cannot authorize database execution")
        session.answer(question.id, text: "游标，并按 id 排序")
        try check(session.actions.last?.outcome == "游标，并按 id 排序" && !session.actions.last!.shared, "freeform clarification answer stays local until sharing approval")
        session.continueWithResults(context: context)
        try await eventually { await control.count == 10 }
        session.reset()
        await control.emit(9, "old conversation")
        await control.succeed(9, tool("execute_query"))
        try check(session.messages.isEmpty && session.actions.isEmpty, "reset ignores in-flight completion")
        let encoded = String(decoding: try JSONEncoder().encode(AgentMessage(role: "assistant", content: "answer", delivery: .stopped)), as: UTF8.self)
        try check(!encoded.contains("delivery") && !encoded.contains("id"), "local presentation status stays out of provider messages")
        let client = OpenAICompatibleClient()
        for model in ["plain", "stream", "tools", "truncated", "length", "unauthorized"] {
            let capture = DeltaCapture()
            let configuration = AgentConfiguration(baseURL: ProcessInfo.processInfo.environment["TABLEVIEWER_AGENT_FIXTURE"]!, model: model, streaming: model != "plain")
            do {
                let reply = try await client.complete(configuration: configuration, key: "fixture-key", messages: [AgentMessage(role: "user", content: "SQLite tutorial")], context: context) { await capture.append($0) }
                try check(["plain", "stream", "tools"].contains(model), "HTTP response should succeed only for complete fixtures")
                let text = await capture.text
                try check(reply.content == "# SQLite\n\n```sql\nSELECT 1;\n```" && reply.content == text, "HTTP \(model) hides reasoning and preserves Markdown")
                if model == "tools" { try check(reply.toolCalls?.first?.function.name == "ask_user" && AgentQuestion.parse(reply.toolCalls![0].function.arguments) != nil, "HTTP fragmented clarification tool arguments assemble") }
            } catch {
                let text = await capture.text
                switch model {
                case "truncated": try check(error.localizedDescription.contains("提前结束") && text.contains("SELECT 1"), "HTTP premature EOF retains delivered partial text and rejects tools")
                case "length": try check(error.localizedDescription.contains("上限") && text.hasSuffix("最后文字"), "HTTP length failure delivers final text and rejects incomplete tool")
                case "unauthorized": try check(error.localizedDescription.contains("401") && !error.localizedDescription.contains("fixture-key"), "HTTP errors continue redacting credentials")
                default: throw error
                }
            }
        }
        for model in ["five-options", "freeform-question", "malformed-question"] {
            let configuration = AgentConfiguration(baseURL: ProcessInfo.processInfo.environment["TABLEVIEWER_AGENT_FIXTURE"]!, model: model)
            let flow = AgentSession { configuration, messages, context, delta in
                try await client.complete(configuration: configuration, key: "fixture-key", messages: messages, context: context, onDelta: delta)
            }
            flow.configuration = configuration; flow.input = "查看某个表的数据"; flow.send(context: quickContext)
            try await eventually { !flow.running }
            guard let question = flow.actions.first else { throw DatabaseFailure("missing fixture question") }
            if model == "malformed-question" {
                try check(question.state == .failed && flow.canReaskQuestion(question.id), "malformed HTTP question exposes an explicit retry")
                flow.actions.append(guardedAction)
                try check(!flow.canReaskQuestion(question.id), "question retry cannot share another pending database action")
                flow.actions.removeLast()
                flow.reaskQuestion(question.id, context: quickContext)
                try await eventually { !flow.running }
                try check(flow.actions.count == 2 && flow.actions[0].shared && flow.actions[1].state == .awaitingApproval && flow.actions[1].question?.options.count == 5, "retry sends only failed tool result and accepts corrected five-option question")
                try check(flow.messages.filter { $0.role == "tool" }.count == 1 && flow.messages.filter { $0.role == "user" }.count == 1, "question retry preserves protocol without duplicate user turns")
            } else {
                try check(question.state == .awaitingApproval && question.question?.options.count == (model == "five-options" ? 5 : 0), "HTTP \(model) reaches an answerable question")
            }
            let pending = flow.pendingActions[0]
            flow.answer(pending.id, text: "projects")
            try check(!flow.running && !flow.actions.last!.shared && flow.beginExecution(pending.id, connectionID: quickContext.connectionID) == nil, "table selection stays local and never authorizes execution")
            flow.continueWithResults(context: quickContext)
            try await eventually { !flow.running }
            try check(flow.messages.last?.content == "已选择 projects" && flow.pendingActions.isEmpty, "HTTP question-answer-continue finishes without a failed or repeated call")
        }
        print("ALL AGENT EXPERIENCE CHECKS PASSED")
    }
}
