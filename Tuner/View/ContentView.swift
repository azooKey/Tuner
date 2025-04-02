import SwiftUI

/// アプリケーションのメインビュー
/// - タブベースのナビゲーションを提供
/// - 設定画面と統計画面を切り替え可能
struct ContentView: View {
    /// ビューの本体
    /// - TabViewを使用して設定画面と統計画面を切り替え
    /// - 各タブには適切なアイコンとラベルを設定
    var body: some View {
        TabView {
            // 設定画面
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(0)
            
            // 統計画面
            StatisticsView()
                .tabItem {
                    Label("統計", systemImage: "chart.bar")
                }
                .tag(1)
        }
        .padding(.top, 1) // タブビューの上部に小さなパディングを追加
    }
}
