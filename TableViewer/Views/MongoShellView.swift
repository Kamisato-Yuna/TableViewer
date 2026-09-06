import SwiftUI
import AppKit

struct MongoShellView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(store.shellRunning ? .orange : .green).frame(width: 7, height: 7)
                Text("Mongo Shell").font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(store.shellDatabase).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("帮助", systemImage: "questionmark.circle") { store.shellInput = "help"; Task { await store.runShell() } }.disabled(store.busy)
                Button("清屏", systemImage: "clear") { store.shellEntries = [] }.disabled(store.shellRunning)
                Button("重置会话", systemImage: "arrow.counterclockwise") { Task { await store.resetShell() } }.disabled(store.shellRunning)
            }.buttonStyle(.borderless).controlSize(.small).padding(.horizontal, 24).frame(height: 48)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if store.shellEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: "terminal").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(.tint)
                                Text("让数据回应你的每一行。 ").font(.system(size: 21, weight: .medium, design: .rounded))
                                Text("输入 JavaScript 表达式、db 命令或 rs.status()。变量和游标会在本会话内保留。").font(.system(size: 12)).foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    sample("show collections")
                                    sample("db.hello()")
                                    sample("rs.status()")
                                }
                            }.padding(.vertical, 32)
                        }
                        ForEach(store.shellEntries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(entry.database) ›").foregroundStyle(.tint)
                                    Text(entry.command).foregroundStyle(.primary).textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }.font(.system(size: 12, weight: .medium, design: .monospaced))
                                if !entry.output.isEmpty { Text(entry.output).font(.system(size: 11, design: .monospaced)).foregroundStyle(entry.failed ? Color.orange : Color.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            }.id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("terminal-bottom")
                    }.padding(24)
                }.onChange(of: store.shellEntries.count) { withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { proxy.scrollTo("terminal-bottom", anchor: .bottom) } }
            }
            Divider()
            HStack(alignment: .top, spacing: 10) {
                Text("›").font(.system(size: 20, weight: .medium, design: .monospaced)).foregroundStyle(.tint).padding(.top, 7)
                ShellInput(text: $store.shellInput, disabled: store.shellRunning, submit: { Task { await store.runShell() } }, history: { store.navigateShellHistory($0) })
                    .frame(height: 85)
                if store.shellRunning {
                    Button("停止", systemImage: "stop.fill") { Task { await store.shell.stop() } }.buttonStyle(.glass).padding(.top, 6)
                } else {
                    Button("运行", systemImage: "return") { Task { await store.runShell() } }.buttonStyle(.glassProminent).padding(.top, 6).disabled(store.busy || store.shellInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(.horizontal, 24).padding(.top, 12)
            HStack { Text("↵ 运行 · ⇧↵ 换行 · ↑↓ 历史"); Spacer(); Text("JavaScriptCore · 写入直接执行") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.bottom, 14)
        }
    }
    private func sample(_ command: String) -> some View { Button(command) { store.shellInput = command }.font(.system(size: 11, design: .monospaced)).buttonStyle(.glass).controlSize(.small) }
}

struct ShellInput: NSViewRepresentable {
    @Binding var text: String
    var disabled: Bool
    var submit: () -> Void
    var history: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let view = InputTextView(), scroll = NSScrollView()
        view.delegate = context.coordinator; view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.drawsBackground = false; view.textColor = .labelColor
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isContinuousSpellCheckingEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true; view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 2, height: 8)
        view.setAccessibilityLabel(String(localized: "Mongo Shell 输入"))
        scroll.documentView = view; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? InputTextView else { return }
        view.submit = submit; view.history = history; view.isEditable = !disabled
        if view.string != text { view.string = text; view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ShellInput
        init(_ parent: ShellInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { parent.text = view.string } }
    }
    final class InputTextView: NSTextView {
        var submit: (() -> Void)?
        var history: ((Int) -> Void)?
        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) { submit?(); return }
            if !string.contains("\n") && event.keyCode == 126 { history?(-1); return }
            if !string.contains("\n") && event.keyCode == 125 { history?(1); return }
            super.keyDown(with: event)
        }
    }
}
