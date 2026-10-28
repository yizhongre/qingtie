import AppKit
import SwiftUI

@MainActor
final class AboutWindow {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 302),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 QingTie"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = info["CFBundleVersion"] as? String, build != version {
            return "版本 \(version)（\(build)）"
        }
        return "版本 \(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("QingTie")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(QingTieTheme.ink)
                    Text(version)
                        .font(.system(size: 11))
                        .foregroundStyle(QingTieTheme.secondary)
                }
            }
            Hairline()
                .padding(.top, 24)
                .padding(.bottom, 22)
            Text("留住复制过的内容，轻轻一贴。")
                .font(.system(size: 12))
                .foregroundStyle(QingTieTheme.ink)
            Text("本地保存，不上传剪贴板内容。")
                .font(.system(size: 11))
                .foregroundStyle(QingTieTheme.secondary)
                .padding(.top, 9)
            Spacer(minLength: 18)
            Text("© 2026 QingTie")
                .font(.system(size: 10))
                .foregroundStyle(QingTieTheme.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 340, height: 302)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QingTieTheme.canvas)
    }
}
