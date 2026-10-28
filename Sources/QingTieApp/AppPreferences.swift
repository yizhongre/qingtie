import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppPreferences: ObservableObject {
  let defaults: UserDefaults
  @Published var paused: Bool { didSet { defaults.set(paused, forKey: "capturePaused") } }
  @Published var automaticPaste: Bool { didSet { defaults.set(automaticPaste, forKey: "automaticPaste") } }
  @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
  @Published var shortcut: Int { didSet { defaults.set(shortcut, forKey: "shortcutChoice") } }
  @Published var excludedApplications: String { didSet { defaults.set(excludedApplications, forKey: "excludedApplications") } }
  @Published var loginEnabled = SMAppService.mainApp.status == .enabled
  @Published var message = ""

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: ["automaticPaste": true, "historyLimit": 200])
    paused = defaults.bool(forKey: "capturePaused")
    automaticPaste = defaults.bool(forKey: "automaticPaste")
    historyLimit = max(1, defaults.integer(forKey: "historyLimit"))
    shortcut = defaults.integer(forKey: "shortcutChoice")
    excludedApplications = defaults.string(forKey: "excludedApplications") ?? ""
  }

  func excludes(_ bundleID: String?) -> Bool {
    guard let bundleID else { return false }
    let entries = excludedApplications.components(separatedBy: CharacterSet(charactersIn: ",，;\n "))
    return entries.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
  }

  func changeLogin(_ enabled: Bool) {
    do {
      if enabled { try SMAppService.mainApp.register() }
      else { try SMAppService.mainApp.unregister() }
      loginEnabled = SMAppService.mainApp.status == .enabled
      message = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 QingTie。" : ""
    } catch {
      loginEnabled = SMAppService.mainApp.status == .enabled
      message = "无法更改登录项：\(error.localizedDescription)"
    }
  }
}

struct PreferencesView: View {
  @ObservedObject var preferences: AppPreferences
  let openPermission: () -> Void
  let clearHistory: () -> Void
  @State private var confirmingClear = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 10) {
          sectionHeading("使用")
          HStack {
            Text("打开历史记录")
            Spacer()
            Picker("打开历史记录", selection: $preferences.shortcut) {
              Text("⇧⌘V").tag(0)
              Text("⌃⌥V").tag(1)
              Text("⌥空格").tag(2)
            }
            .labelsHidden()
            .frame(width: 116)
            .accessibilityLabel("打开历史记录")
          }
          Toggle("选择后自动粘贴", isOn: $preferences.automaticPaste)
          supportingText("自动粘贴需要辅助功能权限；未授权时仍可复制，再按 ⌘V 粘贴。")
          Button("打开辅助功能设置", action: openPermission)
            .buttonStyle(QuietButtonStyle(active: true))
            .padding(.leading, -7)
          Toggle("登录时启动 QingTie", isOn: Binding(get: { preferences.loginEnabled }, set: preferences.changeLogin))
        }
        Hairline()
        VStack(alignment: .leading, spacing: 10) {
          sectionHeading("历史记录")
          Toggle("暂停记录新内容", isOn: $preferences.paused)
          HStack {
            Text("保留未固定记录")
            Spacer()
            Picker("保留未固定记录", selection: $preferences.historyLimit) {
              ForEach(Array(Set([50, 200, 500, 1000, preferences.historyLimit])).sorted(), id: \.self) { Text("\($0) 条").tag($0) }
            }
            .labelsHidden()
            .frame(width: 116)
            .accessibilityLabel("保留未固定记录")
          }
          supportingText("固定记录单独保留。剪贴板内容只保存在本机。")
          TextField("忽略应用的标识符，以逗号分隔", text: $preferences.excludedApplications)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("忽略应用的标识符，以逗号分隔")
          supportingText("例如 com.apple.keychainaccess。密码工具标记的保密内容会自动忽略。")
          Button(role: .destructive) { confirmingClear = true } label: {
            Text("清除未固定记录…")
              .foregroundStyle(.red)
          }
          .buttonStyle(QuietButtonStyle())
          .padding(.leading, -7)
        }
        if !preferences.message.isEmpty {
          Text(preferences.message)
            .foregroundStyle(.orange)
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.system(size: 13))
    .foregroundStyle(QingTieTheme.ink)
    .toggleStyle(.checkbox)
    .background(QingTieTheme.canvas)
    .frame(width: 460, height: 520)
    .confirmationDialog("清除全部未固定记录？", isPresented: $confirmingClear) {
      Button("清除记录", role: .destructive, action: clearHistory)
      Button("取消", role: .cancel) {}
    } message: { Text("固定记录和当前系统剪贴板内容会保留。") }
  }

  private func sectionHeading(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(QingTieTheme.secondary)
      .padding(.bottom, 2)
      .accessibilityAddTraits(.isHeader)
  }

  private func supportingText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundStyle(QingTieTheme.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .lineSpacing(3)
  }
}
