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
                .task { appDelegate.store = store; await store.start(); updater.start() }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…", action: updater.checkForUpdates).disabled(!updater.canCheck)
            }
            CommandGroup(replacing: .newItem) {
                Button("新建连接…") { store.editingProfile = nil; store.showConnectionSheet = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("数据库") {
                Button("刷新数据") { Task { await store.refresh(reloadObjects: true) } }
                    .keyboardShortcut("r").disabled(store.active == nil || store.busy || store.hasChanges)
                Button("运行查询") { Task { await store.runQuery() } }
                    .keyboardShortcut(.return).disabled(store.tab != .query || store.active == nil || store.busy)
                Divider()
                Button("保存记录") { Task { await store.saveRow() } }
                    .keyboardShortcut("s").disabled(!store.hasChanges || store.busy)
                Button("导出当前结果…") { store.exportCSV() }.disabled(store.displayedResult.columns.isEmpty)
            }
        }
        Settings { SettingsView(updater: updater) }
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
    @AppStorage("appearance") private var appearance = "system"
    @State private var language = (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "local.yuna.TableViewer")?["AppleLanguages"] as? [String])?.first ?? "system"
    var body: some View {
        Form {
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
            LabeledContent("每页记录", value: "200")
            LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            UpdateSettingsSection(updater: updater)
        }.formStyle(.grouped).frame(width: 560, height: 610)
    }
}
