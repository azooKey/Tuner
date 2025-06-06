import XCTest
@testable import Tuner

class StringAnalysisTest: XCTestCase {
    
    func testJapaneseStringLengths() {
        let str1 = "おはy"
        let str2 = "おはよ"
        let str3 = "おはよう"
        
        print("=== String Analysis ===")
        print("String: '\(str1)' - Count: \(str1.count) - Characters: \(Array(str1))")
        print("String: '\(str2)' - Count: \(str2.count) - Characters: \(Array(str2))")
        print("String: '\(str3)' - Count: \(str3.count) - Characters: \(Array(str3))")
        
        print("\nPrefix tests:")
        print("'\(str3)'.hasPrefix('\(str1)') = \(str3.hasPrefix(str1))")
        print("'\(str3)'.hasPrefix('\(str2)') = \(str3.hasPrefix(str2))")
        
        print("\nRatio calculations:")
        let ratio1 = Double(str1.count) / Double(str3.count)
        let ratio2 = Double(str2.count) / Double(str3.count)
        print("Ratio 1: \(str1.count)/\(str3.count) = \(ratio1)")
        print("Ratio 2: \(str2.count)/\(str3.count) = \(ratio2)")
        
        // Basic assertions that should pass
        XCTAssertEqual(str1.count, 3, "おはy should have 3 characters")
        XCTAssertEqual(str2.count, 3, "おはよ should have 3 characters")
        XCTAssertEqual(str3.count, 4, "おはよう should have 4 characters")
        
        // If the above pass, then ratio calculations should be:
        // 3/4 = 0.75 for both str1 and str2
        XCTAssertEqual(ratio1, 0.75, accuracy: 0.001, "Ratio should be 0.75")
        XCTAssertEqual(ratio2, 0.75, accuracy: 0.001, "Ratio should be 0.75")
        
        // Both should be >= 0.7
        XCTAssertTrue(ratio1 >= 0.7, "Ratio \(ratio1) should be >= 0.7")
        XCTAssertTrue(ratio2 >= 0.7, "Ratio \(ratio2) should be >= 0.7")
        
        print("=== All string analysis tests passed ===")
    }
}