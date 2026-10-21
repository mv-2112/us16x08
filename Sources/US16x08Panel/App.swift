// SPDX-License-Identifier: GPL-2.0-or-later
//
// US-16x08 Panel: an unofficial control panel for the TASCAM US-16x08.
// Not affiliated with TASCAM / TEAC Corporation, the Linux kernel or ALSA
// maintainers, or the GNU Project.
//
// Derivative work. The USB protocol knowledge used here comes from the Linux
// kernel driver sound/usb/mixer_us16x08.c, Copyright (c) 2016 by Detlef Urban,
// GPL-2.0-or-later.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation; either version 2 of the License, or (at your option) any later
// version. It is distributed WITHOUT ANY WARRANTY. See the file COPYING.

import SwiftUI
import AppKit

enum AppInfo {
    static let mainWindowTitle = "US-16x08 Panel (unofficial)"
    /// Bump when the window layout changes so macOS forgets frames saved for an older, larger layout.
    static let layoutVersion = 2
}

/// Closing the main window quits the app (there is nothing useful to keep running without it).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            if let w = note.object as? NSWindow, w.title == AppInfo.mainWindowTitle {
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}

@main
struct US16x08PanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() {
        let d = UserDefaults.standard
        if d.integer(forKey: "layoutVersion") != AppInfo.layoutVersion {
            for key in d.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame") { d.removeObject(forKey: key) }
            d.set(AppInfo.layoutVersion, forKey: "layoutVersion")
        }
        // Needed so the window comes to the front when launched via `swift run`.
        NSApplication.shared.setActivationPolicy(.regular)
        // `swift run` has no app bundle and so no icon; borrow it from the package folder.
        if Bundle.main.bundleIdentifier == nil, let icon = NSImage(contentsOfFile: "Resources/AppIcon-1024.png") {
            NSApplication.shared.applicationIconImage = icon
        }
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup(AppInfo.mainWindowTitle) {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    model.appearance.apply()
                    model.connect()
                }
        }
        .defaultSize(width: Layout.defaultWidth, height: Layout.defaultHeight)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }

        // The log and the About box live in their own windows, opened from the menu bar.
        Window("Diagnostics Log", id: "diagnostics") {
            DiagnosticsView()
                .environmentObject(model)
                .frame(minWidth: 560, minHeight: 320)
        }
        .defaultSize(width: 760, height: 480)

        Window("About US-16x08 Panel", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About US-16x08 Panel") { openWindow(id: "about") }
        }
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Diagnostics Log") { openWindow(id: "diagnostics") }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }
}
