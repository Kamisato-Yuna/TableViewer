import SwiftUI

struct QueryEditorView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("queryHorizontal") private var horizontal = false
    @State private var showRunHint = false
    var body: some View {
        // Keep scrolling content beneath the system material so the header
        // samples the document, rather than an empty background above it.
        ZStack(alignment: .top) {
            if store.selectedScriptID == nil {
                ContentUnavailableView {
                    Label("新建命名脚本", systemImage: "doc.badge.plus")
                } description: {
                    Text("为脚本命名后开始编辑，输入内容会自动保存到本地 .sql 文件。")
                } actions: {
                    Button("新建脚本") { store.nameScript() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let sideBySide = horizontal && geometry.size.width >= 529
                    QueryPaneSplit(vertical: sideBySide) {
                        editor.padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    } second: {
                        results.padding(.top, sideBySide ? 42 : 0).padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            GlassEffectContainer(spacing: 6) {
            HStack(spacing: 8) {
                GeometryReader { tabGeometry in
                ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(store.openScripts) { script in
                            ScriptTabItem(title: script.name,
                                          width: max(156, (tabGeometry.size.width - 6) / CGFloat(max(1, store.openScripts.count))),
                                          isSelected: store.selectedScriptID == script.id,
                                          canClose: store.runningScriptID != script.id,
                                          select: { store.openScript(script.id) },
                                          close: { store.closeScript(script.id) },
                                          rename: { store.nameScript(script.id) })
                                .id(script.id)
                        }
                    }.padding(3)
                }.scrollIndicators(.hidden)
                    .background(.thinMaterial, in: Capsule())
                    .onChange(of: store.selectedScriptID, initial: true) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                }.frame(height: 44)
                Button { store.nameScript() } label: { Image(systemName: "plus").frame(width: 32, height: 32).glassEffect(.regular, in: Circle()) }.help("新建命名脚本").accessibilityLabel("新建命名脚本")
                Menu {
                    Section("最近 10 个脚本") {
                        let recent = Array(store.scripts.scripts.filter { $0.connectionID == store.active?.id }.sorted { $0.lastUsed > $1.lastUsed }.prefix(10))
                        if recent.isEmpty { Text("暂无最近脚本") }
                        ForEach(recent) { script in
                            Button(script.name) { store.openScript(script.id) }
                        }
                    }
                    Divider()
                    Button("更多历史…") { openWindow(id: "script-history") }
                } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 18, height: 16) }
                .menuStyle(.borderlessButton)
                .help("脚本历史").accessibilityLabel("脚本历史")
                Button { horizontal.toggle() } label: { Image(systemName: horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1").frame(width: 18, height: 16) }.help("切换上下或左右分栏")
            }.buttonStyle(.plain).tint(.primary).controlSize(.regular)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 4)
            }
            .frame(height: 50)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(12)
        .onAppear { if store.selectedScriptID == nil { store.nameScript() } }
        .alert(store.renamingScriptID == nil ? String(localized: "新建脚本") : String(localized: "重命名脚本"), isPresented: $store.showScriptName) {
            TextField("脚本名称", text: $store.scriptName)
            Button("取消", role: .cancel) {}
            Button("保存") { store.saveScriptName() }.disabled(store.scriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $store.showQueryApproval) {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.estimatesEnabled ? String(localized: "执行前规模预估") : String(localized: "执行确认")).font(.title2)
                ScrollView {
                    ForEach(Array(store.estimates.enumerated()), id: \.offset) { index, estimate in
                        VStack(alignment: .leading) {
                            Label(String(localized: "语句") + " \(index + 1): " + estimate.summary, systemImage: estimate.severity == .excessive ? "exclamationmark.octagon" : "info.circle")
                                .foregroundStyle(estimate.severity == .excessive ? Color.red : .primary)
                            if !estimate.details.isEmpty { DisclosureGroup("计划详情") { Text(verbatim: estimate.details).font(.caption.monospaced()).textSelection(.enabled) } }
                        }.padding(.bottom, 12)
                    }
                }
                Text("估算不保证运行时间。首次失败停止；先前自动提交的写入不会回滚，显式事务由数据库处理。").font(.caption).foregroundStyle(.secondary)
                HStack { if store.estimatesEnabled { Button("关闭查询预估") { store.setEstimatesEnabled(false); store.showQueryApproval = false; store.pendingQuery = nil } }; Spacer(); Button("取消", role: .cancel) { store.showQueryApproval = false; store.pendingQuery = nil }; Button("继续执行") { store.showQueryApproval = false; Task { await store.runQuery(approved: true) } }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 620, height: 420)
        }
    }
    private var editor: some View {
        let scriptID = store.selectedScriptID
        let initialText = store.query
        // SwiftUI may update the outgoing editor before dismantling it. Its binding
        // must continue to refer to that script, not the newly selected script.
        let scriptText = Binding<String>(
            get: { [weak store] in
                guard let store else { return initialText }
                if store.selectedScriptID == scriptID { return store.query }
                if let scriptID, let view = store.queryEditorViews[scriptID]?.documentView as? NSTextView { return view.string }
                return initialText
            },
            set: { [weak store] value in
                guard let store, store.selectedScriptID == scriptID else { return }
                store.query = value
            }
        )
        return ZStack(alignment: .top) {
            CodeEditor(text: scriptText, isJSON: store.active?.kind == .mongodb,
                       completions: store.objects.flatMap {
                           let plain = $0.name.range(of: "^[a-z_][a-z0-9_]*$", options: .regularExpression) != nil
                           return [plain ? $0.name : quoteIdentifier($0.name), $0.qualifiedName]
                       },
                       // 50 pt tabs - 8 pt pane inset + 40 pt editor toolbar.
                       topContentInset: store.showSlowQuerySuggestion ? 118 : 82,
                       selectionChanged: { [weak store] range in
                           guard let store, store.selectedScriptID == scriptID else { return }
                           store.querySelection = range
                       },
                       retainedView: scriptID.flatMap { store.queryEditorViews[$0] },
                       retainView: { [weak store] view in
                           if let scriptID { store?.queryEditorViews[scriptID] = view }
                       }).id(scriptID)
                .clipped()

            VStack(spacing: 0) {
            HStack {
                Text(store.active?.kind == .mongodb ? "MongoDB JSON" : "SQL").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if showRunHint {
                    Text("也可以按 ⌘↵ 运行查询").font(.caption).lineLimit(2)
                        .padding(.horizontal, 10).padding(.vertical, 5).glassEffect()
                        .task { try? await Task.sleep(for: .seconds(4)); showRunHint = false }
                }
                Button {
                    let defaults = UserDefaults.standard
                    let clicks = defaults.integer(forKey: "runButtonClicks") + 1
                    defaults.set(clicks, forKey: "runButtonClicks")
                    if clicks == 3 { showRunHint = true }
                    Task { await store.runQuery() }
                } label: { Label(store.querySelection.length > 0 ? String(localized: "运行选区") : String(localized: "运行"), systemImage: "play.fill") }
                    .buttonStyle(.glassProminent).controlSize(.small).disabled(store.busy || store.query.isEmpty)

            }.padding(.horizontal, 8).frame(height: 40)
            if store.showSlowQuerySuggestion {
                HStack {
                    Text("查询已超过 5 秒，可开启查询前预估。").font(.caption)
                    Spacer()
                    Button("开启") { store.setEstimatesEnabled(true) }
                    Button("暂不") { store.showSlowQuerySuggestion = false }
                }.padding(8)
            }
            }
            .background(.bar)
            .padding(.top, 42)

        }
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("查询结果").font(.headline)
                if store.statementResults.count > 1 {
                    Picker("结果", selection: $store.selectedResultIndex) {
                        ForEach(Array(store.statementResults.enumerated()), id: \.offset) { index, statement in
                            Text(String(localized: "语句") + " \(index + 1)" + (statement.failure == nil ? "" : " ⚠︎")).tag(index)
                        }
                    }.labelsHidden().frame(maxWidth: 150)
                    .onChange(of: store.selectedResultIndex) { _, index in
                        if store.statementResults.indices.contains(index) { store.queryResult = store.statementResults[index].result ?? QueryResult() }
                    }
                }
                Spacer()
                ExportMenu(store: store)
                Button { Task { await store.runQuery() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.busy)
            }.controlSize(.small).padding(.horizontal, 8).frame(height: 40)
            if let failure = store.queryFailure {
                VStack(alignment: .leading) {
                    Label("执行失败，后续语句未运行；先前自动提交的写入不会回滚。", systemImage: "exclamationmark.triangle").font(.caption)
                    DisclosureGroup("错误详情") { ScrollView { Text(verbatim: failure).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140) }
                }.padding(12).background(.red.opacity(0.05))
            }
            if store.queryHasRun && !store.queryResult.columns.isEmpty {
                DataGrid(columns: store.queryResult.columns, rows: store.queryResult.rows, selectedID: store.querySelectedRows.first, selectedIDs: store.querySelectedRows, selectionChanged: { store.querySelectedRows = $0 })
            } else {
                ContentUnavailableView(store.queryHasRun ? String(localized: "执行结束") : String(localized: "从一个好问题开始"), systemImage: "text.magnifyingglass", description: Text(store.queryHasRun ? String(localized: "\(store.queryResult.affectedRows) 行受影响。") : String(localized: "写下查询，按 ⌘↵，让数据给出答案。")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if store.queryResult.hasMore { Text("当前仅显示前 1,000 行或首批文档；请通过 LIMIT / skip 缩小范围。").font(.caption2).padding(8) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// A nested system split view must use the query pane's bounds, rather than
// expanding into NavigationSplitView's sidebar safe area on macOS 27.
private struct ScriptTabItem: View {
    let title: String
    var width: CGFloat = 156
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void
    let rename: () -> Void
    @State private var hovering = false
    @FocusState private var focus: Control?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Control: Hashable { case title, close }
    private var showsClose: Bool { hovering || focus != nil }

    var body: some View {
        Button(action: select) {
            Text(title).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14).frame(width: width, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focused($focus, equals: .title).help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("关闭脚本")) { if canClose { close() } }
        .glassEffect(isSelected ? .regular : .identity, in: Capsule())
        .overlay(alignment: .leading) {
            if showsClose {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focused($focus, equals: .close)
                .help("关闭脚本").accessibilityLabel("关闭脚本").disabled(!canClose)
                .padding(.leading, 5).transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsClose)
        .contextMenu {
            Button("重命名…", action: rename)
            Button("关闭脚本", action: close).disabled(!canClose)
        }
    }
}

// Own the split view so only this divider's drawing changes. Native dragging,
// cursor feedback and accessibility remain NSSplitView behavior.
private final class QueryDividerlessSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 8 }
    override func drawDivider(in rect: NSRect) {}
}

private struct QueryPaneSplit<First: View, Second: View>: NSViewRepresentable {
    var vertical: Bool
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    final class Coordinator: NSObject, NSSplitViewDelegate {
        let first: NSHostingView<First>
        let second: NSHostingView<Second>
        init(first: First, second: Second) {
            self.first = NSHostingView(rootView: first)
            self.second = NSHostingView(rootView: second)
            super.init()
            self.first.safeAreaRegions = []; self.second.safeAreaRegions = []
            self.first.sizingOptions = []; self.second.sizingOptions = []
        }
        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            min(splitView.isVertical ? 260 : 150, (splitView.isVertical ? splitView.bounds.width : splitView.bounds.height) / 2)
        }
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            return max(length / 2, length - (splitView.isVertical ? 260 : 150) - splitView.dividerThickness)
        }
        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
    }
    func makeCoordinator() -> Coordinator { Coordinator(first: first(), second: second()) }
    func makeNSView(context: Context) -> NSSplitView {
        let split = QueryDividerlessSplitView()
        split.isVertical = vertical
        split.dividerStyle = .thin
        split.delegate = context.coordinator
        split.addArrangedSubview(context.coordinator.first)
        split.addArrangedSubview(context.coordinator.second)
        return split
    }
    func updateNSView(_ split: NSSplitView, context: Context) {
        context.coordinator.first.rootView = first()
        context.coordinator.second.rootView = second()
        if split.isVertical != vertical {
            split.isVertical = vertical
            split.adjustSubviews()
        }
    }
}

private struct QuerySplitContainer<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content
    func makeNSView(context: Context) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: content())
        host.safeAreaRegions = []
        host.sizingOptions = []
        return host
    }
    func updateNSView(_ host: NSHostingView<Content>, context: Context) {
        host.rootView = content()
    }
}

struct ScriptLibraryView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @AppStorage("scriptCleanupDays") private var days = 90
    @AppStorage("scriptAutoCleanup") private var automatic = false
    @State private var deleting = Set<UUID>()
    @State private var confirm = false
    @State private var confirmAutomatic = false
    private func returnToWorkspace() {
        dismissWindow(id: "script-history")
        openWindow(id: "workspace")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("全部本地脚本").font(.title2); Spacer(); Button("完成") { dismissWindow(id: "script-history") } }
            Text("脚本内容保存为 .sql，显示名称保存在本地目录索引。关闭选项卡会保留脚本；清理会永久删除文件。").font(.caption).foregroundStyle(.secondary)
            List(store.scripts.scripts.sorted { $0.lastUsed > $1.lastUsed }) { script in
                HStack {
                    VStack(alignment: .leading) { Text(script.name); Text((store.profiles.first(where: { $0.id == script.connectionID })?.name ?? String(localized: "连接已删除")) + " · " + script.lastUsed.formatted()).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("打开") { Task { if await store.openHistoricalScript(script.id) { returnToWorkspace() } } }.disabled(store.busy || store.hasChanges)
                    Button("重命名…") { returnToWorkspace(); store.nameScript(script.id) }.disabled(store.busy || store.hasChanges)
                }
            }
            HStack {
                Stepper(String(localized: "未使用天数：") + "\(days)", value: $days, in: 1...3650)
                Button("清理未使用脚本") { deleting = Set(store.scripts.unused(days: days).map(\.id)); confirm = true }
                Button("清理全部", role: .destructive) { deleting = Set(store.scripts.scripts.map(\.id)); confirm = true }
            }.controlSize(.small).disabled(store.busy || store.hasChanges)
            Toggle("启动时自动清理未使用且已关闭的脚本", isOn: Binding(get: { automatic }, set: { if $0 { confirmAutomatic = true } else { automatic = false } }))
        }.padding(24).frame(width: 680, height: 500)
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog("永久删除所选脚本？", isPresented: $confirm, titleVisibility: .visible) {
            Button(String(localized: "删除") + " \(deleting.count)", role: .destructive) {
                do {
                    if let selected = store.selectedScriptID, deleting.contains(selected) { store.selectedScriptID = nil; store.query = "" }
                    try store.scripts.delete(deleting)
                    for id in deleting { store.queryEditorViews.removeValue(forKey: id); store.scriptResults.removeValue(forKey: id) }
                } catch { store.report(error) }
            }
        } message: { Text("删除后无法撤销，数据库数据不受影响。") }
        .confirmationDialog("启用自动清理？", isPresented: $confirmAutomatic, titleVisibility: .visible) {
            Button("启用自动清理", role: .destructive) { automatic = true }
        } message: { Text("每次启动会永久删除超过所设未使用天数且已关闭的脚本。可随时关闭；已删除文件无法恢复。") }
    }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isJSON = false
    var completions: [String] = []
    var topContentInset: CGFloat = 0
    var selectionChanged: (NSRange) -> Void = { _ in }
    var retainedView: NSScrollView? = nil
    var retainView: (NSScrollView) -> Void = { _ in }
    @AppStorage("editorFont") private var fontName = "SF Mono"
    @AppStorage("editorSize") private var fontSize = 13.0
    @AppStorage("editorLigatures") private var ligatures = false
    @AppStorage("editorLineNumbers") private var lineNumbers = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        if let retainedView, let view = retainedView.documentView as? QueryTextView {
            view.delegate = context.coordinator
            return retainedView
        }
        let scroll = NSScrollView()
        // NSRulerView can draw outside its bounds on recent macOS versions.
        // Clip at the scroll view, keeping the ruler and text in the code viewport.
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        let view = QueryTextView(frame: .zero)
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        view.delegate = context.coordinator; view.isRichText = false; view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.backgroundColor = .textBackgroundColor
        view.setAccessibilityLabel(String(localized: "查询代码编辑器"))
        scroll.verticalRulerView = QueryLineRuler(textView: view)
        scroll.hasVerticalRuler = true
        scroll.drawsBackground = false
        retainView(scroll)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? QueryTextView else { return }
        let font = NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let changed = view.font != font || view.ligaturesEnabled != ligatures
        view.font = font; view.ligaturesEnabled = ligatures
        view.sqlCandidates = isJSON ? [] : completions
        view.isJSON = isJSON
        scroll.rulersVisible = lineNumbers
        if scroll.contentInsets.top != topContentInset {
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
            scroll.scrollerInsets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
            view.scrollRangeToVisible(view.selectedRange())
        }
        if changed || view.string != text, let ruler = scroll.verticalRulerView as? QueryLineRuler { ruler.updateMetrics(font: font, text: text) }
        if view.string != text {
            view.string = text
            view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: 0))
            context.coordinator.highlight(view)
        } else if changed { context.coordinator.highlight(view); view.scrollRangeToVisible(view.selectedRange()) }
        if context.coordinator.needsSelectionRestore {
            context.coordinator.needsSelectionRestore = false
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak view, weak coordinator] in
                guard let view, let coordinator, view.delegate === coordinator else { return }
                coordinator.parent.selectionChanged(view.selectedRange())
                view.window?.makeFirstResponder(view)
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var needsSelectionRestore = true
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? QueryTextView else { return }
            if parent.text != view.string { parent.text = view.string }
            highlight(view)
            if let ruler = view.enclosingScrollView?.verticalRulerView as? QueryLineRuler {
                ruler.updateMetrics(font: view.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular), text: view.string)
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selectionChanged(view.selectedRange()); view.needsDisplay = true
            view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
        func highlight(_ view: QueryTextView) {
            guard !view.hasMarkedText(), let storage = view.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            // Attribute-only syntax coloring must never become an undo operation.
            view.undoManager?.disableUndoRegistration()
            storage.beginEditing()
            storage.addAttributes([.foregroundColor: NSColor.labelColor, .font: view.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .ligature: view.ligaturesEnabled ? 1 : 0], range: range)
            let patterns: [(String, NSColor)] = [
                (#"\b(?i:SELECT|FROM|WHERE|ORDER|BY|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|JOIN|LEFT|ON|AND|OR|NOT|NULL|AS|GROUP|HAVING|DESC|ASC|BEGIN|COMMIT|ROLLBACK|TRUE|FALSE)\b"#, .systemPurple),
                (#"'(?:[^']|'')*'|"(?:[^"\\]|\\.)*""#, .systemTeal),
                (#"\b[0-9]+\b"#, .systemOrange),
                (#"--[^\n]*"#, .secondaryLabelColor)
            ]
            for (pattern, color) in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in expression.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
            }
            storage.endEditing(); view.undoManager?.enableUndoRegistration()
            view.typingAttributes = [.font: view.font!, .foregroundColor: NSColor.labelColor, .ligature: view.ligaturesEnabled ? 1 : 0]
            view.needsDisplay = true; view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

final class QueryTextView: NSTextView {
    var sqlCandidates: [String] = []
    var isJSON = false
    private var showingCompletion = false
    private var completionPanel: NSPanel?
    private weak var completionParent: NSWindow?
    private var visibleCandidates: [String] = []
    private var candidateIndex = 0
    private var candidateRange = NSRange(location: NSNotFound, length: 0)
    private func hideCompletions() {
        if let completionPanel { completionParent?.removeChildWindow(completionPanel); completionPanel.orderOut(nil) }
        completionParent = nil
        showingCompletion = false; visibleCandidates = []
    }
    override func complete(_ sender: Any?) {
        guard window != nil else { return }
        let range = rangeForUserCompletion
        guard range.location != NSNotFound else { hideCompletions(); return }
        var index = 0
        visibleCandidates = Array((completions(forPartialWordRange: range, indexOfSelectedItem: &index) ?? []).prefix(8))
        guard !visibleCandidates.isEmpty else { hideCompletions(); return }
        candidateIndex = 0; candidateRange = range; showingCompletion = true
        displayCandidates()
    }
    private func displayCandidates() {
        guard let window, showingCompletion else { return }
        let panel = completionPanel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        completionPanel = panel
        panel.isFloatingPanel = false; panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = NSHostingView(rootView: SQLCompletionList(candidates: visibleCandidates, selected: candidateIndex) { [weak self] index in self?.acceptCandidate(index) })
        let caret = firstRect(forCharacterRange: NSRange(location: selectedRange().location, length: 0), actualRange: nil)
        let height = CGFloat(visibleCandidates.count * 28 + 8)
        let screen = window.screen?.visibleFrame ?? caret
        let x = max(screen.minX, min(caret.minX, screen.maxX - 320))
        let y = caret.minY - height < screen.minY ? caret.maxY : caret.minY - height
        panel.setFrame(NSRect(x: x, y: y, width: 320, height: height), display: true)
        completionParent = window
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }
    private func acceptCandidate(_ index: Int) {
        guard visibleCandidates.indices.contains(index), !hasMarkedText(), candidateRange.location != NSNotFound,
              NSMaxRange(candidateRange) <= (string as NSString).length else { hideCompletions(); return }
        let word = visibleCandidates[index], range = candidateRange
        hideCompletions(); breakUndoCoalescing()
        insertText(word, replacementRange: range); breakUndoCoalescing()
    }
    override func keyDown(with event: NSEvent) {
        if showingCompletion && !hasMarkedText() {
            switch event.keyCode {
            case 53: hideCompletions(); return
            case 36, 48: acceptCandidate(candidateIndex); return
            case 125: candidateIndex = (candidateIndex + 1) % visibleCandidates.count; displayCandidates(); return
            case 126: candidateIndex = (candidateIndex + visibleCandidates.count - 1) % visibleCandidates.count; displayCandidates(); return
            default: hideCompletions()
            }
        }
        super.keyDown(with: event)
    }
    override func resignFirstResponder() -> Bool { hideCompletions(); return super.resignFirstResponder() }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        hideCompletions(); super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    private static let keywords = "SELECT FROM WHERE ORDER BY LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE JOIN LEFT RIGHT INNER OUTER ON AND OR NOT NULL AS GROUP HAVING DESC ASC BEGIN COMMIT ROLLBACK TRUE FALSE DISTINCT UNION ALL WITH CASE WHEN THEN ELSE END COUNT SUM AVG MIN MAX".components(separatedBy: " ")
    private var completionEnabled: Bool { !isJSON && (UserDefaults.standard.object(forKey: "editorCompletion") as? Bool ?? true) }
    override var rangeForUserCompletion: NSRange {
        guard completionEnabled, !hasMarkedText(), selectedRange().length == 0 else { return NSRange(location: NSNotFound, length: 0) }
        let source = string as NSString
        let end = min(selectedRange().location, source.length)
        let prefix = source.substring(to: end)
        // Exclude SQL strings, line/block comments and PostgreSQL dollar strings.
        var quoted: Character?; var lineComment = false; var depth = 0; var dollar: String?; var identifierQuote = false; var identifierStart = 0
        let chars = Array(prefix); var i = 0
        while i < chars.count {
            let c = chars[i], next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if identifierQuote {
                if c == "\"" {
                    if next == "\"" { i += 2; continue }
                    identifierQuote = false
                }
                i += 1; continue
            }
            if lineComment { if c == "\n" { lineComment = false }; i += 1; continue }
            if depth > 0 {
                if c == "/" && next == "*" { depth += 1; i += 2 }
                else if c == "*" && next == "/" { depth -= 1; i += 2 }
                else { i += 1 }; continue
            }
            if let delimiter = dollar {
                if String(chars[i...]).hasPrefix(delimiter) { i += delimiter.count; dollar = nil } else { i += 1 }; continue
            }
            if let quote = quoted {
                if c == quote { if next == quote { i += 2; continue }; quoted = nil }
                else if c == "\\" && quote == "'" { i += 2; continue }
                i += 1; continue
            }
            if c == "-" && next == "-" { lineComment = true; i += 2; continue }
            if c == "/" && next == "*" { depth = 1; i += 2; continue }
            if c == "\"" { identifierQuote = true; identifierStart = i; i += 1; continue }
            if c == "'" { quoted = c; i += 1; continue }
            if c == "$", let close = chars[(i + 1)...].firstIndex(of: "$") {
                let tag = chars[(i + 1)..<close]
                if tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { dollar = String(chars[i...close]); i = close + 1; continue }
            }
            i += 1
        }
        guard quoted == nil, !lineComment, depth == 0, dollar == nil else { return NSRange(location: NSNotFound, length: 0) }
        var start = identifierQuote ? String(chars[..<identifierStart]).utf16.count : end
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.$\""))
        while start > 0, let scalar = UnicodeScalar(source.character(at: start - 1)), allowed.contains(scalar) { start -= 1 }
        guard start < end else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: start, length: end - start)
    }
    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard completionEnabled, !hasMarkedText(), charRange.location != NSNotFound, NSMaxRange(charRange) <= (string as NSString).length else { return nil }
        let prefix = (string as NSString).substring(with: charRange)
        let candidates = Array(Set(Self.keywords + sqlCandidates)).filter {
            $0.replacingOccurrences(of: "\"", with: "").lowercased().hasPrefix(prefix.replacingOccurrences(of: "\"", with: "").lowercased()) && $0 != prefix
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        index.pointee = 0
        showingCompletion = !candidates.isEmpty
        return Array(candidates.prefix(40))
    }
    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        // Candidates stay in the native popup; preview must not edit/autosave SQL
        // or turn its suggested suffix into the query execution selection.
        guard flag else { return }
        showingCompletion = false
        guard movement != NSTextMovement.cancel.rawValue else { return }
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: true)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasMarked = hasMarkedText()
        super.insertText(insertString, replacementRange: replacementRange)
        guard !wasMarked, !hasMarkedText(), completionEnabled, let inserted = insertString as? String,
              inserted.count == 1, inserted.first?.isLetter == true else { return }
        let range = rangeForUserCompletion
        guard range.location != NSNotFound, range.length >= 2 else { return }
        complete(nil)
    }
    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText(), !showingCompletion else { super.insertTab(sender); return }
        indentSelection(outdent: false)
    }
    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText(), !showingCompletion else { super.insertBacktab(sender); return }
        indentSelection(outdent: true)
    }
    private func indentSelection(outdent: Bool) {
        let spaces = UserDefaults.standard.object(forKey: "editorTabSpaces") as? Bool ?? true
        let width = max(1, min(16, UserDefaults.standard.object(forKey: "editorIndentWidth") as? Int ?? 4))
        let unit = spaces ? String(repeating: " ", count: width) : "\t"
        let source = string as NSString
        let selection = selectedRange()
        if !outdent && selection.length == 0 {
            breakUndoCoalescing(); insertText(unit, replacementRange: selection); breakUndoCoalescing(); return
        }
        var selectedLines = selection
        if selectedLines.length > 0 && source.substring(with: NSRange(location: NSMaxRange(selectedLines) - 1, length: 1)) == "\n" { selectedLines.length -= 1 }
        let range = source.lineRange(for: selectedLines)
        var lines = source.substring(with: range).components(separatedBy: "\n")
        for index in lines.indices {
            if index == lines.count - 1 && lines[index].isEmpty { continue }
            if outdent {
                if lines[index].hasPrefix("\t") { lines[index].removeFirst() }
                else { var count = 0; while count < width && lines[index].hasPrefix(" ") { lines[index].removeFirst(); count += 1 } }
            } else { lines[index] = unit + lines[index] }
        }
        let replacement = lines.joined(separator: "\n")
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        breakUndoCoalescing()
        insertText(replacement, replacementRange: range)
        setSelectedRange(NSRange(location: range.location, length: (replacement as NSString).length))
        breakUndoCoalescing()
    }
    @objc func increaseEditorSize(_ sender: Any?) { changeEditorSize(1) }
    @objc func decreaseEditorSize(_ sender: Any?) { changeEditorSize(-1) }
    @objc func resetEditorSize(_ sender: Any?) { UserDefaults.standard.set(13.0, forKey: "editorSize") }
    private func changeEditorSize(_ delta: Double) {
        let current = UserDefaults.standard.object(forKey: "editorSize") as? Double ?? 13
        UserDefaults.standard.set(max(10, min(28, current + delta)), forKey: "editorSize")
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if abs(event.scrollingDeltaY) > 0.1 { changeEditorSize(event.scrollingDeltaY > 0 ? 1 : -1) }
        } else { super.scrollWheel(with: event) }
    }
    // A window undo manager would mix operations from different scripts.
    private let scriptUndoManager = UndoManager()
    override var undoManager: UndoManager? { scriptUndoManager }
    @objc func undo(_ sender: Any?) {
        guard scriptUndoManager.canUndo else { return }
        breakUndoCoalescing()
        let before = string
        scriptUndoManager.undo()
        if string != before { didChangeText() }
    }
    @objc func redo(_ sender: Any?) {
        guard scriptUndoManager.canRedo else { return }
        breakUndoCoalescing()
        let before = string
        scriptUndoManager.redo()
        if string != before { didChangeText() }
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return scriptUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return scriptUndoManager.canRedo }
        if item.action == #selector(copy(_:)) { return isSelectable && !string.isEmpty }
        if item.action == #selector(cut(_:)) { return isEditable && !string.isEmpty }
        return super.validateUserInterfaceItem(item)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { hideCompletions(); return }
        // A retained editor can reattach after the representable's update callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            if let container = self.textContainer { self.layoutManager?.ensureLayout(for: container) }
            self.scrollRangeToVisible(self.selectedRange())
        }
    }
    override func setFrameSize(_ newSize: NSSize) {
        // Rewrapping changes the selected line's vertical position. Keep an
        // already visible caret/selection in view, without undoing manual scrolling.
        var revealSelection = false
        if newSize.width != frame.width, frame.width > 0,
           window?.firstResponder === self, !string.isEmpty, let layoutManager, let textContainer {
            let selection = selectedRange()
            let length = (string as NSString).length
            var rect: NSRect
            if selection.location == length, layoutManager.extraLineFragmentRect.height > 0 {
                rect = layoutManager.extraLineFragmentRect
            } else {
                let range = NSRange(location: min(selection.location, length - 1), length: max(1, selection.length))
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            }
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            revealSelection = visibleRect.intersects(rect)
        }
        super.setFrameSize(newSize)
        if revealSelection {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollRangeToVisible(self.selectedRange())
            }
        }
    }
    var ligaturesEnabled = false
    override func copy(_ sender: Any?) {
        let original = selectedRange()
        if original.length == 0 { setSelectedRange((string as NSString).lineRange(for: original)) }
        super.copy(sender); setSelectedRange(original)
    }
    override func cut(_ sender: Any?) {
        if selectedRange().length == 0 { setSelectedRange((string as NSString).lineRange(for: selectedRange())) }
        super.cut(sender)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command || modifiers == [.command, .shift] {
            switch event.charactersIgnoringModifiers {
            case "=", "+": increaseEditorSize(nil); return true
            case "-": decreaseEditorSize(nil); return true
            case "0": resetEditorSize(nil); return true
            default: break
            }
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.charactersIgnoringModifiers == "/" {
            toggleComment(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    @objc func toggleComment() {
        let source = string as NSString
        var selection = selectedRange()
        if selection.length > 0 && source.substring(with: NSRange(location: NSMaxRange(selection)-1, length: 1)) == "\n" { selection.length -= 1 }
        let range = source.lineRange(for: selection)
        let lines = source.substring(with: range).components(separatedBy: "\n")
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let uncomment = !meaningful.isEmpty && meaningful.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }
        let replacement = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if uncomment, let marker = line.range(of: "--") {
                var value = line; value.removeSubrange(marker)
                let offset = line.distance(from: line.startIndex, to: marker.lowerBound)
                let index = value.index(value.startIndex, offsetBy: offset)
                if index < value.endIndex && value[index] == " " { value.remove(at: index) }
                return value
            }
            return "-- " + line
        }.joined(separator: "\n")
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement); didChangeText()
            setSelectedRange(NSRange(location: range.location, length: (replacement as NSString).length))
            undoManager?.setActionName(String(localized: "注释"))
        }
    }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager, let textContainer else { return }
        let position = min(selectedRange().location, max(0, (string as NSString).length - 1))
        var lineRect = NSRect(x: 0, y: textContainerOrigin.y, width: bounds.width, height: (font?.pointSize ?? 13) * 1.4)
        if !string.isEmpty {
            let glyph = layoutManager.glyphIndexForCharacter(at: position)
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            lineRect.origin.y += textContainerOrigin.y; lineRect.origin.x = 0; lineRect.size.width = bounds.width
        }
        _ = textContainer
        NSColor.labelColor.withAlphaComponent(0.035).setFill(); lineRect.fill()
    }
}

