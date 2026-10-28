import AppKit
import Combine
import Foundation
import QingTieCore

private struct PanelCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
struct PanelStateChecks {
    private static var checks = 0

    static func main() {
        _ = NSApplication.shared
        do {
            try runChecks()
            print("\(checks) panel checks passed")
        } catch {
            print("FAIL \(error)")
            exit(1)
        }
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw PanelCheckFailure(description: message) }
    }

    private static func check(_ name: String, _ body: () throws -> Void) throws {
        try body()
        checks += 1
        print("PASS \(name)")
    }

    private static func record(
        _ text: String? = nil,
        time: TimeInterval,
        representations: [ClipboardRepresentation] = []
    ) -> ClipboardRecord {
        var payload = representations
        if let text {
            payload.append(.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)))
        }
        return ClipboardRecord(
            createdAt: Date(timeIntervalSince1970: time),
            lastUsedAt: Date(timeIntervalSince1970: time),
            sourceName: "Synthetic Test Editor",
            sourceBundleIdentifier: "test.qingtie.synthetic-editor",
            items: [payload]
        )
    }

    private static func withState(
        records: [ClipboardRecord]? = nil,
        _ body: (ClipboardPanelState, ClipboardHistory) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QingTiePanelChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = ClipboardHistory(fileURL: directory.appendingPathComponent("synthetic.json"))
        for record in records ?? [record("alpha", time: 1), record("beta", time: 2), record("gamma", time: 3)] {
            history.add(record)
        }
        try expect(history.errorMessage == nil, "synthetic fixture could not be stored")
        let state = ClipboardPanelState(history: history)
        state.prepareToShow()
        try body(state, history)
    }

    private static func key(
        _ code: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        window: NSWindow? = nil,
        type: NSEvent.EventType = .keyDown
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        )!
    }

    private static func waitForPublishedChange(_ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 1)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private static func runChecks() throws {
        try check("panel fits smaller visible screens without losing its controls") {
            let normal = ClipboardPanelLayout.size(showPreview: true, visibleSize: NSSize(width: 1280, height: 800))
            try expect(normal == NSSize(width: 861, height: 600), "normal display changed the approved panel proportions")
            let small = ClipboardPanelLayout.size(showPreview: true, visibleSize: NSSize(width: 800, height: 560))
            try expect(small == NSSize(width: 776, height: 536), "expanded panel exceeds the usable display")
            let compact = ClipboardPanelLayout.size(showPreview: false, visibleSize: NSSize(width: 800, height: 560))
            try expect(compact == NSSize(width: 460, height: 536), "compact panel exceeds the usable display")
            try expect(ClipboardPanelLayout.size(showPreview: true, visibleSize: nil) == normal, "screen-less initial size is inconsistent")
        }

        try check("content categories exclude file and image text representations") {
            let image = ClipboardRepresentation(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([137, 80, 78, 71]))
            let file = ClipboardRepresentation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/mint.png".utf8))
            let note = record("mint note", time: 1)
            let link = record("  \nhttps://example.com/mint?q=1#details\t", time: 2)
            let prose = record("Read https://example.com/mint for details", time: 3)
            let imageWithText = record("https://example.com/image", time: 4, representations: [image])
            let fileWithText = record("https://example.com/file", time: 5, representations: [file])
            let fileWithImage = record(time: 6, representations: [file, image])
            let imageOnly = record(time: 7, representations: [image])
            let fixtures = [note, link, prose, imageWithText, fileWithText, fileWithImage, imageOnly]
            try withState(records: fixtures) { state, _ in
                try expect(state.visibleRecords.map(\.id) == [imageOnly.id, fileWithImage.id, fileWithText.id, imageWithText.id, prose.id, link.id, note.id], "all category omitted or reordered a payload")
                state.contentFilter = .text
                try expect(state.visibleRecords.map(\.id) == [prose.id, note.id], "text category included a link, image, or file representation")
                state.contentFilter = .image
                try expect(state.visibleRecords.map(\.id) == [imageOnly.id, imageWithText.id], "image category included file rows or lost an image with text")
                state.contentFilter = .link
                try expect(state.visibleRecords.map(\.id) == [link.id], "link category accepted prose, images, or files with URL text")
                state.contentFilter = .all
                try expect(state.visibleRecords.count == 7, "returning to all did not restore file rows")
            }
        }

        try check("link category requires one complete HTTP or HTTPS URL") {
            let cases: [(String, Bool)] = [
                ("https://example.com/mint?q=1#details", true),
                (" \nHTTP://example.com/path\t", true),
                ("https://example.com/a%20b", true),
                ("Read https://example.com/mint", false),
                ("https://example.com/mint extra prose", false),
                ("https://example.com/hello world", false),
                ("https://example.com\nhttps://example.org", false),
                ("ftp://example.com/mint", false),
                ("mailto:mint@example.com", false),
                ("example.com/mint", false),
                ("https://", false),
                ("http:example.com", false)
            ]
            for (text, isLink) in cases {
                let fixture = record(text, time: 1)
                try withState(records: [fixture]) { state, _ in
                    state.contentFilter = .link
                    try expect(state.visibleRecords.map(\.id) == (isLink ? [fixture.id] : []), "incorrect link classification for \(text.debugDescription)")
                    state.contentFilter = .text
                    try expect(state.visibleRecords.map(\.id) == (isLink ? [] : [fixture.id]), "link and text categories overlapped or lost text for \(text.debugDescription)")
                }
            }
        }

        try check("content categories intersect the existing multi-term search") {
            let note = record("mint note", time: 1)
            let otherNote = record("coral note", time: 2)
            let link = record("https://example.com/mint", time: 3)
            let image = record("mint image", time: 4, representations: [.init(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([137, 80, 78, 71]))])
            try withState(records: [note, otherNote, link, image]) { state, _ in
                state.query = "MINT synthetic"
                try expect(state.visibleRecords.map(\.id) == [image.id, link.id, note.id], "all category changed the existing case-insensitive multi-term search")
                state.contentFilter = .text
                try expect(state.visibleRecords.map(\.id) == [note.id] && state.query == "MINT synthetic", "text category ignored or reset search")
                state.contentFilter = .link
                try expect(state.visibleRecords.map(\.id) == [link.id], "link category ignored search")
                state.contentFilter = .image
                try expect(state.visibleRecords.map(\.id) == [image.id], "image category ignored search")
                state.query = "coral"
                try expect(state.visibleRecords.isEmpty, "search returned a record outside its category")
            }
        }

        try check("category changes preserve a visible selection and reconcile hidden selections") {
            let firstNote = record("mint note", time: 1)
            let otherNote = record("coral note", time: 2)
            let link = record("https://example.com/mint", time: 3)
            try withState(records: [firstNote, otherNote, link]) { state, _ in
                var uses = 0
                var copies = 0
                state.onUse = { _, _ in uses += 1 }
                state.onCopy = { _ in copies += 1 }
                state.contentFilter = .text
                try expect(state.selectedID == otherNote.id, "category retained a hidden selection instead of selecting its first result")
                state.selectForPreview(firstNote)
                state.contentFilter = .all
                try expect(state.selectedID == firstNote.id && state.selectionFollowsPointer, "category discarded a still-visible pointer selection")
                state.contentFilter = .link
                try expect(state.selectedID == link.id && !state.selectionFollowsPointer, "category did not reconcile a hidden pointer selection")
                state.contentFilter = .image
                try expect(state.selectedID == nil && !state.handleKey(key(125)) && !state.handleKey(key(36)), "empty category retained or used a stale selection")
                state.contentFilter = .text
                try expect(state.selectedID == otherNote.id && uses == 0 && copies == 0, "restoring category did not select its first row or triggered a copy")
            }
        }

        try check("reopening resets category and search while preserving preview preference") {
            let note = record("mint note", time: 2)
            let link = record("https://example.com/mint", time: 1)
            try withState(records: [note, link]) { state, _ in
                state.contentFilter = .link
                state.query = "example"
                state.showPreview = false
                state.statusMessage = "temporary message"
                let token = state.searchFocusToken
                state.prepareToShow()
                try expect(state.contentFilter == .all && state.query.isEmpty, "reopening retained a hidden category or stale search")
                try expect(state.selectedID == note.id && !state.showPreview, "reopening selected a filtered row or discarded preview preference")
                try expect(state.statusMessage.isEmpty && state.searchFocusToken != token, "reopening retained transient status or failed to request focus")
            }
        }

        try check("pinned groups share filtered display order and global numeric shortcuts") {
            let oldLink = record("https://example.com/mint-old", time: 1)
            let pinnedNote = record("mint old note", time: 2)
            let recentNote = record("mint new note", time: 3)
            let recentLink = record("https://example.com/mint-new", time: 4)
            try withState(records: [oldLink, pinnedNote, recentNote, recentLink]) { state, history in
                history.togglePin(oldLink.id)
                history.togglePin(pinnedNote.id)
                try expect(state.pinnedRecords.map(\.id) == [pinnedNote.id, oldLink.id], "pinned group lost history order")
                try expect(state.recentRecords.map(\.id) == [recentLink.id, recentNote.id], "recent group included pinned rows or reordered history")
                try expect((state.pinnedRecords + state.recentRecords).map(\.id) == [pinnedNote.id, oldLink.id, recentLink.id, recentNote.id], "group flattening changed the visible order")
                try expect(state.shortcutNumber(for: recentLink.id) == 3, "recent group restarted numeric shortcut labels")
                state.contentFilter = .link
                state.query = "mint"
                try expect(state.pinnedRecords.map(\.id) == [oldLink.id] && state.recentRecords.map(\.id) == [recentLink.id], "groups ignored category or search")
                try expect(state.shortcutNumber(for: oldLink.id) == 1 && state.shortcutNumber(for: recentLink.id) == 2, "filtered group labels did not follow flattened order")
                var uses: [UUID] = []
                state.onUse = { uses.append($0.id); _ = $1 }
                try expect(state.handleKey(key(18, characters: "1", modifiers: .command)), "pinned category shortcut was not handled")
                try expect(state.handleKey(key(19, characters: "2", modifiers: .command)), "recent category shortcut was not handled")
                try expect(uses == [oldLink.id, recentLink.id], "grouped category shortcuts used history positions")
                state.query = "new"
                try expect(state.pinnedRecords.isEmpty && state.recentRecords.map(\.id) == [recentLink.id], "groups retained rows excluded by search")
                try expect(state.shortcutNumber(for: recentLink.id) == 1 && state.shortcutNumber(for: oldLink.id) == nil, "search left stale grouped shortcut numbers")
                state.query = "mint"
                history.togglePin(recentLink.id)
                try expect(state.pinnedRecords.map(\.id) == [recentLink.id, oldLink.id] && state.recentRecords.isEmpty, "pinning a filtered row left it in recent rows")
                try expect(state.selectedID == recentLink.id && state.shortcutNumber(for: oldLink.id) == 2, "pin reordering lost selection or global shortcut position")
            }
        }

        try check("Command-F requests search focus without changing results or using content") {
            let link = record("https://example.com/mint", time: 1)
            try withState(records: [link]) { state, _ in
                state.contentFilter = .link
                state.query = "mint"
                state.selectForPreview(link)
                state.showPreview = false
                var uses = 0
                var copies = 0
                state.onUse = { _, _ in uses += 1 }
                state.onCopy = { _ in copies += 1 }
                let firstToken = state.searchFocusToken
                state.focusSearch()
                try expect(state.searchFocusToken != firstToken, "explicit search focus did not issue a new request")
                let secondToken = state.searchFocusToken
                try expect(state.handleKey(key(3, characters: "f", modifiers: [.command, .capsLock])), "Command-F was not handled")
                try expect(state.searchFocusToken != secondToken, "Command-F did not issue a fresh focus request")
                try expect(state.query == "mint" && state.contentFilter == .link && state.selectedID == link.id, "Command-F reset search, category, or selection")
                try expect(state.selectionFollowsPointer && !state.showPreview && uses == 0 && copies == 0, "search focus changed preview behavior or used content")
            }
        }

        try check("preview is visible by default") {
            try withState { state, _ in
                try expect(state.showPreview, "opening the panel hid its preview")
            }
        }

        try check("restored preview preference survives opening and search changes") {
            try withState { _, history in
                for preference in [false, true] {
                    let state = ClipboardPanelState(history: history, showPreview: preference)
                    state.prepareToShow()
                    state.query = "no matching record"
                    state.prepareToShow()
                    try expect(state.showPreview == preference, "restored preview preference was discarded")
                }
            }
        }

        try check("Command-1 through Command-9 use the matching visible row") {
            try withState { state, history in
                for number in 4...10 {
                    history.add(record("row \(number)", time: TimeInterval(number)))
                }
                var usedTexts: [String] = []
                var plainTextModes: [Bool] = []
                state.onUse = { usedTexts.append($0.text ?? ""); plainTextModes.append($1) }
                let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
                for (index, code) in numberRow.enumerated() {
                    try expect(state.handleKey(key(code, characters: String(index + 1), modifiers: .command)), "Command-\(index + 1) was not handled")
                }
                try expect(usedTexts == ["row 10", "row 9", "row 8", "row 7", "row 6", "row 5", "row 4", "gamma", "beta"], "numeric shortcuts used the wrong displayed rows")
                try expect(plainTextModes == Array(repeating: false, count: 9), "numeric shortcuts did not use normal paste mode")
                try expect(state.selectedRecord?.text == "beta", "numeric paste did not update selection")
            }
        }

        try check("numeric shortcuts follow filtering and pin reordering") {
            try withState { state, history in
                var uses: [String] = []
                state.onUse = { uses.append($0.text ?? ""); _ = $1 }
                let alpha = history.records.first { $0.text == "alpha" }!
                history.togglePin(alpha.id)
                try expect(state.handleKey(key(18, modifiers: .command)), "physical Command-1 was not handled")
                try expect(uses == ["alpha"], "Command-1 ignored the pinned-first display order")
                state.query = "beta"
                try expect(state.handleKey(key(18, characters: "1", modifiers: .command)), "filtered Command-1 was not handled")
                try expect(uses == ["alpha", "beta"], "Command-1 used the unfiltered history position")
                let selected = state.selectedID
                try expect(!state.handleKey(key(19, characters: "2", modifiers: .command)), "missing filtered row consumed Command-2")
                try expect(state.selectedID == selected && uses.count == 2, "missing filtered row changed selection or pasted")
                state.query = "no matching record"
                try expect(!state.handleKey(key(18, modifiers: .command)) && uses.count == 2, "empty search used a stale record")
            }
        }

        try check("numeric shortcuts use characters and number-row or keypad fallback") {
            try withState { state, history in
                for number in 4...9 { history.add(record("row \(number)", time: TimeInterval(number))) }
                var uses: [String] = []
                state.onUse = { uses.append($0.text ?? ""); _ = $1 }
                let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
                let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]
                for code in numberRow {
                    try expect(state.handleKey(key(code, modifiers: .command)), "empty-character number-row key \(code) was not handled")
                }
                for code in keypad {
                    try expect(state.handleKey(key(code, modifiers: [.command, .numericPad, .capsLock])), "numeric keypad key \(code) was not handled")
                }
                let expected = ["row 9", "row 8", "row 7", "row 6", "row 5", "row 4", "gamma", "beta", "alpha"]
                try expect(uses == expected + expected, "physical number keys mapped to the wrong rows")
                try expect(state.handleKey(key(18, characters: "3", modifiers: .command)), "layout-provided digit was not handled")
                try expect(uses.last == "row 7", "physical key overrode the event's digit")
                let selected = state.selectedID
                try expect(!state.handleKey(key(18, characters: "0", modifiers: .command)), "Command-0 fell back to a physical Command-1")
                state.onUse = nil
                try expect(!state.handleKey(key(18, modifiers: .command)), "numeric shortcut consumed an event without a paste callback")
                try expect(state.selectedID == selected && uses.count == 19, "unavailable numeric action changed selection")
            }
        }

        try check("numeric shortcuts operate while the search field editor is focused") {
            try withState { state, _ in
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 60), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let search = NSSearchField(frame: NSRect(x: 10, y: 10, width: 220, height: 30))
                window.contentView = search
                defer { window.close() }
                try expect(window.makeFirstResponder(search), "could not focus the synthetic search field")
                try expect(window.firstResponder is NSTextView, "search field did not install its field editor")
                state.query = "beta"
                var usedText: String?
                state.onUse = { usedText = $0.text; _ = $1 }
                try expect(state.handleKey(key(18, characters: "1", modifiers: .command, window: window)), "focused search field blocked Command-1")
                try expect(usedText == "beta" && state.query == "beta", "focused shortcut used the wrong row or altered the query")
            }
        }

        try check("shortcut labels reflect the first nine currently displayed rows") {
            try withState { state, history in
                for number in 4...10 { history.add(record("row \(number)", time: TimeInterval(number))) }
                let expected: [(String, Int?)] = [("row 10", 1), ("row 9", 2), ("row 8", 3), ("row 7", 4), ("row 6", 5), ("row 5", 6), ("row 4", 7), ("gamma", 8), ("beta", 9), ("alpha", nil)]
                for (text, number) in expected {
                    let record = history.records.first { $0.text == text }!
                    try expect(state.shortcutNumber(for: record.id) == number, "wrong shortcut label for \(text)")
                }
                let alpha = history.records.first { $0.text == "alpha" }!
                history.togglePin(alpha.id)
                try expect(state.shortcutNumber(for: alpha.id) == 1, "shortcut label ignored pin ordering")
                let beta = history.records.first { $0.text == "beta" }!
                state.query = "beta"
                try expect(state.shortcutNumber(for: beta.id) == 1 && state.shortcutNumber(for: alpha.id) == nil, "shortcut labels ignored filtering")
                try expect(state.shortcutNumber(for: UUID()) == nil, "unknown row received a shortcut label")
            }
        }

        try check("preview selection never copies or pastes and ignores hidden records") {
            try withState { state, history in
                let alpha = history.records.first { $0.text == "alpha" }!
                let beta = history.records.first { $0.text == "beta" }!
                var uses = 0
                var copies = 0
                state.onUse = { _, _ in uses += 1 }
                state.onCopy = { _ in copies += 1 }
                state.selectForPreview(alpha)
                try expect(state.selectedID == alpha.id, "preview action did not select the requested visible record")
                state.query = "beta"
                state.selectForPreview(alpha)
                try expect(state.selectedID == beta.id, "preview action selected a hidden record")
                state.selectForPreview(record("not in history", time: 100))
                try expect(state.selectedID == beta.id && uses == 0 && copies == 0, "preview action pasted, copied, or selected unknown content")
            }
        }

        try check("pointer preview selection suppresses scrolling until keyboard navigation resumes") {
            try withState { state, history in
                let alpha = history.records.first { $0.text == "alpha" }!
                var pointerSelections: [Bool] = []
                let selectionSubscription = state.$selectedID.dropFirst().sink { _ in
                    pointerSelections.append(state.selectionFollowsPointer)
                }
                defer { selectionSubscription.cancel() }
                state.selectForPreview(alpha)
                try expect(state.selectedID == alpha.id && state.selectionFollowsPointer, "pointer preview requested navigation scrolling")
                try expect(pointerSelections == [true], "pointer origin was not set before publishing selection")
                try expect(state.handleKey(key(126)), "up arrow did not resume keyboard navigation")
                try expect(state.selectedRecord?.text == "beta" && !state.selectionFollowsPointer, "keyboard navigation retained pointer scroll suppression")
                try expect(pointerSelections == [true, false], "keyboard origin was not restored before publishing selection")
            }
        }

        try check("explicit actions and reconciled selection clear pointer origin") {
            try withState { state, history in
                let alpha = history.records.first { $0.text == "alpha" }!
                let beta = history.records.first { $0.text == "beta" }!
                state.selectForPreview(alpha)
                state.prepareToShow()
                try expect(!state.selectionFollowsPointer, "reopening retained pointer origin")
                state.selectForPreview(alpha)
                state.use(beta)
                try expect(!state.selectionFollowsPointer, "paste retained pointer origin")
                state.selectForPreview(alpha)
                state.copy(beta)
                try expect(!state.selectionFollowsPointer, "copy retained pointer origin")
                state.selectForPreview(alpha)
                state.query = "alpha"
                try expect(state.selectionFollowsPointer, "unchanged selection unnecessarily changed its pointer origin")
                state.query = "beta"
                try expect(state.selectedID == beta.id && !state.selectionFollowsPointer, "search reconciliation retained pointer origin")
                state.selectForPreview(alpha)
                try expect(!state.selectionFollowsPointer, "hidden preview record changed selection origin")
                state.query = ""
                state.selectForPreview(beta)
                state.remove(beta)
                try expect(!state.selectionFollowsPointer, "removal retained pointer origin")
            }
        }

        try check("reopening preserves preview choice and requests fresh search focus") {
            try withState { state, history in
                state.query = "alpha"
                state.showPreview = true
                state.statusMessage = "temporary message"
                let token = state.searchFocusToken
                state.prepareToShow()
                try expect(state.query.isEmpty && state.showPreview && state.statusMessage.isEmpty, "reopening reset preview or retained stale transient state")
                try expect(state.selectedID == history.records.first?.id, "reopening did not select the first record")
                try expect(token != state.searchFocusToken, "retained view did not receive a fresh focus request")
                state.showPreview = false
                state.prepareToShow()
                try expect(!state.showPreview, "reopening discarded the closed-preview choice")
            }
        }

        try check("arrows navigate displayed records and stop at list boundaries") {
            try withState { state, _ in
                try expect(state.selectedRecord?.text == "gamma", "fixture order is incorrect")
                try expect(state.handleKey(key(125)), "down arrow was not handled")
                try expect(state.selectedRecord?.text == "beta", "down arrow skipped the next record")
                _ = state.handleKey(key(125))
                _ = state.handleKey(key(125))
                try expect(state.selectedRecord?.text == "alpha", "down arrow wrapped beyond the last record")
                _ = state.handleKey(key(126))
                try expect(state.selectedRecord?.text == "beta", "up arrow did not select the previous record")
                _ = state.handleKey(key(126))
                _ = state.handleKey(key(126))
                try expect(state.selectedRecord?.text == "gamma", "up arrow wrapped before the first record")
            }
        }

        try check("query changes reconcile selection and empty results disable navigation") {
            try withState { state, _ in
                state.query = "alpha"
                try expect(state.selectedRecord?.text == "alpha", "query retained a hidden selection")
                state.showPreview = true
                state.query = "synthetic phrase that does not match"
                try expect(state.visibleRecords.isEmpty && state.selectedID == nil && state.showPreview, "empty results retained selection or reset preview choice")
                try expect(!state.handleKey(key(125)) && !state.handleKey(key(36)), "empty search swallowed navigation or Return")
                state.query = "   "
                try expect(state.visibleRecords.count == 3 && state.selectedRecord?.text == "gamma", "clearing query did not restore a valid selection")
                try expect(state.showPreview, "preview did not remain available after clearing search")
                state.showPreview = false
                state.query = "no matching record"
                state.query = ""
                try expect(!state.showPreview, "query changes reopened a deliberately closed preview")
            }
        }

        try check("ordinary text editing and unrelated modifier combinations pass through") {
            try withState { state, _ in
                let original = state.selectedID
                let untouched = [
                    key(0, characters: "a"), key(51), key(123), key(124),
                    key(0, characters: "a", modifiers: .command),
                    key(3, characters: "f"), key(3, characters: "f", modifiers: [.command, .shift]),
                    key(3, characters: "f", modifiers: [.command, .function]),
                    key(123, modifiers: .option), key(126, modifiers: .shift),
                    key(36, modifiers: .control), key(16, modifiers: [.command, .shift]),
                    key(18, characters: "1"), key(29, characters: "0", modifiers: .command),
                    key(18, characters: "1", modifiers: [.command, .shift]),
                    key(18, characters: "1", modifiers: [.command, .option]),
                    key(18, characters: "1", modifiers: [.command, .control]),
                    key(18, characters: "1", modifiers: [.command, .function]),
                    key(125, type: .keyUp)
                ]
                for event in untouched {
                    try expect(!state.handleKey(event), "panel consumed ordinary editing key \(event.keyCode) with \(event.modifierFlags.rawValue)")
                }
                try expect(state.selectedID == original, "unrelated editing changed selection")
            }
        }

        try check("Return pastes while explicit copy and plain-text actions stay distinct") {
            try withState { state, _ in
                var uses: [(UUID, Bool)] = []
                var copies: [UUID] = []
                state.onUse = { uses.append(($0.id, $1)) }
                state.onCopy = { copies.append($0.id) }
                let selected = state.selectedRecord!
                try expect(state.handleKey(key(36)), "Return was not handled")
                try expect(uses.count == 1 && uses[0].0 == selected.id && !uses[0].1 && copies.isEmpty, "Return did not use the normal paste callback")
                state.copy(selected)
                try expect(copies == [selected.id] && uses.count == 1, "copy triggered a paste callback")
                state.use(selected, plainText: true)
                try expect(uses.count == 2 && uses[1].1, "plain-text request lost its mode")
                try expect(state.handleKey(key(76)), "keypad Enter was not handled")
                try expect(uses.count == 3 && !uses[2].1, "keypad Enter used the wrong mode")
                state.onUse = nil
                try expect(!state.handleKey(key(36)), "Return was consumed without an action callback")
            }
        }

        try check("Escape closes preview before closing the panel") {
            try withState { state, _ in
                var closes = 0
                state.onClose = { closes += 1 }
                try expect(state.handleKey(key(16, modifiers: .command)) && !state.showPreview, "Command-Y did not close preview")
                try expect(state.handleKey(key(16, modifiers: .command)) && state.showPreview, "Command-Y did not reopen preview")
                try expect(state.handleKey(key(53)) && !state.showPreview && closes == 0, "first Escape closed the panel instead of preview")
                try expect(state.handleKey(key(53)) && closes == 1, "second Escape did not close the panel")
                state.onClose = nil
                try expect(!state.handleKey(key(53)), "Escape was consumed without an available close action")
            }
        }

        try check("Option-P pins the selected record and Option-Delete keeps a valid neighbor") {
            try withState { state, history in
                _ = state.handleKey(key(125))
                let selected = state.selectedRecord!
                try expect(state.handleKey(key(35, modifiers: [.option, .capsLock])), "pin shortcut was not handled")
                try expect(history.records.first?.id == selected.id && history.records.first?.pinned == true, "pin shortcut changed the wrong record")
                try expect(state.selectedID == selected.id, "pin reordering lost the selection")
                try expect(state.handleKey(key(51, modifiers: .option)), "delete shortcut was not handled")
                try expect(!history.records.contains { $0.id == selected.id }, "delete shortcut left its record behind")
                try expect(state.selectedRecord?.text == "gamma", "deletion did not select a remaining neighbor")
            }
        }

        try check("empty history preserves preview choice and preview can still toggle") {
            try withState { state, history in
                let original = state.selectedID!
                history.remove(original)
                waitForPublishedChange { state.selectedRecord?.text == "beta" }
                try expect(state.selectedRecord?.text == "beta", "external removal retained a stale selected ID")
                state.showPreview = true
                history.clearUnpinned()
                waitForPublishedChange { state.selectedID == nil }
                try expect(state.selectedID == nil && state.showPreview, "empty history retained selection or reset preview choice")
                try expect(state.handleKey(key(16, modifiers: .command)) && !state.showPreview, "Command-Y could not close empty preview")
                try expect(state.handleKey(key(16, modifiers: .command)) && state.showPreview, "Command-Y could not reopen empty preview")
                let added = record("fresh synthetic record", time: 4)
                history.add(added)
                waitForPublishedChange { state.selectedID == added.id }
                try expect(state.selectedID == added.id && state.showPreview, "new content did not restore preview selection")
                state.remove(added)
                try expect(state.selectedID == nil && state.showPreview, "removing the last record reset preview choice")
            }
        }

        try check("active input-method composition retains navigation and command shortcuts") {
            try withState { state, _ in
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 160, height: 60), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 160, height: 60))
                window.contentView = editor
                defer { window.close() }
                try expect(window.makeFirstResponder(editor), "could not install the synthetic input-method editor")
                editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                try expect(editor.hasMarkedText(), "synthetic editor did not start composition")
                let original = state.selectedID
                var uses = 0
                state.onUse = { _, _ in uses += 1 }
                let previewChoice = state.showPreview
                let focusToken = state.searchFocusToken
                for event in [key(125, window: window), key(126, window: window), key(36, window: window), key(53, window: window), key(18, characters: "1", modifiers: .command, window: window), key(16, modifiers: .command, window: window), key(3, characters: "f", modifiers: .command, window: window)] {
                    try expect(event.window === window, "synthetic event did not resolve its editor window")
                    try expect(!state.handleKey(event), "panel consumed an input-method composition key \(event.keyCode)")
                }
                try expect(state.selectedID == original && uses == 0 && state.showPreview == previewChoice && state.searchFocusToken == focusToken, "composition changed panel state, search focus, or pasted content")
                editor.unmarkText()
                try expect(state.handleKey(key(36, window: window)) && uses == 1, "Return did not resume pasting after composition finished")
                try expect(state.handleKey(key(18, characters: "1", modifiers: .command, window: window)) && uses == 2, "Command-1 did not resume pasting after composition finished")
            }
        }
    }
}
