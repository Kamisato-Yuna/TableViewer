import SwiftUI

struct QueryEditorView: View {
    @Bindable var store: WorkspaceStore
    @AppStorage("queryHorizontal") private var horizontal = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(store.openScripts) { script in
                            Button(script.name) { store.openScript(script.id) }
                                .buttonStyle(.bordered).tint(store.selectedScriptID == script.id ? .accentColor : .secondary)
                                .contextMenu {
                                    Button("重命名…") { store.nameScript(script.id) }
                                    Button("关闭脚本") {
                                        do {
                                            try store.scripts.close(script.id)
                                            store.queryEditorViews.removeValue(forKey: script.id)
                                            if store.selectedScriptID == script.id {
                                                store.selectedScriptID = nil; store.query = ""
                                                if let next = store.openScripts.first { store.openScript(next.id) }
                                            }
                                        } catch { store.report(error) }
                                    }
                                }
                        }
                    }
                }
                Button { store.nameScript() } label: { Image(systemName: "plus") }.help("新建命名脚本")
                Button { store.showScripts = true } label: { Image(systemName: "clock.arrow.circlepath") }.help("全部本地脚本")
                Button { horizontal.toggle() } label: { Image(systemName: horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1") }.help("切换上下或左右分栏")
            }.controlSize(.small).padding(12).disabled(store.busy)
            if store.selectedScriptID == nil {
                ContentUnavailableView("新建命名脚本", systemImage: "doc.badge.plus", description: Text("为脚本命名后开始编辑，输入内容会自动保存到本地 .sql 文件。"))
                Button("新建脚本") { store.nameScript() }.padding()
            } else if horizontal {
                HSplitView { editor.frame(minWidth: 260, idealWidth: 440); results.frame(minWidth: 260) }
            } else {
                VSplitView { editor.frame(minHeight: 150, idealHeight: 260); results.frame(minHeight: 150) }
            }
        }
        .onAppear { if store.selectedScriptID == nil { store.nameScript() } }
        .sheet(isPresented: $store.showScripts) { ScriptLibraryView(store: store) }
        .alert(store.renamingScriptID == nil ? String(localized: "新建脚本") : String(localized: "重命名脚本"), isPresented: $store.showScriptName) {
            TextField("脚本名称", text: $store.scriptName)
            Button("取消", role: .cancel) {}
            Button("保存") { store.saveScriptName() }.disabled(store.scriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $store.showQueryApproval) {
            VStack(alignment: .leading, spacing: 16) {
                Text("执行前规模预估").font(.title2)
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
                HStack { Spacer(); Button("取消", role: .cancel) { store.showQueryApproval = false; store.pendingQuery = nil }; Button("继续执行") { store.showQueryApproval = false; Task { await store.runQuery(approved: true) } }.keyboardShortcut(.defaultAction) }
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
        return VStack(spacing: 0) {
            HStack {
                Text(store.active?.kind == .mongodb ? "MongoDB JSON" : "SQL").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await store.runQuery() } } label: { Label(store.querySelection.length > 0 ? String(localized: "运行选区") : String(localized: "运行"), systemImage: "play.fill") }
                    .buttonStyle(.glassProminent).controlSize(.small).disabled(store.busy || store.query.isEmpty)
            }.padding(12)
            CodeEditor(text: scriptText, isJSON: store.active?.kind == .mongodb,
                       selectionChanged: { [weak store] range in
                           guard let store, store.selectedScriptID == scriptID else { return }
                           store.querySelection = range
                       },
                       retainedView: scriptID.flatMap { store.queryEditorViews[$0] },
                       retainView: { [weak store] view in
                           if let scriptID { store?.queryEditorViews[scriptID] = view }
                       }).id(scriptID)
            HStack {
                Text("⌘↵ 运行 · ⌘/ 注释 · ⌘Z 撤销 · ⇧⌘Z 重做").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }.padding(10)
        }
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("查询结果").font(.headline)
                if store.statementResults.count > 1 {
                    Picker("结果", selection: $store.selectedResultIndex) {
                        ForEach(store.statementResults.indices, id: \.self) { index in
                            Text(String(localized: "语句") + " \(index + 1)" + (store.statementResults[index].failure == nil ? "" : " ⚠︎")).tag(index)
                        }
                    }.labelsHidden().frame(maxWidth: 150)
                    .onChange(of: store.selectedResultIndex) { _, index in
                        if store.statementResults.indices.contains(index) { store.queryResult = store.statementResults[index].result ?? QueryResult() }
                    }
                }
                Spacer()
                ExportMenu(store: store)
                Button { Task { await store.runQuery() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.busy)
            }.controlSize(.small).padding(12)
            if let failure = store.queryFailure {
                VStack(alignment: .leading) {
                    Label("执行失败，后续语句未运行；先前自动提交的写入不会回滚。", systemImage: "exclamationmark.triangle").font(.caption)
                    DisclosureGroup("错误详情") { ScrollView { Text(verbatim: failure).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140) }
                }.padding(12).background(.red.opacity(0.05))
            }
            if store.queryHasRun && !store.queryResult.columns.isEmpty {
                DataGrid(columns: store.queryResult.columns, rows: store.queryResult.rows, selectedID: nil)
            } else {
                ContentUnavailableView(store.queryHasRun ? String(localized: "执行结束") : String(localized: "从一个好问题开始"), systemImage: "text.magnifyingglass", description: Text(store.queryHasRun ? String(localized: "\(store.queryResult.affectedRows) 行受影响。") : String(localized: "写下查询，按 ⌘↵，让数据给出答案。")))
            }
            if store.queryResult.hasMore { Text("当前仅显示前 1,000 行或首批文档；请通过 LIMIT / skip 缩小范围。").font(.caption2).padding(8) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScriptLibraryView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scriptCleanupDays") private var days = 90
    @AppStorage("scriptAutoCleanup") private var automatic = false
    @State private var deleting = Set<UUID>()
    @State private var confirm = false
    @State private var confirmAutomatic = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("全部本地脚本").font(.title2); Spacer(); Button("完成") { dismiss() } }
            Text("脚本内容保存为 .sql，显示名称保存在本地目录索引。关闭选项卡会保留脚本；清理会永久删除文件。").font(.caption).foregroundStyle(.secondary)
            List(store.scripts.scripts.sorted { $0.lastUsed > $1.lastUsed }) { script in
                HStack {
                    VStack(alignment: .leading) { Text(script.name); Text(script.lastUsed.formatted()).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("打开") { store.openScript(script.id); dismiss() }.disabled(script.connectionID != store.active?.id)
                    Button("重命名…") { dismiss(); store.nameScript(script.id) }
                }
            }
            HStack {
                Stepper(String(localized: "未使用天数：") + "\(days)", value: $days, in: 1...3650)
                Button("清理未使用脚本") { deleting = Set(store.scripts.unused(days: days).map(\.id)); confirm = true }
                Button("清理全部", role: .destructive) { deleting = Set(store.scripts.scripts.map(\.id)); confirm = true }
            }.controlSize(.small)
            Toggle("启动时自动清理未使用且已关闭的脚本", isOn: Binding(get: { automatic }, set: { if $0 { confirmAutomatic = true } else { automatic = false } }))
        }.padding(24).frame(width: 680, height: 500)
        .confirmationDialog("永久删除所选脚本？", isPresented: $confirm, titleVisibility: .visible) {
            Button(String(localized: "删除") + " \(deleting.count)", role: .destructive) {
                do {
                    if let selected = store.selectedScriptID, deleting.contains(selected) { store.selectedScriptID = nil; store.query = "" }
                    try store.scripts.delete(deleting)
                    for id in deleting { store.queryEditorViews.removeValue(forKey: id) }
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
        scroll.rulersVisible = lineNumbers
        if view.string != text {
            view.string = text
            view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: 0))
            context.coordinator.highlight(view)
        } else if changed { context.coordinator.highlight(view) }
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
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selectionChanged(view.selectedRange()); view.needsDisplay = true
            view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
        func highlight(_ view: QueryTextView) {
            guard let storage = view.textStorage else { return }
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
                (String(line) as NSString).draw(at: NSPoint(x: 7, y: point.y), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
            }
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0))); line += 1
        }
    }
}
