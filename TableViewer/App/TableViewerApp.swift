import SwiftUI

@main
struct TableViewerEntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--mongo-shell-worker") { MongoShellWorker.run() }
        else { TableViewerApp.main() }
    }
}

struct TableViewerApp: App {
    @NSApplicationDelegateAdaptor(TableViewerAppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @StateObject private var updater = AppUpdater()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        Window("TableViewer", id: "workspace") {
            WorkspaceView(store: store)
                .frame(minWidth: 1000, minHeight: 650)
                .tint(.accentColor)
                .onChange(of: appearance, initial: true) { _, value in
                    // 统一窗口、SwiftUI 和 AppKit 控件；nil 重新继承系统外观。
                    NSApp.appearance = switch value {
                    case "dark": NSAppearance(named: .darkAqua)
                    case "light": NSAppearance(named: .aqua)
                    default: nil
                    }
                }
                .sheet(isPresented: $store.showSettings) {
                    SettingsView(updater: updater, store: store)
                        .environment(\.controlActiveState, .active)
                        .interactiveDismissDisabled()
                }
                .task { appDelegate.store = store; await store.start(); updater.start() }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.openSettings() }.keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…", action: updater.checkForUpdates).disabled(!updater.canCheck)
            }
            CommandGroup(replacing: .newItem) {
                Button("新建连接…") { store.editingProfile = nil; store.showConnectionSheet = true }
                    .keyboardShortcut("n").disabled(store.showSettings)
            }
            CommandMenu("编辑器") {
                Button("放大字号") { NSApp.sendAction(#selector(QueryTextView.increaseEditorSize(_:)), to: nil, from: nil) }.keyboardShortcut("=")
                Button("缩小字号") { NSApp.sendAction(#selector(QueryTextView.decreaseEditorSize(_:)), to: nil, from: nil) }.keyboardShortcut("-")
                Button("恢复字号") { NSApp.sendAction(#selector(QueryTextView.resetEditorSize(_:)), to: nil, from: nil) }.keyboardShortcut("0")
                Divider()
                Button("编辑器设置…") { store.openSettings(section: "editor") }
                Button("关闭脚本") {
                    if let id = store.selectedScriptID { store.closeScript(id) }
                }.keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(store.showSettings || store.tab != .query || store.selectedScriptID == nil || store.runningScriptID == store.selectedScriptID)
            }
            CommandMenu("数据库") {
                Button("刷新数据") { Task { await store.refresh(reloadObjects: true) } }
                    .keyboardShortcut("r").disabled(store.showSettings || store.active == nil || store.busy || store.hasChanges)
                Button("运行查询") { Task { await store.runQuery() } }
                    .keyboardShortcut(.return).disabled(store.showSettings || store.tab != .query || store.active == nil || store.busy)
                Divider()
                Button("保存记录") { Task { await store.saveRow() } }
                    .keyboardShortcut("s").disabled(store.showSettings || !store.hasChanges || store.busy)
                Button("导出当前结果…") { store.exportCSV() }.disabled(store.showSettings || store.displayedResult.columns.isEmpty)
            }
        }
        Window("全部本地脚本", id: "script-history") {
            ScriptLibraryView(store: store).tint(.accentColor)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

    }
}

@MainActor final class TableViewerAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: WorkspaceStore?
    func applicationWillFinishLaunching(_ notification: Notification) {
        ConnectionVault.startSession()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store?.agentLibrary.save()
        guard let warning = store?.terminationWarning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "退出 TableViewer？")
        alert.informativeText = warning
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "取消退出"))
        alert.addButton(withTitle: String(localized: "退出"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        if let store, store.shellRunning {
            // An evaluating worker cannot notice stdin EOF until its script ends.
            // Stop it before the parent exits, including infinite JavaScript loops.
            Task {
                await store.shell.stop()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }
}

struct SettingsView: View {
    @ObservedObject var updater: AppUpdater
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var sizeDraft = ""
    @State private var pageDraft = ""
    @AppStorage("appearance") private var appearance = "system"
    @State private var language = (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "local.yuna.TableViewer")?["AppleLanguages"] as? [String])?.first ?? "system"
    @AppStorage("editorFont") private var editorFont = "SF Mono"
    @AppStorage("editorSize") private var editorSize = 13.0
    @AppStorage("editorLigatures") private var ligatures = false
    @AppStorage("editorTabSpaces") private var tabSpaces = true
    @AppStorage("editorIndentWidth") private var indentWidth = 4
    @AppStorage("editorCompletion") private var completion = true
    @AppStorage("editorLineNumbers") private var lineNumbers = true
    @AppStorage("openInspectorOnSelection") private var openInspector = false
    @AppStorage("showAutomaticEstimates") private var showAutomaticEstimates = false
    private static let editorFonts = Array(Set(["SF Mono"] + NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") && NSFont(name: $0, size: 13) != nil }))
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.title2)
                Spacer()
                Button("完成") { commitSize(); dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Picker("设置分类", selection: $store.settingsSection) {
                Text("通用").tag("general")
                Text("编辑器").tag("editor")
                Text("数据").tag("data")
                Text("执行").tag("execution")
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20)
            Form {
            if store.settingsSection == "general" {
            Picker("语言 / Language", selection: $language) {
                Text("跟随系统").tag("system")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "简体中文").tag("zh-Hans")
            }
            .onChange(of: language) { _, value in
                if value == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                else { UserDefaults.standard.set([value], forKey: "AppleLanguages") }
            }
            Text("语言设置将在下次启动时生效。请先保存修改，再退出并重新打开应用。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
            LabeledContent("凭据存储", value: String(localized: "macOS 钥匙串"))
            LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            UpdateSettingsSection(updater: updater)
            }
            if store.settingsSection == "editor" {
            Section("编辑器") {
                Picker("编辑器字体", selection: $editorFont) {
                    ForEach(Self.editorFonts, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                    // Preserve a previously entered font name until the user chooses another.
                    if !Self.editorFonts.contains(editorFont) {
                        Text(verbatim: editorFont).tag(editorFont)
                    }
                }.pickerStyle(.menu)
                HStack {
                    Text("字号")
                    Spacer()
                    TextField("10–28", text: $sizeDraft).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 64).onSubmit { commitSize() }
                    Stepper("微调字号", value: $editorSize, in: 10...28).labelsHidden()
                }
                Text("输入 10–28，按回车应用；无效输入恢复原值。").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: "SELECT 名称, price FROM orders;\nWHERE id = 12345 AND 名称 = '示例';")
                    .font(Font(NSFont(name: editorFont, size: editorSize) ?? .monospacedSystemFont(ofSize: editorSize, weight: .regular))).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                Toggle("字体连字", isOn: $ligatures)
                Toggle("显示行号", isOn: $lineNumbers)
                Toggle("Tab 转为空格", isOn: $tabSpaces)
                Stepper("缩进空格数：\(indentWidth)", value: $indentWidth, in: 1...16)
                Toggle("SQL 关键字与表名补全", isOn: $completion)
                Text("⌘+ / ⌘− 调整字号，⌘0 恢复 13；⌘+滚轮缩放。Tab 接受补全，Escape 取消；⇧Tab 减少缩进。").font(.caption).foregroundStyle(.secondary)
            }
            }
            if store.settingsSection == "data" {
                Toggle("选择记录时打开属性栏", isOn: $openInspector)
                HStack {
                    Text("每页记录")
                    TextField("1–10000", text: $pageDraft).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 100)
                    Button("应用") {
                        guard let size = Int(pageDraft), (1...10000).contains(size) else { pageDraft = String(store.pageSize); return }
                        Task { await store.updatePageSize(size); pageDraft = String(store.pageSize) }
                    }.disabled(store.busy || store.hasChanges)
                }
                Text("修改后回到第一页并刷新。请先保存或撤销记录修改。").font(.caption).foregroundStyle(.secondary)
            }
            if store.settingsSection == "execution" {
                Toggle("查询前预估", isOn: Binding(get: { store.estimatesEnabled }, set: { store.setEstimatesEnabled($0) }))
                Text("默认关闭。开启后用于查询、Agent 与数据浏览；关闭不会取消数据库审批或只读保护。").font(.caption).foregroundStyle(.secondary)
                Toggle("默认显示自动估算栏", isOn: $showAutomaticEstimates)
            }
            }.formStyle(.grouped)
        }.frame(width: 620, height: 620)
        .onAppear { sizeDraft = String(Int(editorSize)); pageDraft = String(store.pageSize) }
        .onChange(of: editorSize) { _, value in sizeDraft = String(Int(value)) }
    }
    private func commitSize() {
        if let value = Double(sizeDraft), value.isFinite, (10...28).contains(value) { editorSize = value }
        sizeDraft = String(Int(editorSize))
    }
}
