import SwiftUI
import AppKit
import os

struct WorkspaceView: View {
    @Bindable var store: WorkspaceStore
    @State private var trailingPanelWidth: CGFloat = 290
    private var trailingPanelVisible: Bool { store.tab == .agent ? store.showAgentSessions : store.showInspector && WorkspaceTab.basic.contains(store.tab) }
    @AppStorage("showAutomaticEstimates") private var showAutomaticEstimates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            detail
        }
        .navigationTitle(store.active?.name ?? "TableViewer")
        .onChange(of: showAutomaticEstimates) { _, visible in
            Task { await store.setBrowseEstimateVisible(visible) }
        }
        .navigationSubtitle(store.active.map { String(localized: "\($0.kind.rawValue) · \($0.isDemo ? String(localized: "本地示例") : $0.kind == .sqlite ? String(localized: "本地文件") : $0.database)") } ?? String(localized: "你的数据，一目了然。"))
        .toolbar {
            ToolbarItemGroup {
                Button { store.editingProfile = nil; store.showConnectionSheet = true } label: { Label("新建连接", systemImage: "plus") }
                    .help("新建连接 ⌘N")
                Button { if store.allowNavigation() { store.tab = .query } } label: { Label("查询编辑器", systemImage: "terminal") }
                    .disabled(store.active == nil)
                Button { store.openAgentWorkspace() } label: { Label("Agent 会话", systemImage: "sparkles") }
                    .disabled(store.active == nil)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button { Task { await store.refresh(reloadObjects: true) } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(store.active == nil || store.busy || store.hasChanges).help("刷新 ⌘R")
            }
            ToolbarItem {
                Button {
                    guard !store.hasChanges && !store.busy else { return }
                    store.readOnly.toggle()
                } label: { Label(store.readOnly ? String(localized: "只读模式") : String(localized: "允许编辑"), systemImage: store.readOnly ? "lock.fill" : "lock.open") }
                .disabled(store.busy || store.hasChanges)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : store.readOnlyNotice)
                .popover(isPresented: $store.readOnlyNotice) { Text("只读模式已阻止修改。点击锁按钮可切换模式。").padding(16) }
            }
            ToolbarItem {
                Button {
                    if store.tab == .agent { store.showAgentSessions.toggle() } else { store.showInspector.toggle() }
                } label: { Label(store.tab == .agent ? String(localized: "最近会话") : String(localized: "记录详情"), systemImage: "sidebar.right") }
                    .help(store.tab == .agent ? String(localized: "显示或隐藏最近会话") : String(localized: "显示记录详情"))
            }
        }
        .sheet(isPresented: $store.showConnectionSheet) { ConnectionSheet(store: store, existing: store.editingProfile) }
        .sheet(isPresented: $store.showCellEditor) { CellEditorSheet(store: store) }
        .sheet(isPresented: $store.showInsert) { InsertSheet(store: store) }
        .sheet(isPresented: $store.browseEstimateExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                if let estimate = store.browseEstimate {
                    Text(estimate.summary).font(.headline)
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: estimate.details).font(.caption.monospaced())
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                HStack {
                    Button("关闭查询预估") { store.setEstimatesEnabled(false) }
                    Spacer()
                    Button("完成") { store.browseEstimateExpanded = false }
                        .keyboardShortcut(.cancelAction)
                }
            }.padding(24).frame(width: 620, height: 420)
        }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("删除选中的记录？", isPresented: $store.showDelete, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) { Task { await store.deleteRow() } }
        } message: { Text(String(localized: "所选记录将永久删除，按顺序执行；失败时停止，先前删除不会自动撤销。记录数：") + String(store.selectedRowIDs.count)) }
        .confirmationDialog("移除连接？", isPresented: Binding(get: { store.removingProfile != nil }, set: { if !$0 { store.removingProfile = nil } }), titleVisibility: .visible) {
            if let profile = store.removingProfile { Button("移除连接", role: .destructive) { Task { await store.removeConnection(profile) } } }
        } message: { Text("仅移除保存的连接与凭据，数据库文件和数据会保留。") }
    }

    // Keep the transcript width independent of sidebar visibility. Only an
    // actual window or divider resize should reflow long answers.
    private var detail: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if store.tab == .agent {
                    AgentReadingColumn(
                        content: AnyView(AgentView(store: store, readingWidth: min(920, max(300, geometry.size.width - trailingPanelWidth))).tint(.accentColor)),
                        width: max(300, geometry.size.width - trailingPanelWidth),
                        originX: trailingPanelVisible ? 0 : trailingPanelWidth / 2,
                        animated: !reduceMotion
                    )
                }
                else if store.active != nil { workspace }
                else { welcome }
                StatusBar(store: store)
            }
            .padding(.trailing, trailingPanelVisible ? trailingPanelWidth : 0)
            .transaction { $0.animation = nil }
            .background(.background)
            .overlay(alignment: .trailing) {
                WorkspaceTrailingPanel(isPresented: trailingPanelVisible, width: $trailingPanelWidth) {
                    if store.tab == .agent { AgentRecentSessionsView(store: store) }
                    else { InspectorView(store: store) }
                }
            }
            .clipped()
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: store.tab == .data && store.selectedObject?.isView == true ? "eye" : store.tab.symbol)
                    .font(.system(size: 22, weight: .light)).foregroundStyle(.tint)
                    .frame(width: 42, height: 42).background(.tint.opacity(0.08), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(WorkspaceTab.basic.contains(store.tab) && store.tab != .query ? store.selectedObject?.name ?? String(localized: "数据库") : store.tab == .query ? String(localized: "查询工作台") : store.tab == .shell ? "Mongo Shell" : store.tab == .replica ? String(localized: "副本集") : store.tab == .overview ? String(localized: "对象概览") : store.tab == .relationships ? String(localized: "实体关系") : String(localized: "Agent 助手"))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(store.tab == .overview || store.tab == .relationships ? (store.active?.name ?? "") : store.tab == .query ? (store.active?.kind == .mongodb ? String(localized: "MongoDB · JSON 命令") : String(localized: "SQL 编辑器")) : String(localized: "\(store.selectedObject?.schema.isEmpty == false ? store.selectedObject!.schema + " / " : "")\(store.active?.name ?? "")  /  \(store.selectedObject?.isView == true ? String(localized: "视图") : store.active?.kind == .mongodb ? String(localized: "集合") : String(localized: "数据表"))"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Picker("内容", selection: Binding(get: { store.tab }, set: { value in if store.allowNavigation() { store.tab = value; store.rowSearch = ""; if value == .data { Task { await store.refresh() } } } })) {
                    ForEach(WorkspaceTab.basic, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 190).disabled(store.busy).opacity(WorkspaceTab.basic.contains(store.tab) ? 1 : 0).allowsHitTesting(WorkspaceTab.basic.contains(store.tab))
            }.padding(.horizontal, 24).padding(.vertical, 22)
            Divider()
            if store.tab == .overview {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text("让 Agent").font(.headline)
                        if !store.currentDatabaseSessions.isEmpty {
                            Menu("继续会话", systemImage: "bubble.left.and.bubble.right") {
                                ForEach(store.currentDatabaseSessions.sorted { ($0.running || !$0.pendingActions.isEmpty) && !($1.running || !$1.pendingActions.isEmpty) }) { session in
                                    Button {
                                        guard store.allowNavigation() else { return }
                                        store.agentLibrary.open(session.id); store.tab = .agent
                                    } label: {
                                        Text(session.title)
                                        if !session.phase.isEmpty { Text(session.phase) }
                                    }
                                }
                            }.fixedSize().controlSize(.small)
                        }
                        ScrollView(.horizontal) { AgentExampleButtons(action: store.startAgentExample) }
                    }.padding(.horizontal, 24).padding(.top, 20).disabled(store.busy)
                    ObjectBrowserView(objects: store.objects, kind: store.active?.kind ?? .sqlite, openObject: { object in Task { await store.chooseObject(object) } })
                }
            }
            else if store.tab == .relationships {
                Group {
                    if store.relationshipLoading { ProgressView() }
                    else if let failure = store.relationshipError { ContentUnavailableView("操作未完成", systemImage: "exclamationmark.triangle", description: Text(failure)) }
                    else { RelationshipView(relationships: store.relationships, kind: store.active?.kind ?? .sqlite, openObject: { object in Task { await store.chooseObject(object) } }) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: store.active?.id) { await store.loadRelationships() }
            }
            else if store.tab == .structure {
                Group {
                    if store.selectedObject == nil { ContentUnavailableView("选择一个数据库对象", systemImage: "tablecells", description: Text("从左侧或对象概览选择表、视图或集合后查看结构。")) }
                    else if let metadata = store.schemaMetadata, let object = store.selectedObject { StructureMetadataView(metadata: metadata, object: object, kind: store.active?.kind ?? .sqlite) }
                    else if let failure = store.structureError { ContentUnavailableView("操作未完成", systemImage: "exclamationmark.triangle", description: Text(failure)) }
                    else { ProgressView() }
                }.task(id: store.selectedObject?.id) { await store.loadStructure() }
            }
            else if store.tab == .query { QueryEditorView(store: store) }
            else if store.tab == .replica { ReplicaSetView(store: store) }
            else if store.tab == .shell { MongoShellView(store: store) }
            else if store.tab == .agent { AgentView(store: store) }
            else {
                tableActions
                if store.estimatesEnabled, store.showBrowseEstimate, let estimate = store.browseEstimate {
                    Button { store.browseEstimateExpanded = true } label: {
                        HStack {
                            Text(estimate.summary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 24).padding(.bottom, 6)
                } else if store.estimatesEnabled && store.showBrowseEstimate && store.browseEstimateLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在估算…").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(.horizontal, 24).padding(.bottom, 6)
                }
                dataGrid
                pagination
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tableActions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.setBrowseEstimateVisible(!store.showBrowseEstimate) }
            } label: {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(store.showBrowseEstimate ? Color.accentColor : Color.secondary)
            }
            .help(store.showBrowseEstimate ? String(localized: "隐藏自动估算栏") : String(localized: "显示自动估算栏"))
            .accessibilityLabel(store.showBrowseEstimate ? String(localized: "隐藏自动估算栏") : String(localized: "显示自动估算栏"))
            .disabled(!store.showBrowseEstimate && (store.busy || store.browseEstimateLoading))
            Menu {
                Button("关键词（当前页）") { store.filterIsCondition = false }
                Button(String(localized: store.active?.kind == .mongodb ? "JSON 条件" : "WHERE 条件")) { store.filterIsCondition = true }
            } label: { Image(systemName: "line.3.horizontal.decrease") }
            TextField(store.filterIsCondition ? (store.active?.kind == .mongodb ? "{ \"id\": 1 }" : "id = 1") : String(localized: "筛选当前页…"), text: store.filterIsCondition ? $store.condition : $store.rowSearch)
                .textFieldStyle(.plain).font(.system(size: 12)).frame(maxWidth: 220)
                .accessibilityLabel("筛选当前页")
            if store.filterIsCondition { Button("应用条件") { Task { await store.applyCondition() } }.disabled(store.busy || store.hasChanges) }
            if !store.rowSearch.isEmpty { Button { store.rowSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            Spacer()
            Text("\(store.result.columns.count) 个字段").font(.system(size: 11)).foregroundStyle(.tertiary)
            Divider().frame(height: 14)
            ExportMenu(store: store)
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("刷新").disabled(store.busy || store.hasChanges)
            Button(role: .destructive) { store.showDelete = true } label: { Image(systemName: "trash") }.help("删除所选行").disabled(!store.canEdit || store.selectedRowIDs.isEmpty || store.busy || store.hasChanges)
            Button { store.showInsert = true } label: { Label("添加记录", systemImage: "plus") }
                .disabled(store.readOnly || store.selectedObject == nil || store.selectedObject?.isView == true || store.busy || store.hasChanges)
        }.buttonStyle(.borderless).controlSize(.small).padding(.horizontal, 24).frame(height: 48)
    }

    private var dataGrid: some View {
        ZStack {
            DataGrid(columns: store.result.columns, rows: store.visibleRows, selectedID: store.selectedRowID, sortColumn: store.sortColumn, ascending: store.sortAscending, selection: { store.selectRow($0) }, sort: { col in Task { await store.sort(by: col) } }, doubleClick: {}, selectedIDs: store.selectedRowIDs, selectionChanged: { store.selectRows($0) }, editCell: { store.editCell(rowID: $0, column: $1) })
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
            Text("每页 \(store.pageSize) 条").foregroundStyle(.tertiary)
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
                    ForEach(store.visibleProfiles) { profile in
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
                            if profile.isDemo {
                                Button("隐藏示例数据库", systemImage: "eye.slash") { store.chooseDemoVisibility(hidden: true) }
                                    .disabled(!store.hasUserConnections)
                            } else {
                                Button("编辑连接…", systemImage: "slider.horizontal.3") { store.editingProfile = profile; store.showConnectionSheet = true }
                                Button("移除连接", systemImage: "minus.circle", role: .destructive) { store.removingProfile = profile }
                            }
                        }
                    }
                    if store.showDemoVisibilitySuggestion && store.active?.isDemo == false {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("已添加数据库，可以隐藏示例数据库。").font(.caption)
                            Button("隐藏示例数据库") { store.chooseDemoVisibility(hidden: true) }
                            Button("继续显示") { store.chooseDemoVisibility(hidden: false) }
                        }.padding(.vertical, 5)
                    }
                } header: {
                    HStack {
                        Text("连接").font(.system(size: 10, weight: .semibold)).tracking(1)
                        Spacer()
                        if store.hasUserConnections {
                            Menu {
                                Button(store.demoHidden ? String(localized: "显示示例数据库") : String(localized: "隐藏示例数据库")) {
                                    store.chooseDemoVisibility(hidden: !store.demoHidden)
                                }
                            } label: {
                                Label("连接", systemImage: "ellipsis").labelStyle(.iconOnly).foregroundStyle(.gray)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden)
                            .controlSize(.mini).tint(.gray).frame(width: 20)
                            .help(store.demoHidden ? String(localized: "显示示例数据库") : String(localized: "隐藏示例数据库"))
                        }
                    }
                }
                if store.active != nil {
                    Section("工作台") {
                        workspaceLink(.overview)
                        workspaceLink(.relationships)
                        workspaceLink(.query)
                        if store.active?.kind == .mongodb { workspaceLink(.shell); workspaceLink(.replica) }
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
                Button { store.openSettings() } label: { Image(systemName: "gearshape") }.help("设置")
            }.buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary).padding(20)
        }
    }
    private func workspaceLink(_ tab: WorkspaceTab) -> some View {
        Button { if store.allowNavigation() { store.tab = tab } } label: {
            Label(tab == .agent ? String(localized: "Agent 助手") : tab == .query ? String(localized: "查询工作台") : tab.title, systemImage: tab.symbol).font(.system(size: 12)).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.plain).listRowBackground(store.tab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

// Settle the workbench width once, outside the panel animation transaction.
// Native inspector resizing reflows all content on every animation frame.
private struct WorkspaceTrailingPanel<Content: View>: View {
    let isPresented: Bool
    @Binding var width: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        SlidingPanelHost(content: AnyView(content().tint(.accentColor).disabled(!isPresented).background(.background)), isPresented: isPresented, animated: !reduceMotion)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Rectangle().fill(.separator).frame(width: isPresented ? 1 : 0)
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = width }
                            width = min(380, max(260, (dragStartWidth ?? width) - value.translation.width))
                        }
                        .onEnded { _ in dragStartWidth = nil })
                    .help("拖动调整侧栏宽度")
            }
            .disabled(!isPresented)
            .allowsHitTesting(isPresented)
            .accessibilityHidden(!isPresented)
    }
}

