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
        MenuBarExtra {
            // メニューをクリックしたときに表示される内容
            MenuView()
                .environmentObject(appDelegate.textModel)
                .environmentObject(appDelegate.shareData)
        } label: {
            // メニューバーに表示するアイコン画像
            Image("MenuBarIcon") // Assets.xcassets に追加した画像名を指定
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
