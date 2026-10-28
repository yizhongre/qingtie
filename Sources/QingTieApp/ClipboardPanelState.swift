import AppKit
import Combine
import QingTieCore
import SwiftUI

enum ClipboardPanelLayout {
    static let listWidth: CGFloat = 460
    static let previewWidth: CGFloat = 400
    static let height: CGFloat = 600

    static func size(showPreview: Bool, visibleSize: NSSize?) -> NSSize {
        let desired = NSSize(width: listWidth + (showPreview ? previewWidth + 1 : 0), height: height)
        guard let visibleSize else { return desired }
        return NSSize(width: min(desired.width, max(1, visibleSize.width - 24)),
                      height: min(desired.height, max(1, visibleSize.height - 24)))
    }
}

enum ClipboardContentFilter: String, CaseIterable {
    case all
    case text
    case image
    case link

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .link: return "链接"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        }
    }
}

@MainActor
final class ClipboardPanelState: ObservableObject {
    let history: ClipboardHistory

    @Published var query = "" {
        didSet { ensureSelection() }
    }
    @Published var contentFilter: ClipboardContentFilter = .all {
        didSet { ensureSelection() }
    }
    @Published var selectedID: UUID?
    @Published private(set) var selectionFollowsPointer = false
    @Published var showPreview: Bool
    @Published var panelSize: NSSize
    @Published var statusMessage = ""
    @Published private(set) var searchFocusToken = UUID()

    var onUse: ((ClipboardRecord, Bool) -> Void)?
    var onCopy: ((ClipboardRecord) -> Void)?
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onPermission: (() -> Void)?

    private var historySubscription: AnyCancellable?

    init(history: ClipboardHistory, showPreview: Bool = true) {
        self.history = history
        self.showPreview = showPreview
        self.panelSize = ClipboardPanelLayout.size(showPreview: showPreview, visibleSize: nil)
        historySubscription = history.$records
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.ensureSelection() }
    }

    var visibleRecords: [ClipboardRecord] {
        history.filtered(query: query).filter(matchesContentFilter)
    }

    var pinnedRecords: [ClipboardRecord] { visibleRecords.filter(\.pinned) }

    var recentRecords: [ClipboardRecord] { visibleRecords.filter { !$0.pinned } }

    var selectedRecord: ClipboardRecord? {
        visibleRecords.first { $0.id == selectedID }
    }

    func prepareToShow() {
        selectionFollowsPointer = false
        contentFilter = .all
        query = ""
        selectedID = visibleRecords.first?.id
        statusMessage = ""
        focusSearch()
    }

    func focusSearch() {
        searchFocusToken = UUID()
    }

    /// Returns true only for panel navigation and the panel's explicit shortcuts.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // Let the input method finish its own navigation and composition first.
        if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }

        let shortcutModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
        if shortcutModifiers == .command, event.keyCode == 3 { // Command-F
            focusSearch()
            return true
        }

        if shortcutModifiers == .command, let number = shortcutNumber(for: event) {
            let records = visibleRecords
            guard number <= records.count, onUse != nil else { return false }
            use(records[number - 1])
            return true
        }

        if modifiers == .command, event.keyCode == 16 { // Command-Y
            showPreview.toggle()
            return true
        }

        if modifiers == .option, event.keyCode == 35 { // Option-P
            guard let selectedRecord else { return false }
            history.togglePin(selectedRecord.id)
            return true
        }

        if modifiers == .option, event.keyCode == 51 { // Option-Delete
            guard let selectedRecord else { return false }
            remove(selectedRecord)
            return true
        }

        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 125: // Down
            return moveSelection(by: 1)
        case 126: // Up
            return moveSelection(by: -1)
        case 36, 76: // Return and keypad Enter
            guard let selectedRecord, onUse != nil else { return false }
            use(selectedRecord)
            return true
        case 53: // Escape
            if showPreview {
                showPreview = false
            } else {
                guard let onClose else { return false }
                onClose()
            }
            return true
        default:
            return false
        }
    }

    func shortcutNumber(for id: UUID) -> Int? {
        guard let index = visibleRecords.prefix(9).firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    func selectForPreview(_ record: ClipboardRecord) {
        guard visibleRecords.contains(where: { $0.id == record.id }) else { return }
        selectionFollowsPointer = true
        selectedID = record.id
    }

    func use(_ record: ClipboardRecord, plainText: Bool = false) {
        selectionFollowsPointer = false
        selectedID = record.id
        onUse?(record, plainText)
    }

    func copy(_ record: ClipboardRecord) {
        selectionFollowsPointer = false
        selectedID = record.id
        onCopy?(record)
    }

    func remove(_ record: ClipboardRecord) {
        selectionFollowsPointer = false
        let records = visibleRecords
        let index = records.firstIndex { $0.id == record.id } ?? 0
        history.remove(record.id)
        let remaining = visibleRecords
        selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    private func moveSelection(by offset: Int) -> Bool {
        let records = visibleRecords
        guard !records.isEmpty else { return false }
        selectionFollowsPointer = false
        if let index = records.firstIndex(where: { $0.id == selectedID }) {
            selectedID = records[min(max(index + offset, 0), records.count - 1)].id
        } else {
            selectedID = offset < 0 ? records.last?.id : records.first?.id
        }
        return true
    }

    private func ensureSelection() {
        let records = visibleRecords
        if !records.contains(where: { $0.id == selectedID }) {
            selectionFollowsPointer = false
            selectedID = records.first?.id
        }
    }

    private func matchesContentFilter(_ record: ClipboardRecord) -> Bool {
        if contentFilter == .all { return true }
        guard record.fileURLs.isEmpty else { return false }
        if contentFilter == .image { return record.imageData != nil }
        guard record.imageData == nil, let text = record.text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = URLComponents(string: trimmed)
        let isLink = !trimmed.contains(where: \.isWhitespace)
            && ["http", "https"].contains(components?.scheme?.lowercased() ?? "")
            && !(components?.host?.isEmpty ?? true)
        return contentFilter == .link ? isLink : !isLink
    }

    private func shortcutNumber(for event: NSEvent) -> Int? {
        if let characters = event.charactersIgnoringModifiers,
           characters.utf8.count == 1,
           let digit = characters.utf8.first,
           (48...57).contains(digit) {
            return digit == 48 ? nil : Int(digit - 48)
        }

        switch event.keyCode {
        case 18, 83: return 1
        case 19, 84: return 2
        case 20, 85: return 3
        case 21, 86: return 4
        case 23, 87: return 5
        case 22, 88: return 6
        case 26, 89: return 7
        case 28, 91: return 8
        case 25, 92: return 9
        default: return nil
        }
    }
}
