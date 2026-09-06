import SwiftUI
import Sparkle
import Combine

/// Sparkle owns version comparison, signature validation, download and installation.
/// Its settings are persisted by Sparkle, rather than a second set of app defaults.
@MainActor final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status = String(localized: "尚未检查更新")
    private var controller: SPUStandardUpdaterController!
    private var started = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticDownloads)
        controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheck)
    }
    func start() {
        guard !started else { return }
        do { try controller.updater.start(); started = true }
        catch { status = error.localizedDescription }
    }
    func checkForUpdates() {
        guard canCheck else { return }
        status = String(localized: "正在检查更新…")
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = String(localized: "发现新版本：\(item.displayVersionString)")
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = String(localized: "当前已是最新版本")
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let failure = error as NSError
        if failure.domain == SUSparkleErrorDomain && failure.code == SUError.noUpdateError.rawValue {
            status = String(localized: "当前已是最新版本")
        } else { status = error.localizedDescription }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        status = String(localized: "更新已下载，将在退出应用后安装")
        // Let Sparkle install on normal quit; never force a database session to terminate.
        return false
    }
}

struct UpdateSettingsSection: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Section("应用更新") {
            Toggle("自动检查更新", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
            Toggle("自动下载并在退出后安装", isOn: Binding(get: { updater.automaticDownloads }, set: updater.setAutomaticDownloads))
                .disabled(!updater.automaticChecks)
            Text("从 GitHub 获取正式版本。更新包验证通过后才会安装，重启前仍会提醒保存未完成的工作。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("检查更新…", action: updater.checkForUpdates).disabled(!updater.canCheck)
                Spacer()
                Link("发行说明", destination: URL(string: "https://github.com/Kamisato-Yuna/TableViewer/releases/latest")!)
            }
            Text(updater.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let date = updater.lastCheck {
                LabeledContent("上次检查", value: date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
            }
        }
    }
}
