import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the terminal launched executable to register as a standard GUI window in macOS
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Set application icon from resources
        if let iconURL = Bundle.module.url(forResource: "Panels", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct PanelsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        if CommandLine.arguments.contains("--test") {
            Task {
                await runDetectorTest()
                exit(0)
            }
            RunLoop.main.run()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .frame(minWidth: 500, minHeight: 850)
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
