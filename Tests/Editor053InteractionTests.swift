import SwiftUI
import Darwin

@main struct Editor053InteractionTests {
    @MainActor static func check(_ ok: Bool, _ label: String) { print("\(ok ? "PASS" : "FAIL"): \(label)"); if !ok { exit(1) } }
    @MainActor static func main() {
        _ = NSApplication.shared
        let view = QueryTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false; view.allowsUndo = true
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "editorCompletion")
        defaults.removeObject(forKey: "editorTabSpaces"); defaults.removeObject(forKey: "editorIndentWidth")
        view.insertTab(nil)
        check(view.string == "    ", "default tab inserts four spaces")
        view.undo(nil); check(view.string == "", "tab is one undo operation")
        view.string = "one\ntwo\n"; view.setSelectedRange(NSRange(location: 0, length: 8))
        view.insertTab(nil); check(view.string == "    one\n    two\n", "multiline indent excludes trailing empty line")
        view.insertBacktab(nil); check(view.string == "one\ntwo\n", "multiline outdent restores text")
        defaults.set(false, forKey: "editorTabSpaces")
        view.string = ""; view.setSelectedRange(NSRange(location: 0, length: 0)); view.insertTab(nil)
        check(view.string == "\t", "disabled conversion inserts literal tab")
        defaults.set(true, forKey: "editorCompletion")
        view.sqlCandidates = ["orders", "order_items", "\"sales\".\"Orders\""]
        for text in ["SELECT 'sel", "-- sel", "/* sel", "SELECT $$sel", "SELECT $tag$sel"] {
            view.string = text; view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            check(view.rangeForUserCompletion.location == NSNotFound, "no completion inside \(text)")
        }
        view.string = "SELECT * FROM ord"; view.setSelectedRange(NSRange(location: 17, length: 0))
        var index = 0
        let candidates = view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: &index) ?? []
        check(candidates.contains("orders") && candidates.contains("order_items"), "local table candidates")
        let before = view.string
        let range = view.rangeForUserCompletion
        view.insertCompletion("orders", forPartialWordRange: range, movement: 0, isFinal: false)
        check(view.string == before, "candidate preview never alters SQL")
        view.insertCompletion("orders", forPartialWordRange: range, movement: NSTextMovement.cancel.rawValue, isFinal: true)
        check(view.string == before, "cancel completion preserves prefix")
        view.insertCompletion("orders", forPartialWordRange: range, movement: NSTextMovement.tab.rawValue, isFinal: true)
        check(view.string == "SELECT * FROM orders", "accept replaces only partial identifier")
        view.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        check(view.rangeForUserCompletion.location == NSNotFound, "marked text suppresses completion")
        view.unmarkText()
        defaults.set(13.0, forKey: "editorSize")
        let sql = view.string, selection = view.selectedRange()
        view.increaseEditorSize(nil); check(defaults.double(forKey: "editorSize") == 14, "zoom increases font preference")
        view.resetEditorSize(nil); check(defaults.double(forKey: "editorSize") == 13 && sql == view.string && selection == view.selectedRange(), "reset preserves text and selection")
        if let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) {
            scroll.flags = .maskCommand
            view.scrollWheel(with: NSEvent(cgEvent: scroll)!)
            check(defaults.double(forKey: "editorSize") == 14 && view.string == sql, "command-scroll changes font without changing SQL")
            scroll.flags = []
            view.scrollWheel(with: NSEvent(cgEvent: scroll)!)
            check(defaults.double(forKey: "editorSize") == 14, "ordinary scroll never changes font size")
        }
        let ruler = QueryLineRuler(textView: view)
        ruler.updateMetrics(font: .monospacedSystemFont(ofSize: 10, weight: .regular), text: "1\n2")
        let smallWidth = ruler.ruleThickness
        ruler.updateMetrics(font: .monospacedSystemFont(ofSize: 28, weight: .regular), text: "1\n2")
        check(ruler.ruleThickness > smallWidth * 2, "line-number gutter scales with editor size")
        let largeWidth = ruler.ruleThickness
        ruler.updateMetrics(font: .monospacedSystemFont(ofSize: 28, weight: .regular), text: String(repeating: "x\n", count: 1000))
        check(ruler.ruleThickness > largeWidth, "gutter expands for four-digit line numbers")
        let longSQL = String(repeating: "SELECT id FROM orders;\n", count: 3000) + "SEL"
        view.string = longSQL; view.setSelectedRange(NSRange(location: (longSQL as NSString).length, length: 0))
        let start = Date()
        for _ in 0..<30 { _ = view.rangeForUserCompletion }
        let ms = Date().timeIntervalSince(start) * 1000 / 30
        print("METRIC: 66003-character completion context average \(ms) ms")
        check(ms < 50, "long SQL completion context remains interactive")
    }
}
