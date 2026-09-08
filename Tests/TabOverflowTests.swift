import SwiftUI
import Observation
struct TestTab: Identifiable { let id = UUID(); let name: String }
@MainActor @Observable final class TabStore {
    var openScripts = (1...30).map { TestTab(name: "合成超长脚本标签-\($0)") }
    var selectedScriptID: UUID?
    var runningScriptID: UUID?
    var edges = TabOverflowEdges()
    func openScript(_ id: UUID) { selectedScriptID = id }
    func closeScript(_ id: UUID) { openScripts.removeAll { $0.id == id }; selectedScriptID = openScripts.last?.id }
    func nameScript(_ id: UUID) {}
}
@main struct TabOverflowTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        func edges(offset: CGFloat, content: CGFloat, viewport: CGFloat) -> TabOverflowEdges {
            TabOverflowEdges(geometry: ScrollGeometry(contentOffset: CGPoint(x: offset, y: 0), contentSize: CGSize(width: content, height: 44), contentInsets: .init(), containerSize: CGSize(width: viewport, height: 44)))
        }
        precondition(!edges(offset: 0, content: 300, viewport: 500).leading && !edges(offset: 0, content: 300, viewport: 500).trailing)
        precondition(!edges(offset: -10, content: 1000, viewport: 500).leading)
        precondition(edges(offset: 0, content: 1000, viewport: 500).trailing)
        precondition(edges(offset: 200, content: 1000, viewport: 500).leading && edges(offset: 200, content: 1000, viewport: 500).trailing)
        precondition(!edges(offset: 510, content: 1000, viewport: 500).trailing)
        print("PASS edge visibility: short list, start, middle, end and elastic overscroll")
        let store = TabStore()
        store.selectedScriptID = store.openScripts.first!.id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 44), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: TabHost(store: store))
        window.contentView = host
        func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        settle()
        guard let scroll = findScroll(host), let document = scroll.documentView else { fatalError("Native tab scroll view did not mount") }
        precondition(scroll.bounds.width <= 600 && document.bounds.width > 4000)
        func clippedHost(_ view: NSView) -> NSView? {
            if view.layer?.cornerRadius == 22 && view.layer?.masksToBounds == true { return view }
            return view.subviews.lazy.compactMap { clippedHost($0) }.first
        }
        guard let viewport = clippedHost(host) else { fatalError("Clipped native viewport missing") }
        precondition(viewport.hitTest(NSPoint(x: viewport.frame.maxX + 8, y: viewport.frame.midY)) == nil,
                     "Offscreen tab intercepted a point outside the viewport")
        precondition(viewport.hitTest(NSPoint(x: viewport.frame.minX - 8, y: viewport.frame.midY)) == nil)
        print("PASS native hit testing rejects both offscreen sides")
        store.openScript(store.openScripts.last!.id); settle()
        precondition(scroll.documentVisibleRect.maxX >= document.bounds.maxX - 2, "Last selected tab did not scroll into view")
        print("END EDGES", store.edges)
        precondition(store.edges.leading && !store.edges.trailing, "Live trailing edge state did not track native scrolling")
        window.setContentSize(NSSize(width: 320, height: 44)); settle()
        precondition(scroll.bounds.width <= 320, "Native scroll viewport expanded into fixed controls")
        precondition(scroll.documentVisibleRect.maxX >= document.bounds.maxX - 2, "Resize hid the selected last tab")
        store.openScript(store.openScripts.first!.id); settle()
        precondition(scroll.documentVisibleRect.minX <= 1, "First selected tab did not scroll to start")
        store.openScript(store.openScripts.last!.id); settle()
        store.closeScript(store.openScripts.last!.id); settle()
        precondition(scroll.documentVisibleRect.maxX <= document.bounds.maxX + 2, "Closing edge tab left an invalid offset")
        store.selectedScriptID = store.openScripts.first!.id
        store.openScripts.removeLast();settle()
        precondition(scroll.documentVisibleRect.minX <= 1, "Closing an edge tab hid the restored first selection")
        store.openScripts = Array(store.openScripts.prefix(1));store.selectedScriptID = store.openScripts.first!.id;settle()
        precondition(document.bounds.width <= 322 && scroll.documentVisibleRect.minX <= 1, "Short list failed to restore after closing tabs")
        print("PASS native hosting: 30 tabs, last/first selection, narrow resize, edge close and short-list restoration")
        window.contentView = nil
    }
}
