import AppKit
import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
struct CoreChecks {
    private static var count = 0

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw CheckFailure(description: message) }
    }

    private static func textRecord(_ text: String, time: TimeInterval = 1, pinned: Bool = false) -> ClipboardRecord {
        ClipboardRecord(createdAt: Date(timeIntervalSince1970: time), lastUsedAt: Date(timeIntervalSince1970: time), sourceName: "Test Editor", sourceBundleIdentifier: "test.editor", pinned: pinned, items: [[ClipboardRepresentation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]])
    }

    private static func withBoard(_ body: (NSPasteboard) throws -> Void) throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try body(board)
    }

    private static func withStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QingTieCoreChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("history.json"))
    }

    private static func check(_ name: String, _ body: () throws -> Void) throws {
        try body()
        count += 1
        print("PASS \(name)")
    }

    static func main() {
        do { try runChecks() }
        catch {
            print("FAIL \(error)")
            exit(1)
        }
    }

    private static func runChecks() throws {
        try check("captures plain text and source metadata") {
            try withBoard { board in
                board.setString("你好 clipboard", forType: .string)
                guard let record = ClipboardCodec.capture(from: board, sourceName: "Notes", sourceBundleIdentifier: "com.apple.Notes") else { throw CheckFailure(description: "text was not captured") }
                try expect(record.text == "你好 clipboard", "text changed")
                try expect(record.sourceName == "Notes" && record.sourceBundleIdentifier == "com.apple.Notes", "source metadata missing")
                try expect(record.title == "你好 clipboard", "plain title is not readable")
            }
        }

        try check("preserves multiple items and rich/native representations") {
            try withBoard { board in
                let first = NSPasteboardItem()
                first.setString("first", forType: .string)
                first.setData(Data("{\\rtf1\\ansi first}".utf8), forType: .rtf)
                first.setData(Data("<b>first</b>".utf8), forType: .html)
                first.setData(Data([0, 1, 255, 4]), forType: .init("com.example.editor.selection"))
                let second = NSPasteboardItem()
                second.setString("second", forType: .string)
                board.writeObjects([first, second])
                guard let record = ClipboardCodec.capture(from: board, sourceName: "Editor") else { throw CheckFailure(description: "multi-item capture missing") }
                try expect(record.items.count == 2, "item boundary was lost")
                let firstTypes = Set(record.items[0].map(\.type))
                try expect(Set(["public.utf8-plain-text", "public.rtf", "public.html", "com.example.editor.selection"]).isSubset(of: firstTypes), "native representations lost")
                try expect(record.text == "first\nsecond", "multi-item text lost")
                try withBoard { destination in
                    try ClipboardCodec.write(record, to: destination)
                    let restored = ClipboardCodec.capture(from: destination, sourceName: "Destination")
                    try expect(restored?.items == record.items, "native representations changed in round trip")
                }
            }
        }

        try check("derives text from rich text without a plain representation") {
            let record = ClipboardRecord(sourceName: "Rich Editor", items: [[.init(type: NSPasteboard.PasteboardType.rtf.rawValue, data: Data("{\\rtf1\\ansi Rich \\b text\\b0}".utf8))]])
            try expect(record.text == "Rich text", "rich text is not searchable")
        }

        try check("preserves image bytes and exposes image preview") {
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jY1sAAAAASUVORK5CYII=")!
            try withBoard { board in
                board.setData(png, forType: .png)
                guard let record = ClipboardCodec.capture(from: board, sourceName: "Images") else { throw CheckFailure(description: "image capture missing") }
                try expect(record.imageData == png, "image bytes changed")
                try expect(!record.title.isEmpty, "image title is empty")
                try withBoard { destination in
                    try ClipboardCodec.write(record, to: destination)
                    try expect(destination.data(forType: .png) == png, "restored PNG changed")
                }
            }
        }

        try check("preserves multiple file URLs") {
            let firstURL = URL(fileURLWithPath: "/tmp/报告 one.pdf")
            let secondURL = URL(fileURLWithPath: "/tmp/photo.png")
            try withBoard { board in
                let first = NSPasteboardItem()
                first.setString(firstURL.absoluteString, forType: .fileURL)
                let second = NSPasteboardItem()
                second.setString(secondURL.absoluteString, forType: .fileURL)
                board.writeObjects([first, second])
                guard let record = ClipboardCodec.capture(from: board, sourceName: "Finder") else { throw CheckFailure(description: "files not captured") }
                try expect(record.fileURLs == [firstURL, secondURL], "file URLs changed")
                try expect(record.title.contains("报告 one.pdf"), "file title missing filename")
                try withBoard { destination in
                    try ClipboardCodec.write(record, to: destination)
                    try expect(ClipboardCodec.capture(from: destination, sourceName: "Finder")?.fileURLs == [firstURL, secondURL], "file restoration failed")
                }
            }
        }

        try check("plain-text restore removes rich representations") {
            var record = textRecord("clean text")
            record.items[0].append(.init(type: NSPasteboard.PasteboardType.html.rawValue, data: Data("<b>clean text</b>".utf8)))
            try withBoard { board in
                try ClipboardCodec.write(record, to: board, plainText: true)
                try expect(board.string(forType: .string) == "clean text", "plain text missing")
                try expect(board.data(forType: .html) == nil, "rich representation remained")
            }
        }

        try check("rejects empty and protected clipboard data") {
            try withBoard { board in
                try expect(ClipboardCodec.capture(from: board, sourceName: "Empty") == nil, "empty clipboard became a record")
            }
            for marker in ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.ConfidentialType", "org.nspasteboard.AutoGeneratedType"] {
                try withBoard { board in
                    let item = NSPasteboardItem()
                    item.setString("secret", forType: .string)
                    item.setData(Data(), forType: .init(marker))
                    board.writeObjects([item])
                    try expect(ClipboardCodec.capture(from: board, sourceName: "Protected") == nil, "protected content was captured for \(marker)")
                }
            }
        }

        try check("enforces aggregate capture size limit") {
            try withBoard { board in
                let item = NSPasteboardItem()
                item.setData(Data(repeating: 1, count: 13 * 1_024 * 1_024), forType: .init("test.first"))
                item.setData(Data(repeating: 2, count: 13 * 1_024 * 1_024), forType: .init("test.second"))
                board.writeObjects([item])
                try expect(ClipboardCodec.capture(from: board, sourceName: "Large") == nil, "aggregate size limit was ignored")
            }
        }

        try check("invalid restore preserves destination clipboard") {
            try withBoard { board in
                board.setString("keep me", forType: .string)
                let oversized = ClipboardRecord(sourceName: "Large", items: [[.init(type: "test.large", data: Data(repeating: 0, count: 25 * 1_024 * 1_024 + 1))]])
                var didThrow = false
                do { try ClipboardCodec.write(oversized, to: board) } catch { didThrow = true }
                try expect(didThrow && board.string(forType: .string) == "keep me", "invalid data destroyed the destination clipboard")
                didThrow = false
                do { try ClipboardCodec.write(ClipboardRecord(sourceName: "Empty", items: []), to: board, plainText: true) } catch { didThrow = true }
                try expect(didThrow && board.string(forType: .string) == "keep me", "unavailable text destroyed the destination clipboard")
            }
        }

        try check("deduplicates payload while preserving identity and pin") {
            try withStore { url in
                let history = ClipboardHistory(fileURL: url, limit: 2)
                let original = textRecord("repeat", time: 1, pinned: true)
                history.add(original)
                history.add(textRecord("other", time: 2))
                var duplicate = textRecord("repeat", time: 3)
                duplicate.sourceName = "Another Editor"
                history.add(duplicate)
                try expect(history.records.count == 2, "duplicate created a new row")
                let saved = history.records.first { $0.id == original.id }
                try expect(saved?.pinned == true && saved?.createdAt == original.createdAt, "duplicate lost identity or pin")
                try expect(saved?.lastUsedAt == duplicate.lastUsedAt && saved?.sourceName == "Another Editor", "duplicate recency/source did not refresh")
            }
        }

        try check("dedup ignores representation ordering but preserves item ordering") {
            try withStore { url in
                let history = ClipboardHistory(fileURL: url)
                var original = textRecord("native")
                original.items[0].append(.init(type: "custom.binary", data: Data([42])))
                history.add(original)
                var reordered = original
                reordered.id = UUID()
                reordered.items[0].reverse()
                history.add(reordered)
                try expect(history.records.count == 1, "representation ordering defeated dedup")
                history.add(ClipboardRecord(sourceName: "Editor", items: [original.items[0], textRecord("second").items[0]]))
                history.add(ClipboardRecord(sourceName: "Editor", items: [textRecord("second").items[0], original.items[0]]))
                try expect(history.records.count == 3, "different item ordering was incorrectly deduplicated")
            }
        }

        try check("limits only unpinned history and sorts pins first") {
            try withStore { url in
                let history = ClipboardHistory(fileURL: url, limit: 2)
                let pinned = textRecord("saved", time: 1, pinned: true)
                history.add(pinned)
                history.add(textRecord("old", time: 2))
                history.add(textRecord("middle", time: 3))
                history.add(textRecord("new", time: 4))
                try expect(history.records.map(\.text) == ["saved", "new", "middle"], "pin sorting or unpinned limit incorrect")
                history.setLimit(1)
                try expect(history.records.map(\.text) == ["saved", "new"], "reduced limit removed a pin")
                history.setLimit(0)
                try expect(history.records.count == 1 && history.records[0].id == pinned.id, "zero limit must retain pins")
            }
        }

        try check("pin toggle, remove and clear persist") {
            try withStore { url in
                let history = ClipboardHistory(fileURL: url)
                let saved = textRecord("saved", time: 1)
                let other = textRecord("other", time: 2)
                history.add(saved)
                history.add(other)
                history.togglePin(saved.id)
                history.clearUnpinned()
                try expect(history.records.count == 1 && history.records[0].pinned, "clear removed a pin")
                let restored = ClipboardHistory(fileURL: url)
                try expect(restored.records == history.records, "history did not round-trip")
                restored.togglePin(saved.id)
                try expect(!restored.records[0].pinned, "unpin failed")
                restored.remove(saved.id)
                try expect(restored.records.isEmpty && ClipboardHistory(fileURL: url).records.isEmpty, "remove did not persist")
            }
        }

        try check("search matches text, source and filenames") {
            try withStore { url in
                let history = ClipboardHistory(fileURL: url)
                history.add(textRecord("Café meeting", time: 1))
                history.add(ClipboardRecord(sourceName: "Finder", items: [[.init(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data(URL(fileURLWithPath: "/tmp/季度报告.pdf").absoluteString.utf8))]]))
                try expect(history.filtered(query: "CAFE").count == 1, "case/diacritic search failed")
                try expect(history.filtered(query: "test.editor").count == 1, "bundle identifier search failed")
                try expect(history.filtered(query: "季度报告").count == 1, "filename search failed")
                try expect(history.filtered(query: "  ").count == 2, "empty query filtered records")
            }
        }

        try check("corrupt history remains untouched and reports error") {
            try withStore { url in
                let invalid = Data("{this is not valid JSON".utf8)
                try invalid.write(to: url)
                let history = ClipboardHistory(fileURL: url)
                try expect(history.errorMessage != nil && history.records.isEmpty, "corrupt load was silently accepted")
                history.add(textRecord("replacement"))
                history.clearUnpinned()
                history.setLimit(1)
                try expect(try Data(contentsOf: url) == invalid, "corrupt original was overwritten")
                try expect(history.errorMessage != nil, "corruption error disappeared")
            }
        }

        try check("failed persistence leaves published records unchanged") {
            try withStore { url in
                let blockingFile = url.deletingLastPathComponent().appendingPathComponent("parent-file")
                try Data("blocked".utf8).write(to: blockingFile)
                let history = ClipboardHistory(fileURL: blockingFile.appendingPathComponent("history.json"))
                history.add(textRecord("not saved"))
                try expect(history.records.isEmpty && history.errorMessage != nil, "failed save was reported as successful")
            }
        }

        try check("history remains private when its parent directory is shared") {
            try withStore { url in
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
                let history = ClipboardHistory(fileURL: url)
                history.add(textRecord("private"))
                let initialAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                try expect((initialAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "new history file is accessible to other users")
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                history.add(textRecord("still private", time: 2))
                let updatedAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
                try expect((updatedAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "rewritten history file is accessible to other users")
                try expect(ClipboardHistory(fileURL: url).records == history.records, "private persistence changed content")
            }
        }

        print("\(count) core checks passed")
    }
}
