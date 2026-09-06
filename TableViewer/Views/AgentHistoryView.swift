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
                            Text(session.updatedAt, style: .date).font(.caption2).foregroundStyle(.secondary)
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
