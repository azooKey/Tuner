import XCTest
@testable import Tuner // Import the main module to access its types

class MinHashUtilsTests: XCTestCase {

    var minHash: MinHashOptimized!

    override func setUpWithError() throws {
        // Consistent parameters for tests
        minHash = MinHashOptimized(numHashFunctions: 50, similarityThreshold: 0.7, sequenceLength: 5)
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
        let expected1: [[Unicode.Scalar]] = [
            Array("abcde".unicodeScalars),
            Array("bcdef".unicodeScalars),
            Array("cdefg".unicodeScalars),
            Array("defgh".unicodeScalars),
            Array("efghi".unicodeScalars),
            Array("fghij".unicodeScalars)
        ]
        XCTAssertEqual(minHash.splitText(text1), expected1, "Splitting failed for standard text.")

        let text2 = "abc"
        let expected2: [[Unicode.Scalar]] = [
             Array("abc".unicodeScalars)
        ]
        // Test with sequenceLength = 5
        XCTAssertEqual(minHash.splitText(text2), expected2, "Splitting failed for text shorter than sequence length.")

        let text3 = ""
        let expected3: [[Unicode.Scalar]] = []
        XCTAssertEqual(minHash.splitText(text3), expected3, "Splitting failed for empty text.")

        let text4 = "abcde"
        let expected4: [[Unicode.Scalar]] = [
            Array("abcde".unicodeScalars)
        ]
        XCTAssertEqual(minHash.splitText(text4), expected4, "Splitting failed for text equal to sequence length.")
    }

    func testComputeMinHashSignature() {
        let text1 = "This is a test text."
        let text2 = "This is a test text."
        let text3 = "This is a different text."

        let signature1 = minHash.computeMinHashSignature(for: text1)
        let signature2 = minHash.computeMinHashSignature(for: text2)
        let signature3 = minHash.computeMinHashSignature(for: text3)

        XCTAssertEqual(signature1.count, 50, "Signature length should match numHashFunctions.")
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
        let text1 = "This is a sample text for testing similarity."
        let text2 = "This is a sample text for testing similarity, very similar."
        let text3 = "Completely different content here."
        // Adjust threshold if needed for specific test cases, or use default
        let customMinHash = MinHashOptimized(numHashFunctions: 50, similarityThreshold: 0.7, sequenceLength: 5)

        XCTAssertTrue(customMinHash.isSimilar(text1, text2), "Similar texts should be identified as similar.")
        XCTAssertFalse(customMinHash.isSimilar(text1, text3), "Different texts should not be identified as similar.")
    }

    // MARK: - TextModelOptimizedWithLRU Tests

    func testPurifyTextEntriesWithMinHash() {
        var textModel = TextModelOptimizedWithLRU()
        let date = Date()

        let entries = [
            TextEntry(appName: "AppA", text: "This is the first entry.", timestamp: date),
            TextEntry(appName: "AppB", text: "This is the second entry, slightly different.", timestamp: date),
            TextEntry(appName: "AppC", text: "This is the first entry.", timestamp: date), // Duplicate text
            TextEntry(appName: "AppA", text: "A completely different entry.", timestamp: date),
            TextEntry(appName: "AppD", text: "Short", timestamp: date), // Should be filtered by length
            TextEntry(appName: "AvoidMe", text: "This should be avoided by app name.", timestamp: date),
            // Add incrementally different short entries (all should be filtered by minTextLength = 10)
            TextEntry(appName: "App", text: "今日は遅刻しました．すい", timestamp: date),
            TextEntry(appName: "App", text: "今日は遅刻しました．すいm", timestamp: date),
            TextEntry(appName: "App", text: "今日は遅刻しました．すいま", timestamp: date),
            TextEntry(appName: "App", text: "今日は遅刻しました．すいまs", timestamp: date),
            TextEntry(appName: "App", text: "今日は遅刻しました．すいませ", timestamp: date),
            TextEntry(appName: "App", text: "今日は遅刻しました．すいません", timestamp: date), // Length might be >= 10 depending on encoding, but likely filtered
        ]

        let avoidApps: Set<String> = ["AvoidMe"]
        let minTextLength = 10
        let similarityThreshold = 0.7 // Use the same threshold as in MinHashOptimized

        let (uniqueEntries, duplicateCount) = textModel.purifyTextEntriesWithMinHash(
            entries, avoidApps: avoidApps, minTextLength: minTextLength, similarityThreshold: similarityThreshold
        )

        // Expected unique entries: Index 0, 1, 3, and the first of the new Japanese entries
        // Expected duplicates: Index 2 (similar to 0) + 5 subsequent Japanese entries (similar to the first Japanese one)
        // Expected filtered: Index 4 (length), Index 5 (avoidApp)

        XCTAssertEqual(uniqueEntries.count, 4, "Incorrect number of unique entries.")
        XCTAssertEqual(duplicateCount, 6, "Incorrect duplicate count.")

        // Check if the correct entries are present (order might vary depending on MinHash specifics)
        let uniqueTexts = Set(uniqueEntries.map { $0.text })
        XCTAssertTrue(uniqueTexts.contains("This is the first entry."))
        XCTAssertTrue(uniqueTexts.contains("This is the second entry, slightly different."))
        XCTAssertTrue(uniqueTexts.contains("A completely different entry."))
        XCTAssertTrue(uniqueTexts.contains("今日は遅刻しました．すい"))

        // Check if filtered/duplicate entries are not present
        XCTAssertFalse(uniqueTexts.contains("Short"))
        XCTAssertFalse(uniqueTexts.contains("This should be avoided by app name."))
    }
} 
