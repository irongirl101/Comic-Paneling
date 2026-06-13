import SwiftUI

#if os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the command-line compiled SwiftUI app to show a regular window and Dock icon
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

@main
struct ComicPanelReaderApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    
    var body: some Scene {
        WindowGroup {
            LibraryView()
                .frame(minWidth: 400, minHeight: 600)
                #if os(macOS)
                .background(Color.black)
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        #endif
    }
}
