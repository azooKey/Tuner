import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            StaticsView()
                .tabItem {
                    Label("Statics", systemImage: "chart.bar")
                }
        }
    }
}
