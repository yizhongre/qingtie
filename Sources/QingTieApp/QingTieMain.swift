import AppKit
import ApplicationServices
import Combine
import QingTieCore
import SwiftUI

@main
struct QingTieMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = ApplicationDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

private final class HistoryPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem!
  private var panel: HistoryPanel!
  private var settingsWindow: NSWindow?
  private let about = AboutWindow()
  private let preferences: AppPreferences
  private let history: ClipboardHistory
  private let state: ClipboardPanelState
  private let shortcut = GlobalShortcut()
  private var timer: Timer?
  private var subscriptions = Set<AnyCancellable>()
  private var keyMonitor: Any?
  private var outsideClickMonitor: Any?
  private var previousApplication: NSRunningApplication?
  private var watcher: ClipboardWatcher?
  private var activationObserver: NSObjectProtocol?
  private let pasteboard: NSPasteboard
  private let demo: Bool

  override init() {
    demo = CommandLine.arguments.contains("--demo")
    let defaults = demo ? UserDefaults(suiteName: "io.github.yizhongre.qingtie.demo.\(ProcessInfo.processInfo.processIdentifier)")! : .standard
    preferences = AppPreferences(defaults: defaults)
    let folder = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("QingTie-demo-\(UUID())")
      : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingTie")
    let historyURL = folder.appendingPathComponent("History-v2.json")
    history = ClipboardHistory(fileURL: historyURL, limit: preferences.historyLimit)
    state = ClipboardPanelState(history: history, showPreview: preferences.defaults.object(forKey: "previewPaneVisible") as? Bool ?? true)
    pasteboard = demo ? NSPasteboard(name: .init("io.github.yizhongre.qingtie.demo.\(UUID())")) : .general
    super.init()
    if demo { addDemoRecords() }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureApplicationMenu()
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menuImage = NSImage(named: "QingTieMenuTemplate")
      ?? NSImage(systemSymbolName: "clipboard", accessibilityDescription: "QingTie")
    menuImage?.isTemplate = true
    menuImage?.size = NSSize(width: 18, height: 18)
    menuImage?.accessibilityDescription = "QingTie"
    statusItem.button?.image = menuImage
    statusItem.button?.toolTip = "QingTie · 剪贴板历史"
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

    panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: ClipboardPanelView.listWidth,
                                           height: ClipboardPanelView.panelHeight),
                         styleMask: [.borderless], backing: .buffered, defer: false)
    panel.title = "QingTie"
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.delegate = self
    let hosting = NSHostingView(rootView: ClipboardPanelView(state: state))
    hosting.sizingOptions = []
    panel.contentView = hosting
    state.$showPreview.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] visible in
      guard let self else { return }
      self.preferences.defaults.set(visible, forKey: "previewPaneVisible")
      self.resizePanel(showPreview: visible)
    }.store(in: &subscriptions)

    state.onUse = { [weak self] record, plain in self?.use(record, plainText: plain, copyOnly: false) }
    state.onCopy = { [weak self] record in self?.use(record, plainText: false, copyOnly: true) }
    state.onClose = { [weak self] in
      self?.panel.orderOut(nil)
      self?.previousApplication?.activate(options: [])
    }
    state.onSettings = { [weak self] in self?.showSettings() }
    state.onAbout = { [weak self] in self?.panel.orderOut(nil); self?.about.show() }
    state.onPermission = { [weak self] in self?.openPermissionSettings() }
    shortcut.onPress = { [weak self] in self?.togglePanel() }
    preferences.$shortcut.removeDuplicates().sink { [weak self] choice in
      guard let self, !self.demo else { return }
      if !self.shortcut.register(choice: choice) { self.preferences.message = "该快捷键已被占用，请选择其他组合。" }
    }.store(in: &subscriptions)
    preferences.$historyLimit.removeDuplicates().sink { [weak self] value in self?.history.setLimit(value) }.store(in: &subscriptions)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.panel.isKeyWindow else { return event }
      return self.state.handleKey(event) ? nil : event
    }
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      guard let self, !self.demo else { return }
      self.panel.orderOut(nil)
    }
    if !demo {
      let active = NSWorkspace.shared.frontmostApplication
      watcher = ClipboardWatcher(pasteboard: pasteboard, sourceName: active?.localizedName ?? "未知应用",
        sourceBundleIdentifier: active?.bundleIdentifier,
        canRecord: { [weak self] in guard let self else { return false }; return !self.preferences.paused },
        isExcluded: { [weak self] in self?.preferences.excludes($0) ?? true },
        onCapture: { [weak self] in self?.history.add($0) })
      preferences.$paused.dropFirst().sink { [weak self] _ in self?.watcher?.markCurrentChangeHandled() }.store(in: &subscriptions)
      activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
          guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
          MainActor.assumeIsolated { self?.watcher?.sourceDidChange(name: app.localizedName ?? "未知应用", bundleIdentifier: app.bundleIdentifier) }
        }
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.watcher?.poll() }
      }
    }
    if CommandLine.arguments.contains("--show-about") { about.show() }
    else if demo || CommandLine.arguments.contains("--show-panel") || !preferences.defaults.bool(forKey: "hasOpenedPanel") {
      preferences.defaults.set(true, forKey: "hasOpenedPanel")
      showPanel()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    shortcut.stop()
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    if demo { pasteboard.releaseGlobally() }
  }

  func applicationDidResignActive(_ notification: Notification) {
    if !demo { panel?.orderOut(nil) }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showPanel()
    return true
  }

  private func configureApplicationMenu() {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "QingTie")
    for (title, action, key) in [("关于 QingTie", #selector(aboutFromMenu), ""),
                                 ("设置…", #selector(settingsFromMenu), ","),
                                 ("退出 QingTie", #selector(quitFromMenu), "q")] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = self
      applicationMenu.addItem(item)
    }
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)
    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "编辑")
    for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                ("复制", "copy:", "c"), ("粘贴", "paste:", "v"),
                                ("全选", "selectAll:", "a")] {
      editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
    }
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu
  }

  @objc private func statusClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      for (title, selector) in [("打开 QingTie", #selector(openFromMenu)), ("设置…", #selector(settingsFromMenu)),
                                ("关于 QingTie", #selector(aboutFromMenu)), ("退出 QingTie", #selector(quitFromMenu))] {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
      }
      if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button) }
    } else { togglePanel() }
  }

  @objc private func openFromMenu() { showPanel() }
  @objc private func settingsFromMenu() { showSettings() }
  @objc private func aboutFromMenu() { about.show() }
  @objc private func quitFromMenu() { NSApp.terminate(nil) }

  private func togglePanel() {
    if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
  }

  private func resizePanel(showPreview: Bool, screen: NSScreen? = nil) {
    let visible = (screen ?? panel.screen ?? NSScreen.main)?.visibleFrame
    let size = ClipboardPanelLayout.size(showPreview: showPreview, visibleSize: visible?.size)
    state.panelSize = size
    var frame = panel.frame
    frame.origin.y += frame.height - size.height
    frame.size = size
    if let visible {
      frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - size.width))
      frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
    }
    panel.setFrame(frame, display: true)
  }

  private func showPanel() {
    let frontmost = NSWorkspace.shared.frontmostApplication
    if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = frontmost }
    state.prepareToShow()
    state.statusMessage = preferences.paused ? "已暂停记录新内容" : AXIsProcessTrusted() && preferences.automaticPaste ? "回车或 ⌘1–⌘9 使用 · ⌘Y 预览" : "点击复制，回原应用按 ⌘V"
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    resizePanel(showPreview: state.showPreview, screen: screen)
    if let rect = screen?.visibleFrame {
      let size = panel.frame.size
      panel.setFrameOrigin(NSPoint(x: max(rect.minX, min(rect.maxX - size.width, rect.midX - size.width / 2)),
                                   y: max(rect.minY, rect.maxY - size.height - 80)))
    }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func use(_ record: ClipboardRecord, plainText: Bool, copyOnly: Bool) {
    do {
      try ClipboardCodec.write(record, to: pasteboard, plainText: plainText)
      watcher?.markCurrentChangeHandled()
      var usedRecord = record
      usedRecord.lastUsedAt = Date()
      history.add(usedRecord)
      panel.orderOut(nil)
      guard !demo, let destination = previousApplication, !destination.isTerminated else { return }
      destination.activate(options: [])
      guard !copyOnly, preferences.automaticPaste, AXIsProcessTrusted() else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
      }
    } catch { state.statusMessage = "复制失败：\(error.localizedDescription)" }
  }

  private func openPermissionSettings() {
    panel.orderOut(nil)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  private func showSettings() {
    panel.orderOut(nil)
    if settingsWindow == nil {
      let root = PreferencesView(preferences: preferences,
        openPermission: { [weak self] in self?.openPermissionSettings() },
        clearHistory: { [weak self] in self?.history.clearUnpinned() })
      let window = NSWindow(contentViewController: NSHostingController(rootView: root))
      window.title = "QingTie 设置"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  private func addDemoRecords() {
    func addText(_ value: String, source: String, bundle: String, minutesAgo: Double) {
      pasteboard.clearContents()
      pasteboard.setString(value, forType: .string)
      if var record = ClipboardCodec.capture(from: pasteboard, sourceName: source, sourceBundleIdentifier: bundle) {
        record.createdAt = Date(timeIntervalSinceNow: -minutesAgo * 60)
        record.lastUsedAt = record.createdAt
        history.add(record)
      }
    }
    addText("项目配色参考\n奶白、薄荷绿与一点珊瑚色。", source: "Safari", bundle: "com.apple.Safari", minutesAgo: 32)
    addText("新的想法，先留在这里。", source: "微信", bundle: "com.tencent.xinWeChat", minutesAgo: 24)
    addText("npm run dev", source: "终端", bundle: "com.apple.Terminal", minutesAgo: 18)

    // Synthetic image fixture: demo mode uses its own pasteboard and temporary history.
    let landscape = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { rect in
      NSColor(calibratedRed: 0.75, green: 0.88, blue: 0.94, alpha: 1).setFill()
      rect.fill()
      let hill = NSBezierPath()
      hill.move(to: .zero)
      hill.line(to: NSPoint(x: 0, y: 80))
      hill.curve(to: NSPoint(x: 320, y: 120), controlPoint1: NSPoint(x: 90, y: 220), controlPoint2: NSPoint(x: 180, y: 25))
      hill.line(to: NSPoint(x: 320, y: 0))
      hill.close()
      NSColor(calibratedRed: 0.39, green: 0.65, blue: 0.43, alpha: 1).setFill()
      hill.fill()
      let nearHill = NSBezierPath()
      nearHill.move(to: .zero)
      nearHill.line(to: NSPoint(x: 0, y: 25))
      nearHill.curve(to: NSPoint(x: 320, y: 70), controlPoint1: NSPoint(x: 80, y: 90), controlPoint2: NSPoint(x: 220, y: 0))
      nearHill.line(to: NSPoint(x: 320, y: 0))
      nearHill.close()
      NSColor(calibratedRed: 0.64, green: 0.77, blue: 0.44, alpha: 1).setFill()
      nearHill.fill()
      return true
    }
    if let data = landscape.tiffRepresentation {
      pasteboard.clearContents()
      pasteboard.setData(data, forType: .tiff)
      if var record = ClipboardCodec.capture(from: pasteboard, sourceName: "照片", sourceBundleIdentifier: "com.apple.Photos") {
        record.createdAt = Date(timeIntervalSinceNow: -12 * 60)
        record.lastUsedAt = record.createdAt
        history.add(record)
      }
    }
    addText("https://developer.apple.com/design/resources/", source: "Safari", bundle: "com.apple.Safari", minutesAgo: 8)
    addText("周末，去收集一点灵感。\n\n去逛一家没去过的书店，\n喝一杯喜欢的咖啡，\n把偶然遇见的好点子留下来。", source: "备忘录", bundle: "com.apple.Notes", minutesAgo: 2)
    addText("常用收件地址\n这里是演示内容，不包含真实地址。", source: "备忘录", bundle: "com.apple.Notes", minutesAgo: 60 * 24)
    if let address = history.records.first(where: { $0.title.hasPrefix("常用收件地址") }) {
      history.togglePin(address.id)
    }
    let sampleFolder = FileManager.default.temporaryDirectory.appendingPathComponent("QingTie-preview-\(UUID())")
    let sampleFile = sampleFolder.appendingPathComponent("QingTie 预览示例.txt")
    do {
      try FileManager.default.createDirectory(at: sampleFolder, withIntermediateDirectories: true)
      try "这是 QingTie 的本地文件预览。\n文件、图片和文字都能在右侧查看。".write(to: sampleFile, atomically: true, encoding: .utf8)
      pasteboard.clearContents()
      pasteboard.writeObjects([sampleFile as NSURL])
      if var record = ClipboardCodec.capture(from: pasteboard, sourceName: "访达", sourceBundleIdentifier: "com.apple.finder") {
        record.createdAt = Date(timeIntervalSinceNow: -40 * 60)
        record.lastUsedAt = record.createdAt
        history.add(record)
      }
    } catch { /* Demo fixtures are optional and never affect user history. */ }
  }
}