// A separate hosting view keeps the workbench out of the animation's display
// updates. AppKit animates the layer-backed frame on the render server.
private struct SlidingPanelHost: NSViewRepresentable {
    let content: AnyView
    let isPresented: Bool
    let animated: Bool
    func makeNSView(context: Context) -> SlidingPanelNSView {
        SlidingPanelNSView(content: content)
    }
    func updateNSView(_ view: SlidingPanelNSView, context: Context) {
        view.host.rootView = content
        view.setPresented(isPresented, animated: animated)
    }
}

private final class SlidingPanelNSView: NSView {
    let host: NSHostingView<AnyView>
    private var presented: Bool?
    init(content: AnyView) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        host.wantsLayer = true
        host.sizingOptions = []
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        if host.frame.size != bounds.size {
            host.setFrameSize(bounds.size)
            host.setFrameOrigin(NSPoint(x: presented == true ? 0 : bounds.width, y: 0))
        }
    }
    func setPresented(_ visible: Bool, animated: Bool) {
        guard presented != visible else { return }
        let shouldAnimate = animated && presented != nil && bounds.width > 0
        presented = visible
        let origin = NSPoint(x: visible ? 0 : bounds.width, y: 0)
        animateWorkspaceFrame(animated: shouldAnimate, name: "Sidebar") {
            host.animator().setFrameOrigin(origin)
        }
    }
}

