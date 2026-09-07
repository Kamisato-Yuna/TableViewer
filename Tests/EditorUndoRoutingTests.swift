import SwiftUI

@main struct EditorUndoRoutingTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var aText = "SELECT 40;", bText = ""
        func editor(_ binding: Binding<String>) -> CodeEditor { CodeEditor(text: binding) }
        let editorA = editor(Binding(get: { aText }, set: { aText = $0 }))
        let editorB = editor(Binding(get: { bText }, set: { bText = $0 }))
        let coordinatorA = editorA.makeCoordinator(), coordinatorB = editorB.makeCoordinator()
        func view(_ text: String, _ coordinator: CodeEditor.Coordinator) -> QueryTextView {
            let view = QueryTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            view.isRichText = false; view.allowsUndo = true
            view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            view.string = text; view.delegate = coordinator
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            coordinator.highlight(view)
            view.undoManager!.removeAllActions()
            view.undoManager!.groupsByEvent = false
            return view
        }
        let a = view(aText, coordinatorA), b = view(bText, coordinatorB)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        func paste(_ text: String, into view: QueryTextView) {
            board.declareTypes([.string], owner: nil)
            guard board.setString(text, forType: .string) else {
                fputs("Cannot access the independent AppKit test pasteboard; run with macOS pasteboard-service access.\n", stderr)
                exit(2)
            }
            view.undoManager!.beginUndoGrouping()
            precondition(view.readSelection(from: board, type: .string))
            view.breakUndoCoalescing()
            view.undoManager!.endUndoGrouping()
        }
        paste(" -- undo040", into: a)
        paste("SELECT 99;", into: b)
        precondition(aText == "SELECT 40; -- undo040" && bText == "SELECT 99;")
        // Rebinding a retained editor mirrors remounting it after switching scripts.
        let restoredCoordinator = editorA.makeCoordinator()
        a.delegate = restoredCoordinator
        let undo = NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        precondition(a.responds(to: undo.action!) && a.validateUserInterfaceItem(undo))
        precondition(NSApp.sendAction(undo.action!, to: a, from: undo))
        precondition(a.string == "SELECT 40;" && aText == a.string)
        precondition(b.string == "SELECT 99;" && bText == b.string)
        precondition(a.validateUserInterfaceItem(redo))
        precondition(NSApp.sendAction(redo.action!, to: a, from: redo))
        precondition(a.string == "SELECT 40; -- undo040" && aText == a.string)
        precondition(!a.validateUserInterfaceItem(redo))
        a.setSelectedRange(NSRange(location: 3, length: 0))
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        precondition(a.validateUserInterfaceItem(copy) && a.validateUserInterfaceItem(cut))
        a.isEditable = false
        precondition(a.validateUserInterfaceItem(copy) && !a.validateUserInterfaceItem(cut))
        a.string = ""
        precondition(!a.validateUserInterfaceItem(copy) && !a.validateUserInterfaceItem(cut))
        print("PASS native pasteboard readSelection + production delegate/highlight + NSApplication.sendAction undo/redo and menu validation; general clipboard unchanged")
    }
}
