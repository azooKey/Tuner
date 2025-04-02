//
//  TextEntry.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/06/30.
//

import Foundation

/// テキストエントリを表す構造体
/// - アプリケーション名、テキスト内容、タイムスタンプを保持
/// - Codableプロトコルに準拠してJSONシリアライズをサポート
/// - Hashableプロトコルに準拠して重複チェックをサポート
struct TextEntry: Codable, Hashable {
    /// テキストが取得されたアプリケーション名
    var appName: String
    
    /// 取得されたテキスト内容
    var text: String
    
    /// テキストが取得された時刻
    var timestamp: Date

    /// カスタムのハッシュ関数
    /// - アプリケーション名とテキスト内容のみを使用してハッシュを生成
    /// - タイムスタンプは重複チェックに使用しない
    /// - Parameters:
    ///   - hasher: ハッシュ値を生成するためのハッシャー
    func hash(into hasher: inout Hasher) {
        hasher.combine(appName)
        hasher.combine(text)
    }

    /// イコール関数のオーバーライド
    /// - アプリケーション名とテキスト内容が一致する場合にtrueを返す
    /// - タイムスタンプは比較に使用しない
    /// - Parameters:
    ///   - lhs: 左辺のTextEntry
    ///   - rhs: 右辺のTextEntry
    /// - Returns: アプリケーション名とテキスト内容が一致する場合はtrue
    static func == (lhs: TextEntry, rhs: TextEntry) -> Bool {
        return lhs.appName == rhs.appName && lhs.text == rhs.text
    }
}
