import AppKit
import Quartz
import SwiftUI

@MainActor
struct FilePreviewView: View {
    let urls: [URL]

    var body: some View {
        FilePreviewSelection(urls: urls)
            .id(urls)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

@MainActor
private struct FilePreviewSelection: View {
    let urls: [URL]
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 8) {
            if urls.count > 1 {
                Picker("预览文件", selection: $selectedIndex) {
                    ForEach(urls.indices, id: \.self) { index in
                        Text(urls[index].lastPathComponent)
                            .tag(index)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("预览文件")
            }

            if let url = selectedURL {
                if let message = unavailableMessage(for: url) {
                    unavailablePreview(message)
                } else {
                    NativeFilePreview(url: url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("文件预览：\(url.lastPathComponent)")
                }
            } else {
                unavailablePreview("没有可预览的文件。")
            }
        }
    }

    private var selectedURL: URL? {
        guard urls.indices.contains(selectedIndex) else { return nil }
        return urls[selectedIndex]
    }

    private func unavailableMessage(for url: URL) -> String? {
        guard url.isFileURL else { return "仅支持预览本地文件。" }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "文件已移动或删除，无法预览。"
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return "无法读取此文件，请检查访问权限。"
        }
        return nil
    }

    private func unavailablePreview(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 28, weight: .light))
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(QingTieTheme.secondary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct NativeFilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> FileQuickLookView {
        let view = FileQuickLookView(frame: .zero, style: .compact)!
        view.autostarts = false
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: FileQuickLookView, context: Context) {
        guard view.displayedURL != url else { return }
        view.displayedURL = url
        view.autostarts = false
        view.previewItem = url as NSURL
    }

    static func dismantleNSView(_ view: FileQuickLookView, coordinator: ()) {
        view.previewItem = nil
        view.displayedURL = nil
        view.close()
    }
}

@MainActor
private final class FileQuickLookView: QLPreviewView {
    var displayedURL: URL?

    // Keep search typing in its current responder. Quick Look's child playback
    // controls can still receive mouse clicks and manage their own focus.
    override var acceptsFirstResponder: Bool { false }
}
