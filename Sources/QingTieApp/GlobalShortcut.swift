import AppKit
import Carbon

@MainActor
final class GlobalShortcut {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  var onPress: (() -> Void)?

  init() {
    var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
      guard let userData else { return OSStatus(eventNotHandledErr) }
      let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
      MainActor.assumeIsolated { shortcut.onPress?() }
      return noErr
    }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  func register(choice: Int) -> Bool {
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    let key: UInt32 = choice == 2 ? UInt32(kVK_Space) : UInt32(kVK_ANSI_V)
    let modifiers = choice == 1 ? UInt32(controlKey | optionKey)
      : choice == 2 ? UInt32(optionKey) : UInt32(cmdKey | shiftKey)
    let identifier = EventHotKeyID(signature: 0x51544945, id: 1)
    return RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey) == noErr
  }

  func stop() {
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    if let handler { RemoveEventHandler(handler); self.handler = nil }
  }
}
