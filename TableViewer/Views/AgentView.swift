import SwiftUI

struct AgentView: View {
    @Bindable var store: WorkspaceStore
    var body: some View { AgentConversationView(store: store, agent: store.agent) }
}

private struct AgentConversationView: View {
    @Bindable var store: WorkspaceStore
    @Bindable var agent: AgentSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(agent.ready ? agent.configuration.model : String(localized: "配置你的 AI 助手"), systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("新对话", systemImage: "square.and.pencil") { agent.reset() }.disabled(agent.running || store.busy)
                Button("API 设置", systemImage: "slider.horizontal.3") { agent.showSettings = true }.disabled(agent.running || store.busy)
            }.buttonStyle(.borderless).controlSize(.small).padding(.horizontal, 24).frame(height: 48)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if agent.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: "sparkles").font(.system(size: 36, weight: .light)).foregroundStyle(.tint)
                                Text("一个懂数据库的搭档。").font(.system(size: 25, weight: .semibold, design: .rounded))
                                Text("解释结构、编写查询、一起排查问题。每一步数据库操作，都会先交给你确认。").font(.system(size: 12)).foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    prompt(String(localized: "帮我了解当前数据库"))
                                    prompt(String(localized: "写一个分页查询"))
                                    prompt(String(localized: "检查索引使用情况"))
                                }
                                if !agent.ready { Button("连接 OpenAI-compatible API", systemImage: "plus") { agent.showSettings = true }.buttonStyle(.glassProminent).padding(.top, 4) }
                            }.padding(.vertical, 35)
                        }
                        ForEach(agent.messages) { message in
                            if message.role == "tool" {
                                DisclosureGroup("已发送的工具结果") { Text(message.content ?? "").font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 11)).foregroundStyle(.secondary)
                            } else if let content = message.content, !content.isEmpty {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label(message.role == "user" ? String(localized: "你") : "Agent", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                    Text(LocalizedStringKey(content)).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(16).background(message.role == "user" ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025), in: .rect(cornerRadius: 13))
                            }
                        }
                        if agent.running {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) { ProgressView().controlSize(.mini); Text("Agent 正在思考…").font(.system(size: 11)).foregroundStyle(.secondary) }
                                if !agent.streamingText.isEmpty { Text(LocalizedStringKey(agent.streamingText)).font(.system(size: 13)).textSelection(.enabled) }
                            }.padding(16)
                        }
                        ForEach(agent.actions) { action in actionCard(action) }
                        if agent.canContinue {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("结果目前只在本机。确认后会将上面的工具结果发送给所配置的 API。").font(.system(size: 11)).foregroundStyle(.secondary)
                                Button("发送结果并继续", systemImage: "arrow.up.circle") { if let context = store.agentContext { agent.continueWithResults(context: context) } }.buttonStyle(.glassProminent).disabled(store.busy)
                            }
                        }
                        if let error = agent.error {
                            HStack(alignment: .top, spacing: 10) {
                                Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                                Spacer()
                                Button("重试") { if let context = store.agentContext { agent.retry(context: context) } }.disabled(agent.running || store.busy || !agent.actions.isEmpty)
                            }
                        }
                        Color.clear.frame(height: 1).id("agent-bottom")
                    }.padding(24).frame(maxWidth: 920)
                }
                .onChange(of: agent.messages.count) { withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { proxy.scrollTo("agent-bottom", anchor: .bottom) } }
                .onChange(of: agent.actions.count) { proxy.scrollTo("agent-bottom", anchor: .bottom) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("附带当前表结构", isOn: $agent.shareSchema).toggleStyle(.checkbox).font(.system(size: 10)).disabled(agent.running || !agent.actions.isEmpty)
                    Spacer()
                    Text(URLComponents(string: agent.configuration.baseURL)?.host ?? String(localized: "尚未配置 API")).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("描述你想完成的事情…", text: $agent.input, axis: .vertical).textFieldStyle(.plain).lineLimit(2...5).font(.system(size: 13)).padding(12).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12)).disabled(agent.running || !agent.actions.isEmpty)
                    if agent.running { Button("停止", systemImage: "stop.fill") { agent.stop() }.buttonStyle(.glass) }
                    else { Button("发送", systemImage: "arrow.up") { if let context = store.agentContext { agent.send(context: context) } }.buttonStyle(.glassProminent).disabled(agent.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy || !agent.actions.isEmpty) }
                }
                Text("发送内容包含对话历史\(agent.shareSchema ? String(localized: "及当前表结构") : "")；不会自动发送记录、密码或连接 URI。").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.sheet(isPresented: $agent.showSettings) { AgentSettingsView(agent: agent) }
    }

    private func prompt(_ text: String) -> some View { Button(text) { agent.input = text }.buttonStyle(.glass).controlSize(.small).font(.system(size: 11)) }
    private func actionCard(_ action: AgentAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(action.title, systemImage: action.outcome == nil ? "hand.raised" : action.failed ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(action.connectionName).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let reason = (try? jsonObject(action.call.function.arguments))?["reason"] as? String { Text(reason).font(.system(size: 12)).foregroundStyle(.secondary) }
            if let query = action.query {
                ScrollView { Text(query).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180).padding(12).background(.background, in: .rect(cornerRadius: 8))
                Text("查询将直接在这个连接上执行，写入语句会修改数据。").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let result = action.outcome {
                DisclosureGroup(action.failed ? String(localized: "查看错误（尚未发送）") : String(localized: "查看本地结果（尚未发送）")) {
                    ScrollView { Text(result).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220)
                }.font(.system(size: 11))
            } else {
                HStack { Spacer(); Button("拒绝") { agent.reject(action.id) }; Button("确认执行一次") { Task { await store.executeAgentAction(action.id) } }.buttonStyle(.glassProminent) }.controlSize(.small).disabled(store.busy || action.connectionID != store.active?.id)
            }
        }.padding(18).background(Color.accentColor.opacity(0.045), in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.18)) }
    }
}

struct AgentSettingsView: View {
    @Bindable var agent: AgentSession
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
                Text("Key 保存在 macOS 钥匙串。API 地址或模型变更后会清空当前对话，避免将旧内容发给新的服务。").font(.system(size: 10)).foregroundStyle(.secondary)
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
            agent.reset()
            agent.configuration = configuration; dismiss()
        } catch { message = error.localizedDescription }
    }
}
