import AppKit
import Foundation

private struct SourceIconCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
struct SourceApplicationIconChecks {
    private static var checks = 0

    static func main() {
        _ = NSApplication.shared
        do {
            try runChecks()
            print("\(checks) source application icon checks passed")
        } catch {
            print("FAIL \(error)")
            exit(1)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SourceIconCheckFailure(description: message) }
    }

    private static func check(_ name: String, _ body: () throws -> Void) throws {
        try body()
        checks += 1
        print("PASS \(name)")
    }

    private static func systemIcon(bundleIdentifier: String) throws -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw SourceIconCheckFailure(description: "required system application is unavailable: \(bundleIdentifier)")
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func pixels(of image: NSImage?) throws -> Data {
        guard let image,
              let context = CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw SourceIconCheckFailure(description: "the application icon could not be rendered")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64), from: .zero, operation: .copy, fraction: 1)
        guard let data = context.data else {
            throw SourceIconCheckFailure(description: "the application icon has no rendered pixels")
        }
        // Compare the displayed icon, independent of encoded representations or metadata.
        return Data(bytes: data, count: 64 * 64 * 4)
    }

    private static func runChecks() throws {
        for (identifier, unrelatedName) in [
            ("com.apple.Notes", "Terminal"),
            ("com.apple.Terminal", "Notes")
        ] {
            try check("installed \(identifier) uses its system icon regardless of record name") {
                let expected = try systemIcon(bundleIdentifier: identifier)
                let actual = SourceApplicationIcon.image(bundleIdentifier: identifier, name: unrelatedName)
                let actualPixels = try pixels(of: actual)
                let expectedPixels = try pixels(of: expected)
                try expect(actualPixels == expectedPixels, "the bundle ID did not select its authentic application icon")
            }
        }

        try check("authentic system icons render distinctly from other applications and the fallback") {
            let notes = try pixels(of: systemIcon(bundleIdentifier: "com.apple.Notes"))
            let terminal = try pixels(of: systemIcon(bundleIdentifier: "com.apple.Terminal"))
            let fallback = try pixels(of: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil))
            try expect(notes != terminal, "different applications rendered the same blank or generic icon")
            try expect(notes != fallback && terminal != fallback, "an authentic icon rendered the fallback symbol")
            for icon in [notes, terminal] {
                try expect(stride(from: 3, to: icon.count, by: 4).contains { icon[$0] != 0 }, "an authentic icon rendered entirely transparent")
            }
        }

        try check("an unavailable authoritative bundle ID cannot use a matching application name") {
            let icon = SourceApplicationIcon.image(
                bundleIdentifier: "invalid.qingtie.source-icon-check.missing-app",
                name: "Terminal"
            )
            try expect(icon == nil, "an unavailable app was associated with Terminal through its record name")
        }

        try check("an application name without a bundle identifier resolves through the system") {
            let expected = try systemIcon(bundleIdentifier: "com.apple.Terminal")
            let actual = SourceApplicationIcon.image(bundleIdentifier: nil, name: "Terminal")
            let actualPixels = try pixels(of: actual)
            let expectedPixels = try pixels(of: expected)
            try expect(actualPixels == expectedPixels, "a Terminal record without a bundle identifier did not use its system application icon")
        }

        try check("empty and invalid application names return no application icon") {
            for name in ["", "   ", "QingTieDefinitelyMissingSourceApplication-9F742B", "../Terminal"] {
                try expect(SourceApplicationIcon.image(bundleIdentifier: nil, name: name) == nil, "invalid application name resolved an application: \(name)")
            }
        }

        try check("application names cannot be interpreted as application paths") {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                throw SourceIconCheckFailure(description: "Terminal is unavailable")
            }
            try expect(SourceApplicationIcon.image(bundleIdentifier: nil, name: url.path) == nil, "an application name was interpreted as a filesystem path")
        }

        try check("repeated bundle ID lookups reuse the cached image across record names") {
            let first = SourceApplicationIcon.image(bundleIdentifier: "com.apple.Terminal", name: "Terminal")
            let second = SourceApplicationIcon.image(bundleIdentifier: "com.apple.Terminal", name: "Renamed Terminal")
            try expect(first != nil && first === second, "a repeated bundle ID lookup recreated its system icon")
        }

        try check("the cache reuses successful lookups") {
            let cache = SourceApplicationIconCache(capacity: 2)
            let expected = NSImage(size: NSSize(width: 16, height: 16))
            var resolutions = 0
            let first = cache.image(for: "installed") { resolutions += 1; return expected }
            let second = cache.image(for: "installed") { resolutions += 1; return nil }
            try expect(first === expected && second === expected && resolutions == 1, "a cached success ran its resolver again")
        }

        try check("the cache remembers unavailable applications") {
            let cache = SourceApplicationIconCache(capacity: 2)
            var resolutions = 0
            for _ in 0..<3 {
                let image = cache.image(for: "missing") { resolutions += 1; return nil }
                try expect(image == nil, "an unavailable application acquired an icon")
            }
            try expect(resolutions == 1, "an unavailable app was looked up repeatedly")
        }

        try check("both successful and unavailable lookups count toward the cache bound") {
            let cache = SourceApplicationIconCache(capacity: 2)
            let expected = NSImage(size: NSSize(width: 16, height: 16))
            var resolutions = 0
            _ = cache.image(for: "first") { resolutions += 1; return expected }
            _ = cache.image(for: "missing") { resolutions += 1; return nil }
            _ = cache.image(for: "third") { resolutions += 1; return expected }
            _ = cache.image(for: "first") { resolutions += 1; return expected }
            _ = cache.image(for: "missing") { resolutions += 1; return nil }
            try expect(resolutions == 5, "successes or misses escaped the bounded cache eviction")
        }
    }
}
