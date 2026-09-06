import SwiftUI

struct WorkspaceView: View {
    @Bindable var store: WorkspaceStore
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if store.active != nil { workspace }
                else { welcome }
                StatusBar(store: store)
            }
            .background(.background)
            .inspector(isPresented: Binding(get: { store.showInspector && WorkspaceTab.basic.contains(store.tab) }, set: { store.showInspector = $0 })) {
                InspectorView(store: store)
                    .inspectorColumnWidth(min: 260, ideal: 290, max: 380)
            }
        }
        .navigationTitle(store.active?.name ?? "TableViewer")
        .navigationSubtitle(store.active.map { String(localized: "\($0.kind.rawValue) · \($0.isDemo ? String(localized: "本地示例") : $0.kind == .sqlite ? String(localized: "本地文件") : $0.database)") } ?? String(localized: "你的数据，一目了然。"))
        .toolbar {
            ToolbarItemGroup {
                Button { store.editingProfile = nil; store.showConnectionSheet = true } label: { Label("新建连接", systemImage: "plus") }
                    .help("新建连接 ⌘N")
                Button { if store.allowNavigation() { store.tab = .query } } label: { Label("查询编辑器", systemImage: "terminal") }
                    .disabled(store.active == nil)
                Button { if store.allowNavigation() { store.tab = .agent } } label: { Label("Agent 助手", systemImage: "sparkles") }.disabled(store.active == nil)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button { Task { await store.refresh(reloadObjects: true) } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(store.active == nil || store.busy || store.hasChanges).help("刷新 ⌘R")
            }
            ToolbarItem {
                Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.26)) { store.showInspector.toggle() } } label: { Label("记录详情", systemImage: "sidebar.right") }
                    .help("显示记录详情")
            }
        }
        .sheet(isPresented: $store.showConnectionSheet) { ConnectionSheet(store: store, existing: store.editingProfile) }
        .sheet(isPresented: $store.showInsert) { InsertSheet(store: store) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("删除这条记录？", isPresented: $store.showDelete, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) { Task { await store.deleteRow() } }
        } message: { Text("将从 \(store.selectedObject?.name ?? String(localized: "数据库")) 中永久删除这条记录，此操作无法撤销。") }
        .confirmationDialog("移除连接？", isPresented: Binding(get: { store.removingProfile != nil }, set: { if !$0 { store.removingProfile = nil } }), titleVisibility: .visible) {
            if let profile = store.removingProfile { Button("移除连接", role: .destructive) { Task { await store.removeConnection(profile) } } }
        } message: { Text("仅移除保存的连接与凭据，数据库文件和数据会保留。") }
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: store.tab == .data && store.selectedObject?.isView == true ? "eye" : store.tab.symbol)
                    .font(.system(size: 22, weight: .light)).foregroundStyle(.tint)
                    .frame(width: 42, height: 42).background(.tint.opacity(0.08), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(WorkspaceTab.basic.contains(store.tab) && store.tab != .query ? store.selectedObject?.name ?? String(localized: "数据库") : store.tab == .query ? String(localized: "查询工作台") : store.tab == .shell ? "Mongo Shell" : store.tab == .replica ? String(localized: "副本集") : String(localized: "Agent 助手"))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(store.tab == .query ? (store.active?.kind == .mongodb ? String(localized: "MongoDB · JSON 命令") : String(localized: "SQL 编辑器 · ⌘↵ 运行")) : String(localized: "\(store.selectedObject?.schema.isEmpty == false ? store.selectedObject!.schema + " / " : "")\(store.active?.name ?? "")  /  \(store.selectedObject?.isView == true ? String(localized: "视图") : store.active?.kind == .mongodb ? String(localized: "集合") : String(localized: "数据表"))"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Picker("内容", selection: Binding(get: { store.tab }, set: { value in if store.allowNavigation() { store.tab = value; store.rowSearch = ""; if value == .data { Task { await store.refresh() } } } })) {
                    ForEach(WorkspaceTab.basic, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 190).disabled(store.busy).opacity(WorkspaceTab.basic.contains(store.tab) ? 1 : 0).allowsHitTesting(WorkspaceTab.basic.contains(store.tab))
            }.padding(.horizontal, 24).padding(.vertical, 22)
            Divider()
            if store.tab == .structure { StructureView(store: store) }
            else if store.tab == .query { QueryEditorView(store: store) }
            else if store.tab == .replica { ReplicaSetView(store: store) }
            else if store.tab == .shell { MongoShellView(store: store) }
            else if store.tab == .agent { AgentView(store: store) }
            else {
                tableActions
                dataGrid
                pagination
            }
        }
    }

    private var tableActions: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
            TextField("筛选当前页…", text: $store.rowSearch)
                .textFieldStyle(.plain).font(.system(size: 12)).frame(maxWidth: 220)
                .accessibilityLabel("筛选当前页")
            if !store.rowSearch.isEmpty { Button { store.rowSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            Spacer()
            Text("\(store.result.columns.count) 个字段").font(.system(size: 11)).foregroundStyle(.tertiary)
            Divider().frame(height: 14)
            Button { store.exportCSV() } label: { Label("导出", systemImage: "square.and.arrow.up") }.disabled(store.result.columns.isEmpty)
            Button { store.showInsert = true } label: { Label("添加记录", systemImage: "plus") }
                .disabled(store.selectedObject == nil || store.selectedObject?.isView == true || store.busy || store.hasChanges)
        }.buttonStyle(.borderless).controlSize(.small).padding(.horizontal, 24).frame(height: 48)
    }

    private var dataGrid: some View {
        ZStack {
            DataGrid(columns: store.result.columns, rows: store.visibleRows, selectedID: store.selectedRowID, sortColumn: store.sortColumn, ascending: store.sortAscending, selection: { store.selectRow($0) }, sort: { col in Task { await store.sort(by: col) } }, doubleClick: { store.showInspector = true })
            if store.visibleRows.isEmpty && !store.busy {
                ContentUnavailableView(store.rowSearch.isEmpty ? String(localized: "还没有记录") : String(localized: "没有匹配的记录"), systemImage: store.rowSearch.isEmpty ? "tray" : "line.3.horizontal.decrease", description: Text(store.rowSearch.isEmpty ? String(localized: "添加一条记录，或在查询工作台中开始探索。") : String(localized: "试试其他关键词；筛选仅作用于当前页。")))
            }
        }
    }

    private var pagination: some View {
        HStack(spacing: 12) {
            Text("\(store.visibleRows.count) 条记录").foregroundStyle(.secondary)
            if store.result.elapsed > 0 { Text("·").foregroundStyle(.quaternary); Text(String(format: "%.0f ms", store.result.elapsed * 1000)).foregroundStyle(.tertiary) }
            Spacer()
            Text("每页 200 条").foregroundStyle(.tertiary)
            Button { Task { await store.changePage(-1) } } label: { Image(systemName: "chevron.left") }.disabled(store.page == 0 || store.busy || store.hasChanges)
            Text("第 \(store.page + 1) 页").monospacedDigit().foregroundStyle(.secondary)
            Button { Task { await store.changePage(1) } } label: { Image(systemName: "chevron.right") }.disabled(!store.result.hasMore || store.busy || store.hasChanges)
        }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 24).frame(height: 43)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().scaledToFit().frame(width: 130, height: 130)
                .accessibilityHidden(true)
            VStack(spacing: 9) { Text("你的数据，一目了然。").font(.system(size: 30, weight: .semibold, design: .rounded)); Text("连接、探索、编辑。一个安静而专注的数据工作台。").foregroundStyle(.secondary) }
            Button("新建连接", systemImage: "plus") { store.editingProfile = nil; store.showConnectionSheet = true }.buttonStyle(.glassProminent).controlSize(.large)
            HStack(spacing: 24) { ForEach(DatabaseKind.allCases) { Label($0.rawValue, systemImage: $0.symbol) } }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 8)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusBar: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 7) {
                if store.busy { ProgressView().controlSize(.mini) }
                else { Circle().fill(store.active == nil ? Color.secondary : .green).frame(width: 6, height: 6) }
                Text(store.status)
                Spacer()
                if store.hasChanges { Label("有未保存的修改", systemImage: "pencil.circle.fill").foregroundStyle(.orange) }
                else if store.active?.isDemo == true { Text("本地示例 · 可自由编辑") }
                else { Text(store.active?.kind.rawValue ?? "TableViewer") }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 30)
        }
    }
}

