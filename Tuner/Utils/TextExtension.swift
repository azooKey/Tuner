//
//  TextExtension.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/05.
//

import Foundation

/// 文字の種類を判定するための拡張
extension Character {
    /// 文字が日本語かどうかを判定
    /// - ひらがな、カタカナ、漢字の範囲内かどうかをチェック
    var isJapanese: Bool {
        return ("ぁ"..."ゖ").contains(self) || ("ァ"..."ヺ").contains(self) || ("一"..."龯").contains(self)
    }

    /// 文字が英語かどうかを判定
    /// - 大文字・小文字のアルファベットの範囲内かどうかをチェック
    var isEnglish: Bool {
        return ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    /// 文字が数字かどうかを判定
    /// - 0から9の範囲内かどうかをチェック
    var isNumber: Bool {
        return ("0"..."9").contains(self)
    }
}

/// UTF16文字列の判定機能を提供する拡張
extension String.UTF16View {
    /// 文字列が記号または数字のみで構成されているかどうかを判定
    /// - 以下のUnicode範囲をチェック:
    ///   - 数字: 0x0030-0x0039 ('0'-'9')
    ///   - 記号: 0x0021-0x002F ('!'-'/')
    ///   - 記号: 0x003A-0x0040 (':'-'@')
    ///   - 記号: 0x005B-0x0060 ('['-'`')
    ///   - 記号: 0x007B-0x007E ('{'-'~')
    var isSymbolOrNumber: Bool {
        for unit in self {
            switch unit {
            case 0x0030...0x0039, // 数字 '0' (0x0030) から '9' (0x0039)
                 0x0021...0x002F, // 記号 '!' (0x0021) から '/'
                 0x003A...0x0040, // 記号 ':' (0x003A) から '@'
                 0x005B...0x0060, // 記号 '[' (0x005B) から '`'
                 0x007B...0x007E: // 記号 '{' (0x007B) から '~'
                continue
            default:
                return false
            }
        }
        return true
    }
}
