import AppKit
import SwiftUI

/// Keeps application discovery off repeated row renders, including unsuccessful lookups.
@MainActor
final class SourceApplicationIconCache {
    private struct Entry {
        let image: NSImage?
    }

    private let capacity: Int
    private var entries: [String: Entry] = [:]
    private var insertionOrder: [String] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func image(for key: String, resolve: () -> NSImage?) -> NSImage? {
        if let entry = entries[key] { return entry.image }
        let image = resolve()
        if insertionOrder.count == capacity {
            entries.removeValue(forKey: insertionOrder.removeFirst())
        }
        entries[key] = Entry(image: image)
        insertionOrder.append(key)
        return image
    }
}

@MainActor
enum SourceApplicationIcon {
    private static let cache = SourceApplicationIconCache(capacity: 256)

    static func image(bundleIdentifier: String?, name: String) -> NSImage? {
        let identifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !identifier.isEmpty {
            return cache.image(for: "bundle:\(identifier)") {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
                    return nil
                }
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }

        let applicationName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !applicationName.isEmpty,
              !applicationName.contains("/"),
              !applicationName.contains(":"),
              !applicationName.contains("\0") else { return nil }
        return cache.image(for: "name:\(applicationName)") {
            // Name lookup supports records whose source has no bundle identifier.
            guard let path = NSWorkspace.shared.fullPath(forApplication: applicationName) else { return nil }
            return NSWorkspace.shared.icon(forFile: path)
        }
    }
}

@MainActor
struct SourceApplicationIconView: View {
    let bundleIdentifier: String?
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image = SourceApplicationIcon.image(bundleIdentifier: bundleIdentifier, name: name) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