final class QueryLineRuler: NSRulerView {
    weak var textView: NSTextView?
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView; ruleThickness = 44
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    func updateMetrics(font: NSFont, text: String) {
        numberFont = .monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let digits = max(2, String(text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }).count)
        let width = (String(repeating: "8", count: digits) as NSString).size(withAttributes: [.font: numberFont]).width
        let desired = ceil(width + font.pointSize * 1.4)
        if ruleThickness != desired { ruleThickness = desired }
        needsDisplay = true
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let view = textView, let layout = view.layoutManager else { return }
        let source = view.string as NSString
        var offset = 0, line = 1
        while offset < source.length {
            let glyph = layout.glyphIndexForCharacter(at: offset)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = convert(NSPoint(x: 0, y: fragment.minY + view.textContainerOrigin.y), from: view)
            if point.y > bounds.maxY { break }
            if point.y + fragment.height >= bounds.minY {
                let label = String(line) as NSString
                let labelWidth = label.size(withAttributes: [.font: numberFont]).width
                label.draw(at: NSPoint(x: ruleThickness - labelWidth - numberFont.pointSize * 0.6, y: point.y), withAttributes: [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor])
            }
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0))); line += 1
        }
    }
}

private struct SQLCompletionList: View {
    let candidates: [String]
    let selected: Int
    let accept: (Int) -> Void
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                Button { accept(index) } label: {
                    Text(verbatim: candidate).font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(index == selected ? Color.accentColor.opacity(0.2) : Color.clear)
                }.buttonStyle(.plain)
            }
        }.padding(.vertical, 4).accessibilityLabel("SQL 补全候选")
    }
}
