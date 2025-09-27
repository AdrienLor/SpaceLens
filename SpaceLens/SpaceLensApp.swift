import SwiftUI
import AppKit


class AboutMenuHandler: NSObject {
    @objc func showCustomAboutPanel(_ sender: Any?) {
        SpaceLensApp.showCustomAboutPanel()
    }
}

@main
struct SpaceLensApp: App {
    static let aboutMenuHandler = AboutMenuHandler()

    init() {
        DispatchQueue.main.async {
            if let appMenu = NSApplication.shared.mainMenu?.items.first?.submenu,
               let aboutMenuItem = appMenu.items.first {
                aboutMenuItem.action = #selector(AboutMenuHandler.showCustomAboutPanel(_:))
                aboutMenuItem.target = Self.aboutMenuHandler
            }
        }
    }

    static func showCustomAboutPanel() {
            let alert = NSAlert()
            alert.messageText = "SpaceLens"
            alert.informativeText = "Version 1.1 (Build 2)\n© 2025 Adrien Lorette\nhttps://github.com/AdrienLor"
            alert.icon = NSApp.applicationIconImage
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

