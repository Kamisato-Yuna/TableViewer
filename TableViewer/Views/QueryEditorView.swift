import SwiftUI

struct QueryEditorView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Label(store.active?.kind == .mongodb ? String(localized: "MongoDB 命令") : String(localized: "SQL 查询"), systemImage: "chevron.left.forwardslash.chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        if store.queryHistory.isEmpty { Text("本次连接还没有查询记录") }
                        ForEach(Array(store.queryHistory.enumerated()), id: \.offset) { _, query in
                            Button(String(query.prefix(90))) { store.query = query }
                        }
                    } label: { Image(systemName: "clock.arrow.circlepath") }.menuStyle(.borderlessButton).frame(width: 24).help("本次连接的查询历史")
                    Text("⌘ ↵").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    Button { Task { await store.runQuery() } } label: { Label(store.busy ? String(localized: "运行中…") : String(localized: "运行"), systemImage: "play.fill") }
                        .buttonStyle(.glassProminent).controlSize(.small).disabled(store.busy || store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal, 24).frame(height: 48)
                CodeEditor(text: $store.query, isJSON: store.active?.kind == .mongodb).padding(.horizontal, 16).padding(.bottom, 14)
                HStack { Text(store.active?.kind == .mongodb ? String(localized: "输入 JSON 数据库命令，例如 find、aggregate 或 update。") : String(localized: "每次执行一条 SQL · 修改语句会直接写入数据库")); Spacer() }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 12)
            }.frame(height: 260)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("查询结果").font(.system(size: 12, weight: .medium))
                    if store.queryHasRun { Text("\(store.queryResult.rows.count) 行 · \(String(format: "%.0f", store.queryResult.elapsed * 1000)) ms").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                    Button { store.exportCSV() } label: { Label("导出", systemImage: "square.and.arrow.up") }.buttonStyle(.borderless).controlSize(.small).disabled(store.queryResult.columns.isEmpty)
                }.padding(.horizontal, 24).frame(height: 48)
                if store.queryHasRun && !store.queryResult.columns.isEmpty {
                    DataGrid(columns: store.queryResult.columns, rows: store.queryResult.rows, selectedID: nil)
                } else {
                    ContentUnavailableView(store.queryHasRun ? String(localized: "执行成功") : String(localized: "从一个好问题开始"), systemImage: store.queryHasRun ? "checkmark.circle" : "text.magnifyingglass", description: Text(store.queryHasRun ? String(localized: "\(store.queryResult.affectedRows) 行受影响。") : String(localized: "写下查询，按 ⌘↵，让数据给出答案。")))
                }
                if store.queryResult.hasMore { Text("当前仅显示前 1,000 行或首批文档；请通过 LIMIT / skip 缩小范围。").font(.system(size: 10)).foregroundStyle(.secondary).padding(10) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isJSON = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator; view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.backgroundColor = .textBackgroundColor
        view.setAccessibilityLabel(String(localized: "查询代码编辑器"))
        scroll.drawsBackground = false
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text; context.coordinator.highlight(view) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string; highlight(view)
        }
        func highlight(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes([.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)], range: range)
            let patterns: [(String, NSColor)] = [
                ("\\b(?i:SELECT|FROM|WHERE|ORDER|BY|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|JOIN|LEFT|ON|AND|OR|NOT|NULL|AS|GROUP|HAVING|DESC|ASC|BEGIN|COMMIT|ROLLBACK|TRUE|FALSE)\\b", .systemPurple),
                ("'(?:[^']|'')*'|\"(?:[^\"\\\\]|\\\\.)*\"", .systemTeal),
                ("\\b[0-9]+\\b", .systemOrange),
                ("--[^\\n]*", .secondaryLabelColor)
            ]
            for (pattern, color) in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in expression.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
            }
            storage.endEditing()
        }
    }
}
