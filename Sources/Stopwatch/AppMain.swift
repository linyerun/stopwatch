import SwiftUI
import AppKit

@main
struct StopwatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = TimerModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
