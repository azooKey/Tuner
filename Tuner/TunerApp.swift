import SwiftUI
import Cocoa

@main
struct TunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Tuner", systemImage: "doc.text"){
            MenuView()
                .environmentObject(appDelegate.textModel)
        }
        Settings {
            ContentView()
                .environmentObject(appDelegate.textModel)
                .environmentObject(appDelegate.shareData)
                .frame(width: 500, height: 400)
        }
    }
}
