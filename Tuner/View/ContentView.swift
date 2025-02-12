import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }
        }
    }
}
