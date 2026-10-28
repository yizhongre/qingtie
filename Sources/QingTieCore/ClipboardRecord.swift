import AppKit
import Foundation

/// One native representation of a single pasteboard item.
public struct ClipboardRepresentation: Codable, Equatable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// All native items belonging to one copy operation, along with local history metadata.
public struct ClipboardRecord: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var lastUsedAt: Date = Date()
    public var sourceName: String
    public var sourceBundleIdentifier: String?
    public var pinned: Bool = false
    public var items: [[ClipboardRepresentation]]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        sourceName: String,
        sourceBundleIdentifier: String? = nil,
        pinned: Bool = false,
        items: [[ClipboardRepresentation]]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.pinned = pinned
        self.items = items
    }

    public var text: String? {
        let strings = items.compactMap { item -> String? in
            for type in [NSPasteboard.PasteboardType.string.rawValue, "public.utf8-plain-text", "NSStringPboardType"] {
                if let representation = item.first(where: { $0.type == type }),
                   let text = String(data: representation.data, encoding: .utf8) {
                    return text
                }
            }
            for type in ["public.utf16-external-plain-text", "public.utf16-plain-text"] {
                if let representation = item.first(where: { $0.type == type }),
                   let text = String(data: representation.data, encoding: .utf16) {
                    return text
                }
            }
            if let representation = item.first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue }),
               let richText = NSAttributedString(rtf: representation.data, documentAttributes: nil) {
                return richText.string
            }
            return nil
        }
        return strings.isEmpty ? nil : strings.joined(separator: "\n")
    }

    public var title: String {
        if let text {
            let compact = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if !compact.isEmpty { return String(compact.prefix(120)) }
        }
        let files = fileURLs
        if let first = files.first {
            return files.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) 等 \(files.count) 个文件"
        }
        if imageData != nil { return "图片" }
        return "剪贴板内容"
    }

    public var imageData: Data? {
        let priorities = [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue, "public.jpeg", "public.heic", "public.heif", "org.webmproject.webp"]
        for type in priorities {
            for item in items {
                if let representation = item.first(where: { $0.type == type }) { return representation.data }
            }
        }
        return nil
    }

    public var fileURLs: [URL] {
        var result: [URL] = []
        for item in items {
            for representation in item {
                if representation.type == NSPasteboard.PasteboardType.fileURL.rawValue,
                   let text = String(data: representation.data, encoding: .utf8),
                   let url = URL(string: text), url.isFileURL {
                    if !result.contains(url) { result.append(url) }
                } else if representation.type == "NSFilenamesPboardType",
                          let paths = try? PropertyListSerialization.propertyList(from: representation.data, format: nil) as? [String] {
                    for path in paths {
                        let url = URL(fileURLWithPath: path)
                        if !result.contains(url) { result.append(url) }
                    }
                }
            }
        }
        return result
    }
}
