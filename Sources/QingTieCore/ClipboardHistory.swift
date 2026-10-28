import Combine
import Foundation

public enum ClipboardHistoryError: LocalizedError {
    case unreadableStore
    case storeTooLarge
    case storageWriteFailed

    public var errorDescription: String? {
        switch self {
        case .unreadableStore: return "历史文件无法读取，已保留原文件并停止写入。"
        case .storeTooLarge: return "历史文件超过 256 MB，无法安全读取或保存。"
        case .storageWriteFailed: return "无法创建历史文件，原有记录已保留。"
        }
    }
}

@MainActor
public final class ClipboardHistory: ObservableObject {
    @Published public private(set) var records: [ClipboardRecord] = []
    @Published public private(set) var errorMessage: String?

    private let fileURL: URL
    private var limit: Int
    private var loadFailed = false
    private static let maximumStoreBytes = 256 * 1_024 * 1_024

    public init(fileURL: URL, limit: Int = 200) {
        self.fileURL = fileURL
        self.limit = max(0, limit)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes[.size] as? NSNumber, size.int64Value > Self.maximumStoreBytes {
                throw ClipboardHistoryError.storeTooLarge
            }
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let loaded = try JSONDecoder().decode([ClipboardRecord].self, from: data)
            for record in loaded { try ClipboardCodec.validate(record) }
            records = normalized(loaded, limit: self.limit)
        } catch {
            loadFailed = true
            errorMessage = "\(ClipboardHistoryError.unreadableStore.localizedDescription) \(error.localizedDescription)"
        }
    }

    public func add(_ record: ClipboardRecord) {
        do {
            try ensureWritable()
            try ClipboardCodec.validate(record)
            var next = records
            if let index = next.firstIndex(where: { Self.samePayload($0, record) }) {
                next[index].lastUsedAt = record.lastUsedAt
                next[index].sourceName = record.sourceName
                next[index].sourceBundleIdentifier = record.sourceBundleIdentifier
                next[index].pinned = next[index].pinned || record.pinned
            } else {
                var newRecord = record
                if next.contains(where: { $0.id == newRecord.id }) { newRecord.id = UUID() }
                next.insert(newRecord, at: 0)
            }
            try commit(normalized(next, limit: limit))
        } catch { errorMessage = error.localizedDescription }
    }

    public func togglePin(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        var next = records
        next[index].pinned.toggle()
        update(normalized(next, limit: limit))
    }

    public func remove(_ id: UUID) {
        update(records.filter { $0.id != id })
    }

    public func clearUnpinned() {
        update(records.filter(\.pinned))
    }

    public func setLimit(_ limit: Int) {
        let newLimit = max(0, limit)
        do {
            try commit(normalized(records, limit: newLimit))
            self.limit = newLimit
        } catch { errorMessage = error.localizedDescription }
    }

    public func filtered(query: String) -> [ClipboardRecord] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return records }
        return records.filter { record in
            let searchText = [record.text ?? "", record.title, record.sourceName, record.sourceBundleIdentifier ?? "", record.fileURLs.map(\.path).joined(separator: "\n")].joined(separator: "\n")
            return terms.allSatisfy { searchText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private func update(_ next: [ClipboardRecord]) {
        do { try commit(next) } catch { errorMessage = error.localizedDescription }
    }

    private func commit(_ next: [ClipboardRecord]) throws {
        try ensureWritable()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        guard data.count <= Self.maximumStoreBytes else { throw ClipboardHistoryError.storeTooLarge }
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporaryURL = directory.appendingPathComponent(".qingtie-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporaryURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ClipboardHistoryError.storageWriteFailed
        }
        defer { try? manager.removeItem(at: temporaryURL) }
        let handle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        if manager.fileExists(atPath: fileURL.path) {
            _ = try manager.replaceItemAt(fileURL, withItemAt: temporaryURL, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: temporaryURL, to: fileURL)
        }
        records = next
        errorMessage = nil
    }

    private func ensureWritable() throws {
        guard !loadFailed else { throw ClipboardHistoryError.unreadableStore }
    }

    private func normalized(_ input: [ClipboardRecord], limit: Int) -> [ClipboardRecord] {
        var unique: [ClipboardRecord] = []
        for var record in input {
            if let index = unique.firstIndex(where: { Self.samePayload($0, record) }) {
                unique[index].pinned = unique[index].pinned || record.pinned
                if record.lastUsedAt > unique[index].lastUsedAt {
                    unique[index].lastUsedAt = record.lastUsedAt
                    unique[index].sourceName = record.sourceName
                    unique[index].sourceBundleIdentifier = record.sourceBundleIdentifier
                }
            } else {
                if unique.contains(where: { $0.id == record.id }) { record.id = UUID() }
                unique.append(record)
            }
        }
        let ordered = unique.enumerated().sorted { lhs, rhs in
            if lhs.element.pinned != rhs.element.pinned { return lhs.element.pinned }
            if lhs.element.lastUsedAt != rhs.element.lastUsedAt { return lhs.element.lastUsedAt > rhs.element.lastUsedAt }
            if lhs.element.createdAt != rhs.element.createdAt { return lhs.element.createdAt > rhs.element.createdAt }
            return lhs.offset < rhs.offset
        }.map(\.element)
        var unpinned = 0
        return ordered.filter { record in
            if record.pinned { return true }
            unpinned += 1
            return unpinned <= limit
        }
    }

    private static func samePayload(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
        guard lhs.items.count == rhs.items.count else { return false }
        return zip(lhs.items, rhs.items).allSatisfy { left, right in
            guard left.count == right.count else { return false }
            return left.sorted { $0.type < $1.type } == right.sorted { $0.type < $1.type }
        }
    }
}
