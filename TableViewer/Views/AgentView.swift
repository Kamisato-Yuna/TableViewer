import SwiftUI
import AppKit

struct AgentView: View {
    @Bindable var store: WorkspaceStore
    var readingWidth: CGFloat = 920
    var body: some View {
        VStack(spacing: 0) {
            if let failure = store.agentLibrary.persistenceError { Text(failure).font(.caption).foregroundStyle(.orange).padding(10) }
            if let agent = store.agent { AgentConversationView(store: store, agent: agent, readingWidth: readingWidth).id(agent.id) }
            else {
                ContentUnavailableView("会话历史", systemImage: "bubble.left.and.bubble.right", description: Text("创建会话后，消息和操作进度会保存在本机。"))
                HStack { Button("新会话", systemImage: "plus") { store.newAgentSession() }; Button("所有会话") { store.showAgentHistory = true } }.padding()
            }
        }.sheet(isPresented: $store.showAgentHistory) { AgentHistoryView(store: store) }
    }
}

private struct AgentConversationView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var agent: AgentSession
    let readingWidth: CGFloat
    @State private var followsBottom = true
    @State private var userScrolling = false
    @State private var scrollRequest = 0
    @State private var hoveredMessageID: UUID?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(agent.ready ? agent.configuration.model : String(localized: "配置你的 AI 助手"), systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("所有会话", systemImage: "bubble.left.and.bubble.right") { store.showAgentHistory = true }
                Button("新对话", systemImage: "square.and.pencil") { store.newAgentSession() }
                Button("API 设置", systemImage: "slider.horizontal.3") { agent.showSettings = true }.disabled(agent.running || store.busy)
            }.buttonStyle(.borderless).controlSize(.small).padding(.horizontal, 24).frame(height: 48)
            VStack(alignment: .leading, spacing: 6) {
                Text(agent.title).font(.headline).textSelection(.enabled)
                Text("所属数据库：\(agent.connection?.connectionName ?? "") · \(agent.connection?.kind.rawValue ?? "")").font(.caption).foregroundStyle(.secondary)
                if agent.archived {
                    HStack { Text("已归档，运行进度仍会保留。"); Button("恢复会话") { store.agentLibrary.archive(agent, archived: false) } }.font(.caption)
                }
                if !agent.providerMatches { Text("API 配置已变更。此历史仍可查看，请新建会话使用当前配置。").font(.caption).foregroundStyle(.orange) }
                if store.active?.id != agent.connection?.connectionID {
                    HStack {
                        Text("正在查看其他数据库的会话；执行操作前需要连接原数据库。").font(.caption)
                        if let profile = store.profiles.first(where: { $0.id == agent.connection?.connectionID }) {
                            Button("连接原数据库") { Task { await store.connect(profile); store.tab = .agent } }.disabled(store.busy)
                        } else { Text("原连接已不可用，历史仍保留。").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 12)
            if !agent.ready {
                HStack {
                    Label("先配置 API 地址和模型，即可开始对话。", systemImage: "sparkles")
                    Spacer()
                    Button("配置 API") { agent.showSettings = true }.buttonStyle(.glassProminent)
                }.padding(16).background(.quaternary).padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if agent.messages.isEmpty { welcome }
                        ForEach(agent.messages.filter { $0.role != "tool" }) { message in
                            messageCard(message).id(message.id)
                        }
                        if !agent.phase.isEmpty {
                            HStack(spacing: 8) {
                                if agent.running || store.busy { ProgressView().controlSize(.mini) }
                                Text(agent.phase).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        if agent.canContinue {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("回答与结果目前只在本机。确认后会发送给所配置的 API；回答问题不代表批准数据库操作。").font(.system(size: 12)).foregroundStyle(.secondary)
                                Button("发送结果并继续", systemImage: "arrow.up.circle") { if let context = store.agentContext(for: agent) { agent.continueWithResults(context: context); scrollToBottom() } }.buttonStyle(.glassProminent).disabled(store.busy)
                            }
                        }
                        Color.clear.frame(height: 1).id("agent-bottom")
                    }.padding(24).frame(width: readingWidth).frame(maxWidth: .infinity)
                }
                .onScrollPhaseChange { _, phase in userScrolling = phase == .interacting || phase == .decelerating || phase == .tracking }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY < 70
                } action: { _, nearBottom in
                    if userScrolling { followsBottom = nearBottom }
                }
                .onChange(of: agent.messages.last?.content) { if followsBottom { proxy.scrollTo("agent-bottom", anchor: .bottom) } }
                .onChange(of: agent.phase) { if followsBottom { proxy.scrollTo("agent-bottom", anchor: .bottom) } }
                .onChange(of: scrollRequest) { proxy.scrollTo("agent-bottom", anchor: .bottom) }
                .overlay(alignment: .bottomTrailing) {
                    if !followsBottom { Button("回到底部", systemImage: "arrow.down") { scrollToBottom() }.buttonStyle(.glass).padding(16) }
                }
            }
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 12) {
                    AgentComposer(text: $agent.input, canSubmit: agent.canSend && !store.busy, submit: send)
                        .frame(height: 76)
                        .overlay(alignment: .topLeading) {
                            if agent.input.isEmpty { Text("描述你想完成的事情…").font(.system(size: 13)).foregroundStyle(.secondary).padding(4).allowsHitTesting(false) }
                        }
                    HStack(spacing: 10) {
                        Menu {
                            Toggle("附带当前表结构", isOn: $agent.shareSchema)
                                .disabled(agent.running || !agent.pendingActions.isEmpty || agent.archived || store.active?.id != agent.connection?.connectionID)
                        } label: { Image(systemName: agent.shareSchema ? "plus.circle.fill" : "plus") }
                        .help("附带当前表结构")
                        Picker("执行审批", selection: $agent.approvalMode) {
                            ForEach(AgentApprovalMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }.labelsHidden().fixedSize().disabled(agent.running || !agent.pendingActions.isEmpty)
                        Button { agent.showSettings = true } label: {
                            HStack(spacing: 4) {
                                Text(agent.ready ? agent.configuration.model : String(localized: "API 设置")).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                        }.help(URLComponents(string: agent.configuration.baseURL)?.host ?? String(localized: "尚未配置 API"))
                            .disabled(agent.running || store.busy)
                        Spacer(minLength: 4)
                        if agent.running { Button("停止", systemImage: "stop.fill") { agent.stop() }.labelStyle(.iconOnly).buttonStyle(.glass) }
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 19, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                            .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                            .controlSize(.large).tint(.accentColor)
                            .accessibilityLabel(agent.running ? String(localized: "停止并发送补充") : String(localized: "发送"))
                            .help(agent.running ? String(localized: "停止并发送补充") : String(localized: "发送"))
                            .disabled(!agent.canSend || store.busy)
                    }.buttonStyle(.borderless).controlSize(.small)
                }.padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }.frame(width: readingWidth - 48).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)

        }.sheet(isPresented: $agent.showSettings) { AgentSettingsView(agent: agent, saved: { store.newAgentSession() }) }
    }
    private func scrollToBottom() { followsBottom = true; scrollRequest += 1 }
    private func send() { if let context = store.agentContext(for: agent), !store.busy { agent.send(context: context); scrollToBottom() } }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 36, weight: .light)).foregroundStyle(.tint)
            Text("一个懂数据库的搭档。").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("解释结构、编写查询、一起排查问题。数据库操作遵循当前审批级别，结果共享由你确认。").font(.system(size: 12)).foregroundStyle(.secondary)
            AgentExampleButtons { agent.input = $0 }
            VStack(alignment: .leading, spacing: 5) {
                Text("⌘↩ 发送 · Return 换行 · 等待批准时仍可写草稿")
                Text("结果始终留在本机，发送给 API 仍需确认。")
                Text("发送内容包含对话历史\(agent.shareSchema ? String(localized: "及当前表结构") : "")；不会自动发送记录、密码或连接 URI。")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
            if !agent.ready { Button("连接 OpenAI-compatible API", systemImage: "plus") { agent.showSettings = true }.buttonStyle(.glassProminent) }
        }.padding(.vertical, 35)
    }
    private func deliveryLabel(_ message: AgentMessage) -> String {
        if message.delivery == .interrupted { return String(localized: "生成已中断 · 可手动继续") }
        if message.content?.isEmpty != false {
            return message.delivery == .stopped ? String(localized: "已停止 · 尚未收到正文") : String(localized: "生成失败 · 尚未收到正文")
        }
        return message.delivery == .stopped ? String(localized: "已停止 · 已保留部分回复") : String(localized: "生成失败 · 已保留部分回复")
    }
    private func messageCard(_ message: AgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(message.role == "user" ? String(localized: "你") : "Agent", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if let content = message.content, !content.isEmpty, message.role == "assistant" { AgentCopyButton(text: content, label: String(localized: "复制回复")) }
            }
            if let content = message.content, !content.isEmpty {
                if message.role == "user" { Text(verbatim: content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                else {
                    AgentMarkdownView(text: content,
                                      quickReplies: message.id == agent.messages.last?.id ? agent.quickReplies : [],
                                      repliesEnabled: !store.busy && agent.ready && store.active?.id == agent.connection?.connectionID) { option in
                        if !store.busy, let context = store.agentContext(for: agent), agent.reply(with: option, to: message.id, context: context) { scrollToBottom() }
                    }
                }
            }
            ForEach(agent.actions.filter { $0.messageID == message.id }) { action in
                AgentActionCard(action: action, agent: agent, store: store)
            }
            if [.stopped, .failed, .interrupted].contains(message.delivery) {
                Label(deliveryLabel(message), systemImage: message.delivery == .stopped ? "stop.circle" : "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(message.delivery == .failed ? Color.orange : Color.secondary)
                if message.id == agent.messages.last?.id {
                    if let error = agent.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
                    HStack {
                        Button("重新生成") { if let context = store.agentContext(for: agent) { agent.retry(context: context); scrollToBottom() } }.accessibilityLabel("重新生成")
                        Button("继续回复") { if let context = store.agentContext(for: agent) { agent.continueReply(context: context); scrollToBottom() } }.accessibilityLabel("继续回复")
                    }.disabled(!agent.canRetry || store.busy)
                }
            }
            if message.role == "assistant" {
                Text(message.usage?.display ?? String(localized: "未提供用量"))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .opacity(hoveredMessageID == message.id ? 1 : 0)
            }
        }.font(.system(size: 13)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hoveredMessageID = $0 ? message.id : nil }
            .background(message.role == "user" ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025), in: .rect(cornerRadius: 13))
    }
}

