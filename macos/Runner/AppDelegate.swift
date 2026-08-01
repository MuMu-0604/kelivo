import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    let mainWindow = sender.windows.first { $0 is MainFlutterWindow }
      ?? sender.windows.first { $0.canBecomeKey }

    if let window = mainWindow {
      if window.isMiniaturized {
        window.deminiaturize(self)
      }
      window.orderFrontRegardless()
      window.makeKeyAndOrderFront(self)
    }

    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
