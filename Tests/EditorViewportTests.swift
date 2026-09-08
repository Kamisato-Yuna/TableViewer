import SwiftUI

@main struct EditorViewportTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let source = (1...80).map { "-- line \($0) " + String(repeating: "abcdefghij ", count: 15) + "\nSELECT \($0);" }.joined(separator: "\n")
        var scroll: NSScrollView?
        let host = NSHostingView(rootView: QuerySplitContainer {
            CodeEditor(text: .constant(source), topContentInset: 40, retainView: { scroll = $0 })
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        settle()
        guard let scroll, let text = scroll.documentView as? QueryTextView,
              let layout = text.layoutManager, let container = text.textContainer else { fatalError("Editor did not mount") }
        // Scrollable text extends below the overlaid toolbar; revealing a range
        // must place it below that toolbar, including after jumping upward.
        func assertBelowToolbar(_ range: NSRange) {
            text.setSelectedRange(range)
            text.scrollRangeToVisible(range)
            settle()
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.y += text.textContainerOrigin.y
            let inScroll = text.convert(rect, to: scroll)
            precondition(inScroll.minY >= 40, "Revealed selection is covered by the frosted toolbar")
        }
        assertBelowToolbar((source as NSString).range(of: "SELECT 1;"))
        assertBelowToolbar((source as NSString).range(of: "SELECT 60;"))
        assertBelowToolbar((source as NSString).range(of: "SELECT 30;"))
        let selection = (source as NSString).range(of: "SELECT 80;")
        func selectionRect() -> NSRect {
            layout.ensureLayout(for: container)
            var rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil), in: container)
            rect.origin.x += text.textContainerOrigin.x
            rect.origin.y += text.textContainerOrigin.y
            return rect
        }
        text.setSelectedRange(selection)
        window.makeFirstResponder(text)
        text.scrollRangeToVisible(selection)
        settle()
        precondition(text.visibleRect.intersects(selectionRect()))
        window.setContentSize(NSSize(width: 430, height: 300))
        settle()
        precondition(text.visibleRect.intersects(selectionRect()), "Visible selection disappeared after narrow rewrap")
        precondition(text.string == source && text.selectedRange() == selection)
        window.setContentSize(NSSize(width: 900, height: 300))
        settle()
        precondition(text.visibleRect.intersects(selectionRect()), "Visible selection disappeared after widening")
        window.contentView = nil
        window.contentView = host
        settle()
        precondition(text.visibleRect.intersects(selectionRect()), "Reattached editor lost the visible selection")
        // A user who scrolled away from the caret must retain that reading position.
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        precondition(!text.visibleRect.intersects(selectionRect()))
        window.setContentSize(NSSize(width: 430, height: 300))
        settle()
        precondition(!text.visibleRect.intersects(selectionRect()), "Resize overrode manual scrolling")
        precondition(text.string == source && text.selectedRange() == selection)
        print("PASS viewport resize: selected SQL remains visible; manual scrolling, text and selection remain intact")
        window.contentView = nil
    }
}
