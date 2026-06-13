import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the terminal launched executable to register as a standard GUI window in macOS
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct ComicPanelReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .frame(minWidth: 700, minHeight: 500)
                .background(Color.black)
        }
        .commands {
            SidebarCommands()
            
            CommandGroup(replacing: .newItem) {
                Button("Open Comic Book...") {
                    NotificationCenter.default.post(name: NSNotification.Name("trigger_comic_import"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
