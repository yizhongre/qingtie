import AppKit
import Foundation

@main struct WatcherChecks {
  @MainActor static func main() {
    let board = NSPasteboard(name: .init("QingTie-watcher-tests-\(UUID())"))
    defer { board.releaseGlobally() }
    var output: [ClipboardRecord] = []
    var paused = false
    let watcher = ClipboardWatcher(pasteboard: board, sourceName: "Secret", sourceBundleIdentifier: "test.secret", canRecord: { !paused }, isExcluded: { $0 == "test.secret" }, onCapture: { output.append($0) })
    func copy(_ value: String) { board.clearContents(); board.setString(value, forType: .string) }
    copy("excluded copy before switching")
    watcher.sourceDidChange(name: "Editor", bundleIdentifier: "test.editor")
    watcher.poll()
    precondition(output.isEmpty, "excluded copy leaked after focus changed")
    copy("safe copy")
    watcher.poll()
    precondition(output.count == 1 && output[0].sourceBundleIdentifier == "test.editor")
    copy("safe pending transition")
    watcher.sourceDidChange(name: "Notes", bundleIdentifier: "test.notes")
    precondition(output.count == 2 && output[1].sourceBundleIdentifier == "test.editor")
    paused = true
    copy("paused copy")
    watcher.poll()
    paused = false
    watcher.poll()
    precondition(output.count == 2, "paused data replayed after resuming")
    copy("own clipboard write")
    watcher.markCurrentChangeHandled()
    watcher.poll()
    precondition(output.count == 2, "own write recaptured")
    copy("ambiguous transition to excluded")
    watcher.sourceDidChange(name: "Secret", bundleIdentifier: "test.secret")
    watcher.poll()
    precondition(output.count == 2)
    print("PASS: 6 clipboard watching checks (excluded app switch, source, pause, own writes)")
  }
}