struct SidebarView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().scaledToFit().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TableViewer").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("A little clarity for your data.").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 23).padding(.bottom, 23)
            List {
                Section {
                    ForEach(store.profiles) { profile in
                        Button { Task { await store.connect(profile) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: profile.kind.symbol).font(.system(size: 17)).foregroundStyle(profile.kind == .mongodb ? .green : .accentColor).frame(width: 25)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                    Text(profile.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                if store.active?.id == profile.id { Circle().fill(.green).frame(width: 6, height: 6) }
                            }.padding(.vertical, 5).contentShape(.rect)
                        }.buttonStyle(.plain)
                        .listRowBackground(store.active?.id == profile.id ? Color.accentColor.opacity(0.09) : Color.clear)
                        .contextMenu {
                            if !profile.isDemo {
                                Button("编辑连接…", systemImage: "slider.horizontal.3") { store.editingProfile = profile; store.showConnectionSheet = true }
                                Button("移除连接", systemImage: "minus.circle", role: .destructive) { store.removingProfile = profile }
                            }
                        }
                    }
                } header: { Text("连接").font(.system(size: 10, weight: .semibold)).tracking(1) }
                if store.active != nil {
                    Section("工作台") {
                        workspaceLink(.query)
                        if store.active?.kind == .mongodb { workspaceLink(.shell); workspaceLink(.replica) }
                        workspaceLink(.agent)
                    }
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                            TextField("查找表或集合", text: $store.objectSearch).textFieldStyle(.plain).font(.system(size: 11))
                        }.padding(.vertical, 3)
                        ForEach(store.visibleObjects) { object in
                            Button { Task { await store.chooseObject(object) } } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: object.isView ? "eye" : store.active?.kind == .mongodb ? "curlybraces" : "tablecells")
                                        .font(.system(size: 12)).foregroundStyle(store.selectedObject == object ? Color.accentColor : Color.secondary)
                                    Text(object.name).font(.system(size: 12)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if !object.schema.isEmpty && object.schema != "public" { Text(object.schema).font(.system(size: 9)).foregroundStyle(.tertiary) }
                                }.padding(.vertical, 5).contentShape(.rect)
                            }.buttonStyle(.plain)
                                .listRowBackground(store.selectedObject == object ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                    } header: {
                        HStack { Text(store.active?.kind == .mongodb ? String(localized: "集合") : String(localized: "数据表与视图")); Spacer(); Text("\(store.objects.count)").monospacedDigit() }.font(.system(size: 10, weight: .semibold))
                    }
                }
            }.listStyle(.sidebar).disabled(store.busy)
            Spacer(minLength: 0)
            HStack {
                Button { store.editingProfile = nil; store.showConnectionSheet = true } label: { Label("新建连接", systemImage: "plus.circle") }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("设置")
            }.buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary).padding(20)
        }
    }
    private func workspaceLink(_ tab: WorkspaceTab) -> some View {
        Button { if store.allowNavigation() { store.tab = tab } } label: {
            Label(tab == .agent ? String(localized: "Agent 助手") : tab == .query ? String(localized: "查询工作台") : tab.title, systemImage: tab.symbol).font(.system(size: 12)).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain).listRowBackground(store.tab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
