import AppKit

@main struct EditorUndoIsolationTests {
    @MainActor static func main() {
        // Native AppKit objects only; no windows, clipboard, events or user settings.
        _ = NSApplication.shared
        let first = QueryTextView(frame: .zero)
        let second = QueryTextView(frame: .zero)
        for view in [first, second] { view.isRichText = false; view.allowsUndo = true; view.undoManager?.groupsByEvent = false }
        func edit(_ view: QueryTextView, _ text: String) {
            view.undoManager?.beginUndoGrouping()
            view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            view.breakUndoCoalescing()
            view.undoManager?.endUndoGrouping()
        }
        let firstID = UUID(), secondID = UUID()
        var retained: [UUID: NSScrollView] = [:]
        let scrollA = NSScrollView(); scrollA.documentView = first; retained[firstID] = scrollA
        let scrollB = NSScrollView(); scrollB.documentView = second; retained[secondID] = scrollB
        edit(first, "SELECT 1;")
        edit(second, "SELECT 2;")
        precondition(first.undoManager !== second.undoManager)
        let restored = retained[firstID]!.documentView as! QueryTextView
        precondition(restored === first && restored.undoManager!.canUndo)
        restored.undoManager!.undo()
        precondition(restored.string == "" && second.string == "SELECT 2;")
        precondition(restored.undoManager!.canRedo)
        // Switching away and restoring the retained editor also preserves redo.
        let restoredAgain = retained[firstID]!.documentView as! QueryTextView
        restoredAgain.undoManager!.redo()
        precondition(restoredAgain.string == "SELECT 1;")
        edit(restoredAgain, "\nSELECT 3;")
        restoredAgain.undoManager!.undo()
        precondition(restoredAgain.string == "SELECT 1;")
        retained.removeValue(forKey: secondID)
        precondition(retained[secondID] == nil)
        print("PASS native NSTextView independent undo/redo across retained editor switches (no GUI navigation exercised)")
    }
}