// Move the fixed-width reading column as a single layer too. Otherwise moving
// hundreds of offscreen Markdown/code/table views still incurs AppKit work.
private struct AgentReadingColumn: NSViewRepresentable {
    let content: AnyView
    let width: CGFloat
    let originX: CGFloat
    let animated: Bool
    func makeNSView(context: Context) -> AgentReadingColumnNSView {
        AgentReadingColumnNSView(content: content)
    }
    func updateNSView(_ view: AgentReadingColumnNSView, context: Context) {
        view.host.rootView = content
        view.update(width: width, originX: originX, animated: animated)
    }
}

private final class AgentReadingColumnNSView: NSView {
    let host: NSHostingView<AnyView>
    private var columnWidth: CGFloat = 0
    private var originX: CGFloat?
    init(content: AnyView) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        host.wantsLayer = true
        host.sizingOptions = []
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let size = NSSize(width: columnWidth, height: bounds.height)
        if host.frame.size != size { host.setFrameSize(size) }
    }
    func update(width: CGFloat, originX: CGFloat, animated: Bool) {
        if columnWidth != width { columnWidth = width; needsLayout = true }
        guard self.originX != originX else { return }
        let shouldAnimate = animated && self.originX != nil && bounds.height > 0
        self.originX = originX
        animateWorkspaceFrame(animated: shouldAnimate, name: "Agent Reading Column") {
            host.animator().setFrameOrigin(NSPoint(x: originX, y: 0))
        }
    }
}

@MainActor private func animateWorkspaceFrame(animated: Bool, name: StaticString, changes: () -> Void) {
    #if DEBUG
    // Measure the native animation interval separately from later AX snapshots.
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "TableViewer", category: .pointsOfInterest)
    let id = OSSignpostID(log: log)
    if animated { os_signpost(.begin, log: log, name: name, signpostID: id) }
    #endif
    NSAnimationContext.runAnimationGroup { context in
        context.duration = animated ? 0.22 : 0
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        changes()
    } completionHandler: {
        #if DEBUG
        if animated { os_signpost(.end, log: log, name: name, signpostID: id) }
        #endif
    }
}
