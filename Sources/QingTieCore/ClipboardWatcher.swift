import AppKit

/// Attributes pending changes before switching the observed foreground source.
@MainActor
public final class ClipboardWatcher {
  private let pasteboard: NSPasteboard
  private let canRecord: () -> Bool
  private let isExcluded: (String?) -> Bool
  private let onCapture: (ClipboardRecord) -> Void
  private var sourceName: String
  private var sourceBundleIdentifier: String?
  private var lastChange: Int

  public init(pasteboard: NSPasteboard, sourceName: String, sourceBundleIdentifier: String?,
              canRecord: @escaping () -> Bool, isExcluded: @escaping (String?) -> Bool,
              onCapture: @escaping (ClipboardRecord) -> Void) {
    self.pasteboard = pasteboard
    self.sourceName = sourceName
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.canRecord = canRecord
    self.isExcluded = isExcluded
    self.onCapture = onCapture
    lastChange = pasteboard.changeCount
  }

  public func poll() { capturePending(suppress: false) }

  public func sourceDidChange(name: String, bundleIdentifier: String?) {
    // A change at an excluded-app boundary is ambiguous, so discard it.
    capturePending(suppress: isExcluded(bundleIdentifier))
    sourceName = name
    sourceBundleIdentifier = bundleIdentifier
  }

  public func markCurrentChangeHandled() { lastChange = pasteboard.changeCount }

  private func capturePending(suppress: Bool) {
    let change = pasteboard.changeCount
    guard change != lastChange else { return }
    lastChange = change
    guard !suppress, canRecord(), !isExcluded(sourceBundleIdentifier) else { return }
    if let record = ClipboardCodec.capture(from: pasteboard, sourceName: sourceName,
                                           sourceBundleIdentifier: sourceBundleIdentifier) {
      onCapture(record)
    }
  }
}
