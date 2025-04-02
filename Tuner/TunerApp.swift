import SwiftUI
import Cocoa

/// アプリケーションのメインエントリーポイント
/// - メニューバーアプリケーションとして動作
/// - 設定画面とメニュービューを提供
@main
struct TunerApp: App {
    /// アプリケーションのデリゲート
    /// - アプリケーションのライフサイクル管理
    /// - テキストモデルと共有データの管理
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// アプリケーションのシーン
    /// - メニューバーに表示されるメニュービュー
    /// - 設定画面の表示
    var body: some Scene {
        // メニューバーに表示されるメニュービュー
        MenuBarExtra("Tuner", systemImage: "doc.text"){
            MenuView()
                .environmentObject(appDelegate.textModel)
                .environmentObject(appDelegate.shareData)
        }
        
        // 設定画面
        Settings {
            ContentView()
                .environmentObject(appDelegate.textModel)
                .environmentObject(appDelegate.shareData)
                .frame(width: 450, height: 380)
        }
    }
}
