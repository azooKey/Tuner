//
//  MenuView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI

/// メニューバーに表示されるビュー
/// - アクセシビリティ設定の切り替え
/// - データ保存の切り替え
/// - 設定画面へのアクセス
/// - アプリケーションの終了
struct MenuView: View {
    /// テキストモデル（環境オブジェクト）
    @EnvironmentObject var textModel: TextModel
    
    /// 共有データ（環境オブジェクト）
    @EnvironmentObject var shareData: ShareData

    /// ビューの本体
    /// - アクセシビリティとデータ保存のトグル
    /// - 設定画面へのリンク
    /// - アプリケーション終了ボタン
    var body: some View {
        // アクセシビリティ設定のトグル
        Toggle("Enable Read Everything", isOn: $shareData.activateAccessibility)
            .padding(.bottom)
            .onChange(of: shareData.activateAccessibility) { oldValue, newValue in
                if newValue {
                    checkAndRequestAccessibilityPermission()
                }
            }
        
        // データ保存のトグル
        Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
            .padding(.bottom)
        
        Divider()

        // 設定画面へのリンク
        SettingsLink {
            Label("詳細...", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
        
        // アプリケーション終了ボタン
        Button("Quit") {
            NSApplication.shared.terminate(self)
        }
    }

    /// アクセシビリティ権限をチェックし、必要に応じて要求
    /// - アクセシビリティが有効になったときに呼び出される
    private func checkAndRequestAccessibilityPermission() {
        print("Enable Accessibility")
        shareData.requestAccessibilityPermission()
    }
}

#Preview {
    MenuView()
        .environmentObject(TextModel())
        .environmentObject(ShareData())
}
