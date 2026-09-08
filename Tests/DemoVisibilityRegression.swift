import Foundation

@main struct DemoVisibilityRegression {
    @MainActor static func main() async throws {
        guard let identifier = Bundle.main.bundleIdentifier, identifier.hasPrefix("local.yuna.TableViewer.DemoRegression.") else { fatalError("Requires isolated test bundle") }
        guard LocalWorkspace.directory.lastPathComponent == identifier else { fatalError("Refuse production storage") }
        if CommandLine.arguments.contains("--verify-isolation") {
            print("ISOLATED: " + LocalWorkspace.directory.path)
            return
        }
        guard !FileManager.default.fileExists(atPath: LocalWorkspace.directory.appendingPathComponent("connections.json").path) else { fatalError("Use a fresh disposable test profile") }
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        try LocalWorkspace.saveProfiles([])
        let store = WorkspaceStore()
        await store.start()
        let demo = store.profiles.first { $0.isDemo }!
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            print("PASS: " + message)
        }
        check(store.visibleProfiles.count == 1 && store.active?.isDemo == true, "initial demo")
        let user = ConnectionProfile(name: "Synthetic SQLite", kind: .sqlite, path: demo.path)
        try store.saveConnection(user, secret: "")
        await store.connect(user)
        store.suggestDemoVisibility(afterAdding: user)
        check(store.showDemoVisibilitySuggestion, "successful local SQLite addition suggests hiding")
        store.chooseDemoVisibility(hidden: false)
        store.suggestDemoVisibility(afterAdding: user)
        check(!store.showDemoVisibilitySuggestion && store.visibleProfiles.count == 2, "keep choice suppresses repeated prompts")
        store.chooseDemoVisibility(hidden: true)
        check(store.visibleProfiles.count == 1 && store.profiles.contains { $0.isDemo }, "hide retains demo profile and file")
        let restarted = WorkspaceStore()
        await restarted.start()
        check(restarted.demoHidden && restarted.active?.id == user.id, "restart preserves hidden state and visible selection")
        let second = ConnectionProfile(name: "Second synthetic", kind: .sqlite, path: demo.path)
        try restarted.saveConnection(second, secret: "")
        await restarted.removeConnection(second)
        check(restarted.demoHidden && restarted.visibleProfiles.count == 1, "partial removal keeps demo hidden")
        await restarted.removeConnection(user)
        check(!restarted.demoHidden && restarted.active?.isDemo == true && restarted.tab == .overview && restarted.selectedObject == nil, "last removal restores demo and valid workspace")
        defaults.set(true, forKey: "demoSidebarHidden")
        let onlyDemo = WorkspaceStore()
        await onlyDemo.start()
        check(!onlyDemo.demoHidden && onlyDemo.active?.isDemo == true, "restart repairs stale hidden preference with demo only")
        onlyDemo.demoVisibilityChoiceMade = false
        let invalid = ConnectionProfile(name: "Invalid synthetic", kind: .sqlite, path: "/nonexistent/demo-regression.sqlite")
        try onlyDemo.saveConnection(invalid, secret: "")
        await onlyDemo.connect(invalid)
        onlyDemo.suggestDemoVisibility(afterAdding: invalid)
        check(!onlyDemo.showDemoVisibilitySuggestion, "failed connection does not suggest hiding")
        print("All demo visibility regressions passed")
    }
}