private struct AgentActionCard: View {
    var action: AgentAction
    @Bindable var agent: AgentSession
    @Bindable var store: WorkspaceStore
    private var answer: String { action.draftAnswer }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(action.title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                Text(action.status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(); Text(action.connectionName).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let question = action.question {
                Text(question.question)
                if action.canRestoreQuestion {
                    Text("这条历史问题的选项现在可以正常显示，无需重新请求模型。").font(.caption).foregroundStyle(.secondary)
                    Button("恢复问题选项") { agent.restoreQuestion(action.id) }.disabled(agent.archived || agent.running)
                }
                if action.state == .awaitingApproval {
                    ForEach(question.options, id: \.self) { option in
                        Button { agent.answer(action.id, text: option) } label: {
                            HStack { Text(verbatim: option); Spacer(); Image(systemName: "arrow.turn.down.left") }
                        }.buttonStyle(.glass).disabled(agent.archived).help("使用此选项回答（保留在本机）")
                    }
                    TextField("自由补充或修改选项…", text: Binding(get: { answer }, set: { agent.setAnswerDraft(action.id, text: $0) }), axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("确认回答（保留在本机）") { agent.answer(action.id, text: answer) }.disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("回答仅用于澄清需求；数据库操作遵循当前审批级别。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if agent.canReaskQuestion(action.id) {
                Button("让模型重新提问") {
                    if !store.busy, let context = store.agentContext(for: agent) { agent.reaskQuestion(action.id, context: context) }
                }.disabled(store.busy || store.active?.id != agent.connection?.connectionID)
            }
            if let reason = (try? jsonObject(action.call.function.arguments))?["reason"] as? String { Text(reason).foregroundStyle(.secondary) }
            if action.call.function.name == "inspect_schema" {
                Text("inspect_schema").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            if let query = action.query {
                AgentCommandPreview(command: query)
                Text("通过此会话的独立数据库连接执行；不继承查询工作台事务。写入语句会修改数据。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let estimate = action.executionEstimate { Text(verbatim: estimate).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if let result = action.outcome {
                DisclosureGroup(action.shared ? String(localized: "已发送的回答或结果") : String(localized: "查看本地回答或结果（尚未发送）")) {
                    ScrollView { Text(verbatim: result).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220)
                }.font(.system(size: 11))
            } else if action.state == .executing {
                ProgressView().controlSize(.small)
            } else {
                HStack {
                    Spacer(); Button("拒绝") { agent.reject(action.id) }
                    if action.question == nil { Button("确认执行一次") { Task { await store.executeAgentAction(action.id, in: agent) } }.buttonStyle(.glassProminent).disabled(!store.canExecuteAgent(agent)) }
                }.controlSize(.small).disabled(agent.archived)
            }
        }.padding(16).background(Color.accentColor.opacity(0.045), in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.18)) }
    }
    private var symbol: String {
        switch action.state { case .awaitingApproval: return action.question == nil ? "hand.raised" : "questionmark.circle"; case .executing: return "gearshape"; case .completed: return "checkmark.circle"; case .failed: return "exclamationmark.circle"; case .rejected: return "xmark.circle"; case .uncertain: return "questionmark.circle" }
    }
}

struct AgentSettingsView: View {
    @Bindable var agent: AgentSession
    var saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AgentConfiguration()
    @State private var key = ""
    @State private var models: [String] = []
    @State private var loading = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 27, weight: .light)).foregroundStyle(.tint).frame(width: 56, height: 56).glassEffect(in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) { Text("连接你的 AI").font(.system(size: 23, weight: .semibold, design: .rounded)); Text("OpenAI-compatible · Chat Completions").font(.system(size: 11)).foregroundStyle(.secondary) }
            }.padding(26)
            Form {
                TextField("Base URL", text: $configuration.baseURL, prompt: Text("https://api.example.com/v1"))
                SecureField("API Key", text: $key, prompt: Text("本地服务可留空"))
                HStack {
                    TextField("模型", text: $configuration.model, prompt: Text("模型 ID"))
                    if !models.isEmpty { Menu(String(localized: "选择")) { ForEach(models, id: \.self) { model in Button(model) { configuration.model = model } } }.fixedSize() }
                }
                Toggle("流式显示回复", isOn: $configuration.streaming)
                Toggle("允许可信内网的明文 HTTP", isOn: $configuration.allowInsecureHTTP)
                if configuration.allowInsecureHTTP { Text("HTTP 不加密 API Key 和对话内容，仅用于你信任的内网。").font(.system(size: 10)).foregroundStyle(.orange) }
                Text("Key 保存在 macOS 钥匙串。保存后创建使用当前配置的新会话；原有历史保留，不会自动发送给新服务。").font(.system(size: 10)).foregroundStyle(.secondary)
            }.formStyle(.grouped).scrollDisabled(true).frame(height: configuration.allowInsecureHTTP ? 300 : 275).disabled(loading)
            if let message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 26).padding(.bottom, 12) }
            HStack {
                Button(loading ? String(localized: "连接中…") : String(localized: "测试并获取模型")) { Task { await loadModels() } }.disabled(loading || configuration.baseURL.isEmpty)
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.disabled(loading)
                Button("保存配置") { save() }.buttonStyle(.glassProminent).disabled(loading || configuration.baseURL.isEmpty || configuration.model.isEmpty)
            }.padding(24)
        }.frame(width: 620)
        .onAppear { configuration = agent.configuration; do { key = try ConnectionVault.read(id: AgentConfiguration.secretID) } catch { message = error.localizedDescription } }
    }
    private func loadModels() async {
        loading = true; message = nil
        defer { loading = false }
        do { models = try await OpenAICompatibleClient().models(configuration: configuration, key: key); message = String(localized: "连接成功 · 发现 \(models.count) 个模型。未发送数据库内容。") }
        catch { message = error.localizedDescription }
    }
    private func save() {
        do {
            _ = try configuration.endpoint("chat/completions")
            try ConnectionVault.save(key, id: AgentConfiguration.secretID)
            try configuration.save()
            dismiss(); saved()
        } catch { message = error.localizedDescription }
    }
}

