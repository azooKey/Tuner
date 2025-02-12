//
//  TextExtension.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/05.
//

import Foundation

extension Character {
    var isJapanese: Bool {
        return ("ぁ"..."ゖ").contains(self) || ("ァ"..."ヺ").contains(self) || ("一"..."龯").contains(self)
    }

    var isEnglish: Bool {
        return ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    var isNumber: Bool {
        return ("0"..."9").contains(self)
    }
}

extension String.UTF16View {
    // 記号か数字のみか判定
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
