import AppKit
import QingTieCore
import SwiftUI

@MainActor
struct ClipboardPanelView: View {
    @ObservedObject var state: ClipboardPanelState
    @ObservedObject private var history: ClipboardHistory
    @FocusState private var searchIsFocused: Bool
    @State private var confirmingClear = false

    static let listWidth = ClipboardPanelLayout.listWidth
    static let previewWidth = ClipboardPanelLayout.previewWidth
    static let panelHeight = ClipboardPanelLayout.height

    private var effectiveListWidth: CGFloat {
        state.showPreview ? (state.panelSize.width - 1) * Self.listWidth / (Self.listWidth + Self.previewWidth)
                          : state.panelSize.width
    }

    init(state: ClipboardPanelState) {
        self.state = state
        _history = ObservedObject(wrappedValue: state.history)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Hairline()
            HStack(spacing: 0) {
                listColumn.frame(width: effectiveListWidth)
                if state.showPreview {
                    Hairline(vertical: true)
                    ClipboardPreview(record: state.selectedRecord,
                                     togglePin: { if let record = state.selectedRecord { history.togglePin(record.id) } },
                                     onClose: { state.showPreview = false },
                                     recordMenu: { record in AnyView(rowMenu(record)) })
                        .frame(width: max(0, state.panelSize.width - effectiveListWidth - 1))
                }
            }
            Hairline()
            footer
        }
        .frame(width: state.panelSize.width, height: state.panelSize.height)
        .foregroundStyle(QingTieTheme.ink)
        .background(QingTieTheme.canvas)
        .tint(QingTieTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(QingTieTheme.line, lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .onAppear { focusSearch() }
        .onChange(of: state.searchFocusToken) { _, _ in focusSearch() }
        .confirmationDialog("清除全部未置顶记录？", isPresented: $confirmingClear) {
            Button("清除记录", role: .destructive) { history.clearUnpinned() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("置顶记录和当前系统剪贴板内容会保留。")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 9) {
            Image(nsImage: Bundle.main.image(forResource: "QingTieMark") ?? NSImage())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text("QingTie").font(.system(size: 16, weight: .semibold))
            Spacer()
            Button { state.showPreview.toggle() } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 15, weight: .regular))
            }
            .buttonStyle(QuietButtonStyle(active: state.showPreview))
            .help("显示或收起右侧预览 · ⌘Y")
            .accessibilityLabel(state.showPreview ? "收起预览" : "打开预览")
            Menu {
                Button("设置…", systemImage: "gearshape") { state.onSettings?() }
                Button("自动粘贴权限…", systemImage: "keyboard") { state.onPermission?() }
                Divider()
                Button("清除未置顶记录…", systemImage: "trash") { confirmingClear = true }
                    .disabled(!history.records.contains { !$0.pinned })
                Divider()
                Button("关于 QingTie", systemImage: "info.circle") { state.onAbout?() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(QingTieTheme.secondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("设置与更多")
            .accessibilityLabel("设置与更多")
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(.ultraThinMaterial)
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            searchField.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 4) {
                ForEach(ClipboardContentFilter.allCases, id: \.self) { filter in
                    Button { state.contentFilter = filter } label: {
                        HStack(spacing: 7) {
                            Image(systemName: filter.systemImage).font(.system(size: 13))
                            Text(filter.title).font(.system(size: 12, weight: state.contentFilter == filter ? .medium : .regular))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButtonStyle(active: state.contentFilter == filter))
                    .accessibilityLabel("筛选\(filter.title)")
                    .accessibilityAddTraits(state.contentFilter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if let error = history.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .help(error)
            }
            recordList
        }
        .background(QingTieTheme.sidebar.opacity(0.6))
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(QingTieTheme.secondary)
            TextField("搜索剪贴板", text: $state.query)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .accessibilityLabel("搜索剪贴板")
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                    focusSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(QingTieTheme.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            } else {
                Text("⌘F")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(QingTieTheme.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(QingTieTheme.hover, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(QingTieTheme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(searchIsFocused ? QingTieTheme.accent.opacity(0.28) : QingTieTheme.line, lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var recordList: some View {
        if state.visibleRecords.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: state.query.isEmpty ? state.contentFilter.systemImage : "magnifyingglass")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(QingTieTheme.accent.opacity(0.7))
                    .padding(.bottom, 4)
                Text(state.query.isEmpty ? "这里还没有内容" : "没有找到相关内容")
                    .font(.system(size: 13, weight: .medium))
                Text(state.query.isEmpty ? "复制过的内容，会替你留在这里。" : "试试其他关键词或内容分类。")
                    .font(.system(size: 11))
                    .foregroundStyle(QingTieTheme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        if !state.pinnedRecords.isEmpty {
                            sectionHeading("置顶", count: state.pinnedRecords.count)
                            rows(state.pinnedRecords)
                        }
                        if !state.recentRecords.isEmpty {
                            sectionHeading(state.query.isEmpty ? "最近复制" : "搜索结果", count: state.recentRecords.count)
                                .padding(.top, state.pinnedRecords.isEmpty ? 0 : 5)
                            rows(state.recentRecords)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .onChange(of: state.selectedID) { _, id in
                    if let id, !state.selectionFollowsPointer { proxy.scrollTo(id) }
                }
                .accessibilityLabel("剪贴板历史")
            }
        }
    }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(title)
            Text("\(count)").monospacedDigit()
            Spacer()
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(QingTieTheme.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private func rows(_ records: [ClipboardRecord]) -> some View {
        ForEach(records) { record in
            ClipboardRow(record: record, selected: record.id == state.selectedID,
                         shortcutNumber: state.shortcutNumber(for: record.id),
                         onPreview: { state.selectForPreview(record) },
                         onPin: { history.togglePin(record.id) },
                         action: { state.use(record) },
                         recordMenu: { AnyView(rowMenu(record)) })
                .id(record.id)
                .contextMenu { rowMenu(record) }
        }
    }

    @ViewBuilder
    private func rowMenu(_ record: ClipboardRecord) -> some View {
        Button(record.pinned ? "取消置顶" : "置顶", systemImage: record.pinned ? "pin.slash" : "pin") {
            history.togglePin(record.id)
        }
        Button("复制", systemImage: "doc.on.doc") { state.copy(record) }
        Button("粘贴为纯文本", systemImage: "textformat") { state.use(record, plainText: true) }
            .disabled(record.text == nil)
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { state.remove(record) }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            if state.statusMessage.hasPrefix("已复制") {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(QingTieTheme.accent)
            }
            Text(state.statusMessage.isEmpty ? "↑↓ 选择   ↵ 使用" : state.statusMessage)
                .lineLimit(1)
                .help(state.statusMessage)
            Spacer(minLength: 8)
            Text("⌘1–9 快速使用")
                .font(.system(size: 10))
                .help("⌘F 搜索 · ⌘Y 预览 · ⌥P 置顶 · ⌥⌫ 删除")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(QingTieTheme.secondary)
        .padding(.horizontal, 20)
        .frame(height: 34)
        .background(.ultraThinMaterial)
    }

    private func focusSearch() {
        searchIsFocused = false
        DispatchQueue.main.async { searchIsFocused = true }
    }
}

@MainActor
private struct ClipboardRow: View {
    let record: ClipboardRecord
    let selected: Bool
    let shortcutNumber: Int?
    let onPreview: () -> Void
    let onPin: () -> Void
    let action: () -> Void
    let recordMenu: () -> AnyView
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayTitle: String {
        guard record.fileURLs.isEmpty, record.imageData == nil,
              let firstLine = record.text?.split(whereSeparator: \.isNewline)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return record.title }
        return String(firstLine).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 11) {
                    thumbnail.frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle.isEmpty ? "剪贴板内容" : displayTitle)
                            .font(.system(size: 13, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? QingTieTheme.selectionInk : QingTieTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 5) {
                            Text(record.sourceName.isEmpty ? "未知应用" : record.sourceName).lineLimit(1)
                            Text("·").accessibilityHidden(true)
                            Text(record.createdAt, format: .dateTime.hour().minute()).monospacedDigit()
                            if record.fileURLs.count > 1 { Text("\(record.fileURLs.count) 个文件") }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(QingTieTheme.secondary)
                    }
                    Spacer(minLength: 2)
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(ClipboardRowButtonStyle())
            .accessibilityLabel("\(record.title)、\(record.sourceName)、\(record.createdAt.formatted(date: .omitted, time: .shortened))\(shortcutNumber.map { "、Command \($0) 快速使用" } ?? "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
            HStack(spacing: 0) {
                Button(action: onPin) {
                    Image(systemName: record.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(QuietButtonStyle(active: record.pinned))
                .help(record.pinned ? "取消置顶" : "置顶")
                .accessibilityLabel(record.pinned ? "取消置顶" : "置顶")
                Menu { recordMenu() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundStyle(QingTieTheme.secondary)
                        .frame(width: 24, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("记录操作")
                .accessibilityLabel("记录操作")
            }
            .opacity(hovered || selected ? 1 : 0)
            .allowsHitTesting(hovered || selected)
            .accessibilityHidden(!hovered && !selected)
            Group {
                if let shortcutNumber {
                    Text("⌘\(shortcutNumber)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(selected ? QingTieTheme.selectionInk.opacity(0.7) : QingTieTheme.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 4)
                        .background(QingTieTheme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                } else { Color.clear.frame(width: 26, height: 20) }
            }
            .frame(width: 33)
            .padding(.trailing, 9)
            .accessibilityHidden(true)
        }
        .background(selected ? QingTieTheme.selection : hovered ? QingTieTheme.hover : record.pinned ? QingTieTheme.surface.opacity(0.65) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? QingTieTheme.selectionBorder : .clear, lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2).fill(QingTieTheme.accent.opacity(0.8))
                    .frame(width: 2, height: 32).padding(.leading, 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !hovered { hovered = true }
                if let event = NSApp.currentEvent,
                   [.mouseMoved, .mouseEntered, .leftMouseDragged].contains(event.type) { onPreview() }
            case .ended: hovered = false
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = record.imageData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottomTrailing) {
                    SourceApplicationIconView(bundleIdentifier: record.sourceBundleIdentifier, name: record.sourceName, size: 12)
                        .padding(1).background(QingTieTheme.surface, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 3, y: 3)
                }
                .accessibilityHidden(true)
        } else {
            SourceApplicationIconView(bundleIdentifier: record.sourceBundleIdentifier, name: record.sourceName, size: 34)
                .accessibilityHidden(true)
        }
    }
}

private struct ClipboardRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? QingTieTheme.selectionBorder.opacity(0.45) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.08 : 0.18), value: configuration.isPressed)
    }
}

@MainActor
private struct ClipboardPreview: View {
    let record: ClipboardRecord?
    let togglePin: () -> Void
    let onClose: () -> Void
    let recordMenu: (ClipboardRecord) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: typeSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(QingTieTheme.typeAccent)
                    .frame(width: 26, height: 26)
                    .background(QingTieTheme.typeBackground, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                Text(typeTitle).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(QingTieTheme.secondary)
                Spacer()
                if let record {
                    Button(action: togglePin) {
                        Image(systemName: record.pinned ? "pin.fill" : "pin").font(.system(size: 12))
                    }
                    .buttonStyle(QuietButtonStyle(active: record.pinned))
                    .help(record.pinned ? "取消置顶" : "置顶")
                    .accessibilityLabel(record.pinned ? "取消置顶预览记录" : "置顶预览记录")
                    Menu { recordMenu(record) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14))
                            .foregroundStyle(QingTieTheme.secondary)
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("预览记录操作")
                } else {
                    Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(QuietButtonStyle()).help("收起预览 · ⌘Y")
                        .accessibilityLabel("收起预览")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
            Hairline().padding(.horizontal, 20)
            if let record {
                previewBody(record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(22)
                Hairline().padding(.horizontal, 20)
                HStack(spacing: 7) {
                    SourceApplicationIconView(bundleIdentifier: record.sourceBundleIdentifier, name: record.sourceName, size: 16)
                        .accessibilityHidden(true)
                    Text(record.sourceName.isEmpty ? "未知应用" : record.sourceName).lineLimit(1)
                    Spacer()
                    Text(record.createdAt, format: .dateTime.hour().minute()).monospacedDigit()
                }
                .font(.system(size: 10.5))
                .foregroundStyle(QingTieTheme.secondary)
                .padding(.horizontal, 20)
                .frame(height: 40)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.system(size: 26, weight: .light))
                    Text("选择记录以预览内容").font(.system(size: 12))
                }
                .foregroundStyle(QingTieTheme.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(QingTieTheme.surface)
    }

    private var typeTitle: String {
        guard let record else { return "内容预览" }
        if !record.fileURLs.isEmpty { return "文件预览" }
        if record.imageData != nil { return "图片预览" }
        return "文本预览"
    }

    private var typeSymbol: String {
        guard let record else { return "doc.text" }
        if !record.fileURLs.isEmpty { return "doc" }
        if record.imageData != nil { return "photo" }
        return "doc.text"
    }

    @ViewBuilder
    private func previewBody(_ record: ClipboardRecord) -> some View {
        if !record.fileURLs.isEmpty {
            FilePreviewView(urls: record.fileURLs)
        } else if let data = record.imageData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("图片内容预览")
        } else {
            ScrollView {
                Text(record.text ?? "此内容暂不支持预览。")
                    .font(.system(size: 14))
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}
