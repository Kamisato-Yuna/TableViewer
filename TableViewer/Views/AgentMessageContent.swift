import SwiftUI
import AppKit

struct AgentMarkdownView: View {
    let text: String
    var quickReplies: [String] = []
    var repliesEnabled = true
    var reply: ((String) -> Void)?
    @State private var parsed = AgentMarkdownCache()
    var body: some View {
        let blocks = parsed.blocks(for: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                switch blocks[index] {
                case .paragraph(let text): inline(text)
                case .heading(let level, let text): inline(text).font(.system(size: level == 1 ? 22 : level == 2 ? 18 : 15, weight: .semibold)).padding(.top, 6)
                case .list(let marker, let text):
                    if let reply, index >= blocks.count - quickReplies.count, quickReplies.contains(text) {
                        Button { reply(text) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: marker).monospacedDigit().foregroundStyle(.secondary)
                                AgentInlineText(text: text)
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.turn.down.left").font(.caption).foregroundStyle(.tint)
                            }.padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.07), in: .rect(cornerRadius: 8))
                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.22)) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!repliesEnabled).help("点击回复")
                    } else {
                        HStack(alignment: .top, spacing: 8) { Text(verbatim: marker).monospacedDigit(); inline(text) }.padding(.leading, 4)
                    }
                case .table(let headers, let alignments, let rows): AgentMarkdownTable(headers: headers, alignments: alignments, rows: rows)
                case .quote(let text): HStack(spacing: 10) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3); inline(text).foregroundStyle(.secondary) }.fixedSize(horizontal: false, vertical: true)
                case .rule: Divider()
                case .code(let language, let code):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(verbatim: language.isEmpty ? "code" : language).font(.system(size: 10, weight: .medium)); Spacer(); AgentCopyButton(text: code, label: String(localized: "复制代码")) }
                        ScrollView(.horizontal) { Text(verbatim: code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false) }
                    }.padding(12).background(.background.opacity(0.8), in: .rect(cornerRadius: 8))
                }
            }
            if !quickReplies.isEmpty { Text("点击选项回复，也可以在下方自行输入。").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func inline(_ text: String) -> some View {
        AgentInlineText(text: text)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentInlineText: View {
    let text: String
    @State private var parsed = AgentInlineCache()
    var body: some View {
        Text(parsed.value(for: text))
    }
}

// View-local caches: resizing changes layout, not the Markdown source. These plain
// reference objects do not publish mutations during SwiftUI body evaluation.
final class AgentMarkdownCache {
    private var source: String?
    private var result: [AgentMarkdownBlock] = []
    func blocks(for text: String) -> [AgentMarkdownBlock] {
        if source != text { result = AgentMarkdownBlock.parse(text); source = text }
        return result
    }
}

final class AgentInlineCache {
    private var source: String?
    private var result = AttributedString("")
    func value(for text: String) -> AttributedString {
        if source != text {
            result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
            source = text
        }
        return result
    }
}

private struct AgentMarkdownTable: View {
    let headers: [String]
    let alignments: [AgentTableAlignment]
    let rows: [[String]]
    @State private var availableWidth: CGFloat = 600
    private var columnWidth: CGFloat { max(120, min(320, (availableWidth - 2) / CGFloat(max(1, headers.count)))) }
    private func alignment(_ column: Int) -> Alignment {
        switch alignments[column] { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                tableRow(headers, header: true, row: 0)
                ForEach(rows.indices, id: \.self) { row in tableRow(rows[row], header: false, row: row) }
            }.clipShape(.rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)) }
                .padding(1)
        }.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
    private func tableRow(_ values: [String], header: Bool, row: Int) -> some View {
        GridRow {
            ForEach(headers.indices, id: \.self) { column in
                AgentInlineText(text: values[column])
                    .font(.system(size: 13, weight: header ? .semibold : .regular))
                    .textSelection(.enabled)
                    .multilineTextAlignment(alignments[column] == .center ? .center : alignments[column] == .trailing ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(width: columnWidth, alignment: alignment(column))
            }
        }.background(header ? Color.primary.opacity(0.09) : Color.primary.opacity(row.isMultiple(of: 2) ? 0.025 : 0.05))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5) }
    }
}

struct AgentCopyButton: View {
    let text: String
    let label: String
    @State private var copied = false
    var body: some View {
        Button(copied ? String(localized: "已复制") : label, systemImage: copied ? "checkmark" : "doc.on.doc") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copied = true
        }.buttonStyle(.borderless).font(.system(size: 11)).onChange(of: text) { copied = false }
    }
}

// Let NSTextView own marked text and Return. Only Command-Return submits, after composition ends.
struct AgentComposer: NSViewRepresentable {
    @Binding var text: String
    var canSubmit: Bool
    var submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = ComposerTextView()
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 13); editor.drawsBackground = false
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 4, height: 5)
        editor.setAccessibilityLabel(String(localized: "描述你想完成的事情…"))
        editor.delegate = context.coordinator; editor.string = text
        editor.canSubmit = canSubmit; editor.submit = submit
        scroll.documentView = editor; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        editor.canSubmit = canSubmit; editor.submit = submit
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentComposer
        init(_ parent: AgentComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
}
final class ComposerTextView: NSTextView {
    var canSubmit = false
    var submit: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if hasMarkedText() { return true }
            if canSubmit { submit?() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
