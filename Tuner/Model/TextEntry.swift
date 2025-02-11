//
//  TextEntry.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/06/30.
//

import Foundation


struct TextEntry: Codable, Hashable {
    var appName: String
    var text: String
    var timestamp: Date

    // カスタムのハッシュ関数
    func hash(into hasher: inout Hasher) {
        hasher.combine(appName)
        hasher.combine(text)
    }

    // イコール関数のオーバーライド
    static func == (lhs: TextEntry, rhs: TextEntry) -> Bool {
        return lhs.appName == rhs.appName && lhs.text == rhs.text
    }
}
