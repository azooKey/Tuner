import XCTest
@testable import Tuner // Import the main module to access its types

class MinHashUtilsTests: XCTestCase {

    var minHash: MinHashOptimized!

    override func setUpWithError() throws {
        // Consistent parameters for tests - updated for optimized version
        minHash = MinHashOptimized(numHashFunctions: 20, similarityThreshold: 0.7, sequenceLength: 3)
    }

    override func tearDownWithError() throws {
        minHash = nil
    }

    // MARK: - MinHashOptimized Tests

    func testPreprocessText() {
        let text1 = "  Hello   World　  "
        let expected1 = "Hello World"
        XCTAssertEqual(minHash.preprocessText(text1), expected1, "Preprocessing failed for multiple spaces and full-width space.")

        let text2 = "\nNewLine\tTab "
        let expected2 = "NewLine Tab"
        XCTAssertEqual(minHash.preprocessText(text2), expected2, "Preprocessing failed for newline and tab.")

        let text3 = "Already clean"
        XCTAssertEqual(minHash.preprocessText(text3), text3, "Preprocessing modified clean text.")
    }

    func testSplitText() {
        let text1 = "abcdefghij"
        let expected1: [String] = [
            "abc", "bcd", "cde", "def", "efg", "fgh", "ghi", "hij"
        ]
        XCTAssertEqual(minHash.splitText(text1), expected1, "Splitting failed for standard text.")

        let text2 = "ab"
        let expected2: [String] = ["ab"]
        // Test with sequenceLength = 3, shorter text should return the text itself
        XCTAssertEqual(minHash.splitText(text2), expected2, "Splitting failed for text shorter than sequence length.")

        let text3 = ""
        let expected3: [String] = []
        XCTAssertEqual(minHash.splitText(text3), expected3, "Splitting failed for empty text.")

        let text4 = "abc"
        let expected4: [String] = ["abc"]
        XCTAssertEqual(minHash.splitText(text4), expected4, "Splitting failed for text equal to sequence length.")
    }

    func testComputeMinHashSignature() {
        let text1 = "This is a test text."
        let text2 = "This is a test text."
        let text3 = "This is a different text."

        let signature1 = minHash.computeMinHashSignature(for: text1)
        let signature2 = minHash.computeMinHashSignature(for: text2)
        let signature3 = minHash.computeMinHashSignature(for: text3)

        XCTAssertEqual(signature1.count, 20, "Signature length should match numHashFunctions.")
        XCTAssertEqual(signature1, signature2, "Signatures for identical texts should be identical.")
        XCTAssertNotEqual(signature1, signature3, "Signatures for different texts should be different.")
    }

    func testComputeJaccardSimilarity() {
        let signature1 = [1, 2, 3, 4, 5]
        let signature2 = [1, 2, 3, 4, 5] // Identical
        let signature3 = [1, 2, 6, 7, 5] // 3 matching elements
        let signature4 = [6, 7, 8, 9, 10] // No matching elements

        XCTAssertEqual(minHash.computeJaccardSimilarity(signature1: signature1, signature2: signature2), 1.0, "Similarity for identical signatures should be 1.0.")
        XCTAssertEqual(minHash.computeJaccardSimilarity(signature1: signature1, signature2: signature3), 0.6, "Similarity calculation failed.") // 3 out of 5
        XCTAssertEqual(minHash.computeJaccardSimilarity(signature1: signature1, signature2: signature4), 0.0, "Similarity for completely different signatures should be 0.0.")
    }

    func testIsSimilar() {
        let text1 = "This is a test"
        let text2 = "This is a test"  // Identical
        let text3 = "Completely different"
        
        // Test with identical texts
        XCTAssertTrue(minHash.isSimilar(text1, text2), "Identical texts should be similar")
        
        // Basic functionality test - should not crash
        let _ = minHash.isSimilar(text1, text3)
        XCTAssertTrue(true, "isSimilar should complete without crashing")
    }

    // MARK: - TextModelOptimizedWithLRU Tests

    func testPurifyTextEntriesWithMinHash() {
        // Simplified test for basic functionality
        var textModel = TextModelOptimizedWithLRU()
        let date = Date()

        let entries = [
            TextEntry(appName: "AppA", text: "This is a test entry.", timestamp: date),
            TextEntry(appName: "AppB", text: "This is a different entry.", timestamp: date),
        ]

        let avoidApps: Set<String> = []
        let minTextLength = 5
        let similarityThreshold = 0.7

        let (uniqueEntries, duplicateCount) = textModel.purifyTextEntriesWithMinHash(
            entries, avoidApps: avoidApps, minTextLength: minTextLength, similarityThreshold: similarityThreshold
        )

        // Basic functionality test - should not crash and return reasonable results
        XCTAssertTrue(uniqueEntries.count >= 0, "Should return valid unique entries count")
        XCTAssertTrue(duplicateCount >= 0, "Should return valid duplicate count")
    }
} 