/// Every execution keeps its first line visible, including while running and in history.
private struct AgentCommandPreview: View {
    var command: String
    @State private var expanded = false
    @State private var showFullCommand = false
    private var firstLine: String { String(command.split(separator: "\n", omittingEmptySubsequences: true).first ?? Substring(command)) }
    private var lengthy: Bool { command.count > 2_000 || command.components(separatedBy: "\n").count > 30 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: firstLine).font(.system(.caption, design: .monospaced)).lineLimit(1).textSelection(.enabled)
            if command != firstLine || command.count > 100 {
                if lengthy {
                    Button("在浮窗查看完整命令", systemImage: "arrow.up.left.and.arrow.down.right") { showFullCommand = true }
                } else {
                    DisclosureGroup("完整命令", isExpanded: $expanded) {
                        Text(verbatim: command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if lengthy {
                Button("在浮窗查看完整命令", systemImage: "arrow.up.left.and.arrow.down.right") { showFullCommand = true }
            }
        }.popover(isPresented: $showFullCommand) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("完整执行命令").font(.headline); Spacer(); AgentCopyButton(text: command, label: String(localized: "复制命令")); Button("关闭") { showFullCommand = false }.keyboardShortcut(.cancelAction) }
                ScrollView([.horizontal, .vertical]) { Text(verbatim: command).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(20).frame(width: 660, height: 420)
        }
    }
}
