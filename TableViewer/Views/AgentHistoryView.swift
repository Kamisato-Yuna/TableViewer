import SwiftUI

struct AgentHistoryView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var archived = false
    @State private var connectionID: UUID?
    @State private var renaming: AgentSession?
    @State private var title = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("所有 Agent 会话").font(.title2.bold())
                Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("历史仅保存在本机。归档可恢复，不会取消正在进行的任务。").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("按标题或数据库搜索", text: $search).textFieldStyle(.roundedBorder)
                Toggle("已归档", isOn: $archived).toggleStyle(.checkbox)
            }
            List {
                ForEach(store.agentLibrary.matching(search, archived: archived)) { session in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title).font(.headline).lineLimit(2)
                            Text(verbatim: "\(session.connection?.connectionName ?? "") · \(session.connection?.kind.rawValue ?? "")").font(.caption).foregroundStyle(.secondary)
                            if !session.phase.isEmpty { Text(session.phase).font(.caption).foregroundStyle(.tint) }
                            Text(session.historyDate, style: .date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("打开") { store.agentLibrary.open(session.id); store.tab = .agent; dismiss() }
                        Button("重命名") { title = session.title; renaming = session }
                        Button(session.archived ? String(localized: "恢复会话") : String(localized: "归档会话")) { store.agentLibrary.archive(session, archived: !session.archived) }

                    }.buttonStyle(.borderless).accessibilityElement(children: .contain).padding(.vertical, 8)
                }
            }.listStyle(.inset)
            if let session = renaming {
                HStack {
                    TextField("会话标题", text: $title).textFieldStyle(.roundedBorder)
                    Button("取消") { renaming = nil }
                    Button("保存") { store.agentLibrary.rename(session, to: title); renaming = nil }
                }
            }
            HStack {
                Picker("新会话所属数据库", selection: $connectionID) {
                    Text("选择数据库").tag(nil as UUID?)
                    ForEach(store.profiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                }
                Button("新建会话", systemImage: "plus") {
                    if let profile = store.profiles.first(where: { $0.id == connectionID }) { store.newAgentSession(for: profile); dismiss() }
                }.buttonStyle(.glassProminent).disabled(connectionID == nil)
            }
        }.padding(24).frame(width: 720, height: 580)
            .onAppear { connectionID = store.active?.id }
    }
}

struct AgentRecentSessionsView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近会话").font(.headline)
            Text(store.active?.name ?? "").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(store.currentDatabaseSessions.prefix(10))) { session in
                    Button { store.agentLibrary.open(session.id) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 4) {
                                Circle().fill(session.id == store.agent?.id ? Color.accentColor : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                                Rectangle().fill(.quaternary).frame(width: 1)
                            }.frame(width: 8)
                            VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.title).lineLimit(2)
                                Spacer()
                                if session.id == store.agent?.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            if !session.phase.isEmpty { Text(session.phase).font(.caption).foregroundStyle(.secondary) }
                            // Stable timestamps avoid ten per-second text updates while the panel animates.
                            Text(session.historyDate, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(session.id == store.agent?.id ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035), in: .rect(cornerRadius: 12))
                        }.fixedSize(horizontal: false, vertical: true).contentShape(.rect)
                    }.buttonStyle(.plain)
                }
                }
            }
        }.padding(16)
    }
}

struct AgentExampleButtons: View {
    var action: (String) -> Void
    var body: some View {
        HStack(spacing: 10) {
            ForEach([String(localized: "帮我了解当前数据库"), String(localized: "写一个分页查询"), String(localized: "检查索引使用情况")], id: \.self) { prompt in
                Button(prompt) { action(prompt) }
            }
        }.buttonStyle(.glass).controlSize(.small).font(.system(size: 11))
    }
}
