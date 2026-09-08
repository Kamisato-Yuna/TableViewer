import SwiftUI
import Observation
// A minimal observable host state; editor and binding code are extracted verbatim
// from QueryEditorView. This test covers UI lifecycle, not database persistence.
@MainActor @Observable final class WorkspaceStore {
 var query = ""
 var selectedScriptID: UUID?
 var querySelection = NSRange(location: 0, length: 0)
 var active: ConnectionProfile? = ConnectionProfile()
 var busy = false
 var objects: [DatabaseObject] = []
 var showSlowQuerySuggestion = false
 func setEstimatesEnabled(_ enabled: Bool) {}
 @ObservationIgnored var queryEditorViews: [UUID: NSScrollView] = [:]
 func runQuery() async {}
}
@main struct EditorUndoLifecycleTests {
 @MainActor static func main() {
  _ = NSApplication.shared
  let store=WorkspaceStore(), aID=UUID(), bID=UUID()
  store.selectedScriptID=aID;store.query="SELECT 40;"
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:400),styleMask:[.titled],backing:.buffered,defer:false)
  let host=NSHostingView(rootView:QueryEditorHost(store:store));window.contentView=host
  func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.15)) }
  settle()
  guard let a=store.queryEditorViews[aID]?.documentView as? QueryTextView else { fatalError("A did not mount") }
  func findSplit(_ view: NSView) -> NSSplitView? {
   if let split = view as? NSSplitView { return split }
   return view.subviews.lazy.compactMap { findSplit($0) }.first
  }
  guard let split = findSplit(host) else { fatalError("Owned split did not mount") }
  split.setPosition(300, ofDividerAt: 0);settle()
  precondition(abs(split.arrangedSubviews[0].frame.width - 300) < 1)
  precondition(store.queryEditorViews[aID]?.documentView === a && a.string == "SELECT 40;")
  split.isVertical=false;split.adjustSubviews();split.setPosition(180,ofDividerAt:0);settle()
  precondition(abs(split.arrangedSubviews[0].frame.height - 180) < 1)
  precondition(store.queryEditorViews[aID]?.documentView === a)
  split.isVertical=true;split.adjustSubviews();settle()
  print("PASS owned dividerless split: both axes resize without replacing the editor")
  a.setSelectedRange(NSRange(location:(a.string as NSString).length,length:0))
  let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
  board.declareTypes([.string],owner:nil)
  guard board.setString("y",forType:.string) else { fputs("Independent AppKit pasteboard unavailable\n",stderr); exit(2) }
  precondition(a.readSelection(from:board,type:.string));a.breakUndoCoalescing();settle()
  print("A after paste",store.query,a.undoManager!.canUndo)
  precondition(NSApp.sendAction(NSSelectorFromString("undo:"),to:a,from:nil));settle()
  print("A after undo",store.query,a.undoManager!.canRedo)
  let aText=store.query
  store.selectedScriptID=nil;store.query="SELECT 99;";store.selectedScriptID=bID;settle()
  print("A while B active",a.string,a.undoManager!.canRedo)
  // A's stale native callback must not mutate the active script.
  if let delegate=a.delegate as? CodeEditor.Coordinator {
   delegate.textDidChange(Notification(name:NSText.didChangeNotification,object:a))
   delegate.textViewDidChangeSelection(Notification(name:NSTextView.didChangeSelectionNotification,object:a))
  }
  print("B after stale callback",store.query)
  precondition(store.query=="SELECT 99;")
  store.selectedScriptID=nil;store.query=aText;store.selectedScriptID=aID;settle()
  guard let restored=store.queryEditorViews[aID]?.documentView as? QueryTextView else { fatalError("A missing") }
  print("A restored",restored===a,restored.string,restored.undoManager!.canRedo)
  precondition(restored===a && restored.undoManager!.canRedo)
  precondition(NSApp.sendAction(NSSelectorFromString("redo:"),to:restored,from:nil));settle()
  precondition(store.query=="SELECT 40;y")
  print("PASS actual SwiftUI hosting lifecycle: redo survives A/B/A and stale delegate does not write B")
  window.contentView=nil
 }
}
