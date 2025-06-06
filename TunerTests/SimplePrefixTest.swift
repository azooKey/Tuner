import XCTest
@testable import Tuner

class SimplePrefixTest: XCTestCase {
    
    func testSimplePrefix() {
        let entries = [
            TextEntry(appName: "TestApp", text: "おはy", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "おはよ", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "おはよう", timestamp: Date())
        ]
        
        // 長い順にソート
        let sorted = entries.sorted { $0.text.count > $1.text.count }
        print("Sorted: \(sorted.map { $0.text })")
        
        // 前方一致テスト
        let longer = "おはよう"
        let shorter1 = "おはよ"
        let shorter2 = "おはy"
        
        print("'\(longer)'.hasPrefix('\(shorter1)') = \(longer.hasPrefix(shorter1))")
        print("'\(longer)'.hasPrefix('\(shorter2)') = \(longer.hasPrefix(shorter2))")
        
        let ratio1 = Double(shorter1.count) / Double(longer.count)
        let ratio2 = Double(shorter2.count) / Double(longer.count)
        
        print("Ratio1: \(ratio1) >= 0.9? \(ratio1 >= 0.9)")
        print("Ratio2: \(ratio2) >= 0.9? \(ratio2 >= 0.9)")
        
        // 文字数をチェック
        print("おはよう length: \(longer.count)")
        print("おはよ length: \(shorter1.count)")
        print("おはy length: \(shorter2.count)")
        
        // hasPrefix のテスト結果をプリント
        print("hasPrefix results:")
        print("  おはよう.hasPrefix(おはよ): \(longer.hasPrefix(shorter1))")
        print("  おはよう.hasPrefix(おはy): \(longer.hasPrefix(shorter2))")
        
        // 文字列をバイト単位で確認
        print("Characters:")
        print("  おはよう: \(Array(longer))")
        print("  おはよ: \(Array(shorter1))")
        print("  おはy: \(Array(shorter2))")
        
        // 計算の確認
        print("Calculations:")
        print("  3/4 = \(3.0/4.0) >= 0.9? \(3.0/4.0 >= 0.9)")
        print("  3/4 = \(Double(3)/Double(4)) >= 0.9? \(Double(3)/Double(4) >= 0.9)")
    }
}