import XCTest
@testable import Tuner

class DirectTestPrefixDeduplication: XCTestCase {
    
    func testDirectPrefixLogic() {
        // 直接的なテスト
        let longer = "おはよう"
        let shorter1 = "おはよ"
        let shorter2 = "おはy"
        
        print("=== Direct Logic Test ===")
        print("Testing prefix matching logic:")
        print("Longer: '\(longer)' (length: \(longer.count))")
        print("Shorter1: '\(shorter1)' (length: \(shorter1.count))")
        print("Shorter2: '\(shorter2)' (length: \(shorter2.count))")
        
        // hasPrefix tests
        let test1 = longer.hasPrefix(shorter1)
        let test2 = longer.hasPrefix(shorter2)
        
        print("'\(longer)'.hasPrefix('\(shorter1)') = \(test1)")
        print("'\(longer)'.hasPrefix('\(shorter2)') = \(test2)")
        
        // ratio calculations
        let ratio1 = Double(shorter1.count) / Double(longer.count)
        let ratio2 = Double(shorter2.count) / Double(longer.count)
        
        print("Ratio1: \(shorter1.count)/\(longer.count) = \(ratio1)")
        print("Ratio2: \(shorter2.count)/\(longer.count) = \(ratio2)")
        print("Ratio1 >= 0.7? \(ratio1 >= 0.7)")
        print("Ratio2 >= 0.7? \(ratio2 >= 0.7)")
        
        // Expected behavior:
        // - Both should be prefixes of longer string
        // - Both ratios should be >= 0.7 (3/4 = 0.75)
        // - So both shorter strings should be removed
        
        XCTAssertTrue(test1, "おはよう should start with おはよ")
        XCTAssertTrue(test2, "おはよう should start with おはy")
        XCTAssertTrue(ratio1 >= 0.7, "Ratio \(ratio1) should be >= 0.7")
        XCTAssertTrue(ratio2 >= 0.7, "Ratio \(ratio2) should be >= 0.7")
        
        print("=== All direct tests passed ===")
    }
    
    func testManualAlgorithm() {
        print("=== Manual Algorithm Test ===")
        
        // Manual implementation
        let entries = [
            ("おはy", 3),
            ("おはよ", 3),
            ("おはよう", 4)
        ]
        
        // Sort by length descending
        let sorted = entries.sorted { $0.1 > $1.1 }
        print("Sorted by length: \(sorted.map { $0.0 })")
        
        var kept: [String] = []
        var removed: [String] = []
        
        for (text, _) in sorted {
            var shouldKeep = true
            
            for existing in kept {
                if existing.hasPrefix(text) {
                    let ratio = Double(text.count) / Double(existing.count)
                    print("Checking: '\(text)' vs '\(existing)', ratio: \(ratio)")
                    if ratio >= 0.7 {
                        print("Removing: '\(text)'")
                        shouldKeep = false
                        removed.append(text)
                        break
                    }
                }
            }
            
            if shouldKeep {
                print("Keeping: '\(text)'")
                kept.append(text)
            }
        }
        
        print("Final kept: \(kept)")
        print("Final removed: \(removed)")
        
        XCTAssertEqual(kept.count, 1, "Should keep only 1 entry")
        XCTAssertEqual(kept.first, "おはよう", "Should keep the longest")
        XCTAssertEqual(removed.count, 2, "Should remove 2 entries")
    }
}