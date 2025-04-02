import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(0)
            
            StatisticsView()
                .tabItem {
                    Label("統計", systemImage: "chart.bar")
                }
                .tag(1)
        }
        .padding(.top, 1) // タブビューの上部に小さなパディングを追加
    }
}
