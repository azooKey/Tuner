import XCTest
@testable import Tuner

class DirectTestPrefixDeduplication: XCTestCase {
    
    func testDirectPrefixLogic() {
        // 直接的なテスト
        let longer = "おはよう"
        let shorter1 = "おはよ"
        let shorter2 = "おはy"  // Test partial input similarity
        
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
        
        // Test partial similarity for "おはy"
        let isSimilar = isSimilarPartialInput(shorter: shorter2, longer: longer)
        print("isSimilarPartialInput('\(shorter2)', '\(longer)') = \(isSimilar)")
        
        // ratio calculations
        let ratio1 = Double(shorter1.count) / Double(longer.count)
        let ratio2 = Double(shorter2.count) / Double(longer.count)
        
        print("Ratio1: \(shorter1.count)/\(longer.count) = \(ratio1)")
        print("Ratio2: \(shorter2.count)/\(longer.count) = \(ratio2)")
        print("Ratio1 >= 0.7? \(ratio1 >= 0.7)")
        print("Ratio2 >= 0.7? \(ratio2 >= 0.7)")
        
        // Expected behavior:
        // - "おはよ" should be a valid prefix
        // - "おはy" should be similar partial input 
        // - Both ratios should be >= 0.7 (3/4 = 0.75)
        
        XCTAssertTrue(test1, "おはよう should start with おはよ")
        XCTAssertTrue(isSimilar, "おはy should be similar to おはよう")
        XCTAssertTrue(ratio1 >= 0.7, "Ratio \(ratio1) should be >= 0.7")
        XCTAssertTrue(ratio2 >= 0.7, "Ratio \(ratio2) should be >= 0.7")
        
        print("=== All direct tests passed ===")
    }
    
    // Helper function for testing
    private func isSimilarPartialInput(shorter: String, longer: String) -> Bool {
        guard shorter.count >= 2 && longer.count > shorter.count else { return false }
        
        let shorterChars = Array(shorter)
        let longerChars = Array(longer)
        
        var matchingCount = 0
        let maxCheckLength = min(shorterChars.count, longerChars.count)
        
        for i in 0..<maxCheckLength {
            if shorterChars[i] == longerChars[i] {
                matchingCount += 1
            } else {
                break
            }
        }
        
        let prefixMatchRatio = Double(matchingCount) / Double(shorter.count)
        return prefixMatchRatio >= 0.7 && matchingCount >= shorter.count - 1
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