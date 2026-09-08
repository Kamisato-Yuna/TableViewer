import SwiftUI
import Observation

struct QueryResult {}
struct StatementResult { var failure: String?; var result: QueryResult? = QueryResult() }
@Observable final class WorkspaceStore {
    var statementResults: [StatementResult] = []
    var selectedResultIndex = 0
    var queryResult = QueryResult()
}

@main struct QueryResultPickerLifecycleTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let store = WorkspaceStore()
        let host = NSHostingView(rootView: ResultPickerHost(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        for _ in 0..<30 {
            store.statementResults = [StatementResult(), StatementResult(failure: "synthetic failure")]
            settle()
            store.selectedResultIndex = 1
            settle()
            // Opening another script clears results while old Picker children
            // may still participate in the next SwiftUI graph update.
            store.statementResults = []
            store.selectedResultIndex = 0
            settle()
        }
        window.contentView = nil
        print("PASS: multi-result Picker survives 30 result selection and script-clear cycles")
    }
}
