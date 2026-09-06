import SwiftUI

struct ReplicaSetView: View {
    @Bindable var store: WorkspaceStore
    @State private var automatic = false
    @State private var showRaw = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Label("拓扑与复制状态", systemImage: "point.3.connected.trianglepath.dotted").font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("每 10 秒刷新", isOn: $automatic).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                Button { Task { await store.refreshReplica() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(store.replicaLoading)
            }.padding(22)
            if let snapshot = store.replicaSnapshot {
                HStack(spacing: 14) {
                    metric(snapshot.setName, label: snapshot.topology, symbol: "server.rack")
                    metric("\(snapshot.members.count)", label: String(localized: "已发现成员"), symbol: "externaldrive.connected.to.line.below")
                    metric(snapshot.majority.map(String.init) ?? "—", label: String(localized: "多数派票数"), symbol: "checkmark.shield")
                    metric(snapshot.term.map(String.init) ?? "—", label: String(localized: "当前任期"), symbol: "arrow.triangle.branch")
                }.padding(.horizontal, 22).padding(.bottom, 18)
                if let notice = snapshot.notice { Label(notice, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.bottom, 12) }
                Table(snapshot.members) {
                    TableColumn("节点") { node in
                        VStack(alignment: .leading, spacing: 5) { Text(node.name).font(.system(size: 11, design: .monospaced)); if node.isSelf { Text("响应此请求的节点").font(.system(size: 9)).foregroundStyle(.tertiary) } }
                    }.width(min: 180, ideal: 220)
                    TableColumn("角色") { Text($0.role).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle($0.role == "PRIMARY" ? Color.accentColor : Color.secondary) }.width(95)
                    TableColumn("健康") { node in
                        Label(node.healthy.map { $0 ? String(localized: "在线") : String(localized: "异常") } ?? String(localized: "未知"), systemImage: node.healthy == true ? "checkmark.circle.fill" : node.healthy == false ? "exclamationmark.circle" : "questionmark.circle")
                            .font(.system(size: 10)).foregroundStyle(node.healthy == true ? Color.green : node.healthy == false ? Color.orange : Color.secondary)
                    }.width(70)
                    TableColumn("复制延迟") { Text($0.lagSeconds.map { String(format: "%.1f s", $0) } ?? "—").font(.system(size: 11, design: .monospaced)) }.width(85)
                    TableColumn("Ping") { Text($0.pingMS.map { String(format: "%.0f ms", $0) } ?? "—").font(.system(size: 11, design: .monospaced)) }.width(70)
                    TableColumn("同步来源") { Text($0.syncSource.isEmpty ? "—" : $0.syncSource).font(.system(size: 10, design: .monospaced)).help($0.heartbeatMessage) }
                }
                HStack {
                    Text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .standard)) · 延迟基于响应节点的心跳快照").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("原始状态", systemImage: "curlybraces") { showRaw = true }.buttonStyle(.borderless).font(.system(size: 11))
                }.padding(18)
            } else if store.replicaLoading { ProgressView("读取副本集状态…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ContentUnavailableView("尚无副本集状态", systemImage: "server.rack", description: Text(store.replicaError ?? String(localized: "刷新以查看当前 MongoDB 连接的拓扑。"))) }
            if let error = store.replicaError, store.replicaSnapshot != nil { Text("刷新失败，以上为上次快照：\(error)").font(.system(size: 11)).foregroundStyle(.orange).padding(12) }
        }
        .task(id: store.active?.id) { await store.refreshReplica() }
        .task(id: automatic) {
            guard automatic else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)); try Task.checkCancellation() } catch { return }
                await store.refreshReplica()
            }
        }
        .sheet(isPresented: $showRaw) {
            VStack(alignment: .leading, spacing: 16) {
                Text("副本集原始状态").font(.headline)
                ScrollView { Text(store.replicaSnapshot?.rawJSON ?? "{}").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack { Spacer(); Button("完成") { showRaw = false }.keyboardShortcut(.cancelAction) }
            }.padding(24).frame(width: 720, height: 560)
        }
    }
    private func metric(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(label, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
    }
}
