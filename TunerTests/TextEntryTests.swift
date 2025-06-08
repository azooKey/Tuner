import XCTest
@testable import Tuner

class TextEntryTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testTextEntry_Initialization() {
        // Given
        let appName = "TestApp"
        let text = "Sample text content"
        let timestamp = Date()
        
        // When
        let entry = TextEntry(appName: appName, text: text, timestamp: timestamp)
        
        // Then
        XCTAssertEqual(entry.appName, appName)
        XCTAssertEqual(entry.text, text)
        XCTAssertEqual(entry.timestamp, timestamp)
    }
    
    func testTextEntry_InitializationWithEmptyValues() {
        // Given
        let appName = ""
        let text = ""
        let timestamp = Date()
        
        // When
        let entry = TextEntry(appName: appName, text: text, timestamp: timestamp)
        
        // Then
        XCTAssertEqual(entry.appName, "")
        XCTAssertEqual(entry.text, "")
        XCTAssertEqual(entry.timestamp, timestamp)
    }
    
    func testTextEntry_InitializationWithUnicodeText() {
        // Given
        let appName = "UnicodeTester"
        let text = "テスト文字列 🎌 Hello 世界 こんにちは"
        let timestamp = Date()
        
        // When
        let entry = TextEntry(appName: appName, text: text, timestamp: timestamp)
        
        // Then
        XCTAssertEqual(entry.appName, appName)
        XCTAssertEqual(entry.text, text)
        XCTAssertEqual(entry.timestamp, timestamp)
    }
    
    // MARK: - Codable Tests
    
    func testTextEntry_JSONEncoding() throws {
        // Given
        let appName = "TestApp"
        let text = "Sample text for encoding"
        let timestamp = Date(timeIntervalSince1970: 1609459200) // Fixed timestamp for consistent testing
        let entry = TextEntry(appName: appName, text: text, timestamp: timestamp)
        
        // When
        let jsonData = try JSONEncoder().encode(entry)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        // Then
        XCTAssertNotNil(jsonData)
        XCTAssertTrue(jsonString.contains("TestApp"))
        XCTAssertTrue(jsonString.contains("Sample text for encoding"))
        XCTAssertTrue(jsonString.contains("timestamp"))
        XCTAssertTrue(jsonString.contains("appName"))
        XCTAssertTrue(jsonString.contains("text"))
    }
    
    func testTextEntry_JSONDecoding() throws {
        // Given - Use a simple round-trip test instead of hardcoded timestamp
        let originalEntry = TextEntry(
            appName: "DecodedApp",
            text: "Decoded text content",
            timestamp: Date(timeIntervalSince1970: 1609459200.0)
        )
        
        // When - Encode then decode
        let jsonData = try JSONEncoder().encode(originalEntry)
        let decodedEntry = try JSONDecoder().decode(TextEntry.self, from: jsonData)
        
        // Then
        XCTAssertEqual(decodedEntry.appName, "DecodedApp")
        XCTAssertEqual(decodedEntry.text, "Decoded text content")
        XCTAssertEqual(decodedEntry.timestamp.timeIntervalSince1970, 1609459200.0, accuracy: 0.001)
    }
    
    func testTextEntry_JSONEncodingDecoding_RoundTrip() throws {
        // Given
        let originalEntry = TextEntry(
            appName: "RoundTripApp",
            text: "Round trip test content with special chars: 日本語テスト 123 !@#",
            timestamp: Date()
        )
        
        // When
        let jsonData = try JSONEncoder().encode(originalEntry)
        let decodedEntry = try JSONDecoder().decode(TextEntry.self, from: jsonData)
        
        // Then
        XCTAssertEqual(decodedEntry.appName, originalEntry.appName)
        XCTAssertEqual(decodedEntry.text, originalEntry.text)
        XCTAssertEqual(decodedEntry.timestamp.timeIntervalSince1970, 
                      originalEntry.timestamp.timeIntervalSince1970, 
                      accuracy: 0.001) // Small accuracy for floating point comparison
    }
    
    func testTextEntry_JSONDecoding_MissingFields() {
        // Given - JSON missing required fields
        let incompleteJSON = """
{
    "appName": "IncompleteApp"
}
"""
        let jsonData = incompleteJSON.data(using: .utf8)!
        
        // When/Then
        XCTAssertThrowsError(try JSONDecoder().decode(TextEntry.self, from: jsonData))
    }
    
    func testTextEntry_JSONDecoding_InvalidJSON() {
        // Given
        let invalidJSON = """
{
    "appName": "InvalidApp",
    "text": "Valid text",
    "timestamp": "invalid_timestamp_format"
}
"""
        let jsonData = invalidJSON.data(using: .utf8)!
        
        // When/Then
        XCTAssertThrowsError(try JSONDecoder().decode(TextEntry.self, from: jsonData))
    }
    
    func testTextEntry_JSONEncoding_WithSpecialCharacters() throws {
        // Given
        let entry = TextEntry(
            appName: "Special\"Chars\\App/Test",
            text: "Text with\nnewlines\tand\r\"quotes\" and backslashes\\",
            timestamp: Date()
        )
        
        // When
        let jsonData = try JSONEncoder().encode(entry)
        let decodedEntry = try JSONDecoder().decode(TextEntry.self, from: jsonData)
        
        // Then
        XCTAssertEqual(decodedEntry.appName, entry.appName)
        XCTAssertEqual(decodedEntry.text, entry.text)
    }
    
    // MARK: - Hashable Tests
    
    func testTextEntry_Hash_SameContent() {
        // Given
        let timestamp1 = Date()
        let timestamp2 = Date(timeIntervalSinceNow: 3600) // 1 hour later
        
        let entry1 = TextEntry(appName: "App", text: "Content", timestamp: timestamp1)
        let entry2 = TextEntry(appName: "App", text: "Content", timestamp: timestamp2)
        
        // When
        let hash1 = entry1.hashValue
        let hash2 = entry2.hashValue
        
        // Then
        XCTAssertEqual(hash1, hash2, "Entries with same appName and text should have same hash regardless of timestamp")
    }
    
    func testTextEntry_Hash_DifferentAppName() {
        // Given
        let timestamp = Date()
        let entry1 = TextEntry(appName: "App1", text: "Content", timestamp: timestamp)
        let entry2 = TextEntry(appName: "App2", text: "Content", timestamp: timestamp)
        
        // When
        let hash1 = entry1.hashValue
        let hash2 = entry2.hashValue
        
        // Then
        XCTAssertNotEqual(hash1, hash2, "Entries with different appName should have different hash")
    }
    
    func testTextEntry_Hash_DifferentText() {
        // Given
        let timestamp = Date()
        let entry1 = TextEntry(appName: "App", text: "Content1", timestamp: timestamp)
        let entry2 = TextEntry(appName: "App", text: "Content2", timestamp: timestamp)
        
        // When
        let hash1 = entry1.hashValue
        let hash2 = entry2.hashValue
        
        // Then
        XCTAssertNotEqual(hash1, hash2, "Entries with different text should have different hash")
    }
    
    func testTextEntry_HashConsistency() {
        // Given
        let entry = TextEntry(appName: "ConsistencyApp", text: "Consistency test", timestamp: Date())
        
        // When
        let hash1 = entry.hashValue
        let hash2 = entry.hashValue
        let hash3 = entry.hashValue
        
        // Then
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash1, hash3)
    }
    
    func testTextEntry_HashWithEmptyValues() {
        // Given
        let entry1 = TextEntry(appName: "", text: "", timestamp: Date())
        let entry2 = TextEntry(appName: "", text: "", timestamp: Date(timeIntervalSinceNow: 1000))
        
        // When
        let hash1 = entry1.hashValue
        let hash2 = entry2.hashValue
        
        // Then
        XCTAssertEqual(hash1, hash2, "Empty entries should have same hash regardless of timestamp")
    }
    
    // MARK: - Equality Tests
    
    func testTextEntry_Equality_SameContent() {
        // Given
        let timestamp1 = Date()
        let timestamp2 = Date(timeIntervalSinceNow: 3600) // 1 hour later
        
        let entry1 = TextEntry(appName: "App", text: "Content", timestamp: timestamp1)
        let entry2 = TextEntry(appName: "App", text: "Content", timestamp: timestamp2)
        
        // When/Then
        XCTAssertEqual(entry1, entry2, "Entries with same appName and text should be equal regardless of timestamp")
        XCTAssertTrue(entry1 == entry2)
    }
    
    func testTextEntry_Equality_DifferentAppName() {
        // Given
        let timestamp = Date()
        let entry1 = TextEntry(appName: "App1", text: "Content", timestamp: timestamp)
        let entry2 = TextEntry(appName: "App2", text: "Content", timestamp: timestamp)
        
        // When/Then
        XCTAssertNotEqual(entry1, entry2, "Entries with different appName should not be equal")
        XCTAssertFalse(entry1 == entry2)
    }
    
    func testTextEntry_Equality_DifferentText() {
        // Given
        let timestamp = Date()
        let entry1 = TextEntry(appName: "App", text: "Content1", timestamp: timestamp)
        let entry2 = TextEntry(appName: "App", text: "Content2", timestamp: timestamp)
        
        // When/Then
        XCTAssertNotEqual(entry1, entry2, "Entries with different text should not be equal")
        XCTAssertFalse(entry1 == entry2)
    }
    
    func testTextEntry_Equality_SameInstance() {
        // Given
        let entry = TextEntry(appName: "App", text: "Content", timestamp: Date())
        
        // When/Then
        XCTAssertEqual(entry, entry, "Entry should be equal to itself")
        XCTAssertTrue(entry == entry)
    }
    
    func testTextEntry_Equality_EmptyValues() {
        // Given
        let entry1 = TextEntry(appName: "", text: "", timestamp: Date())
        let entry2 = TextEntry(appName: "", text: "", timestamp: Date(timeIntervalSinceNow: 1000))
        
        // When/Then
        XCTAssertEqual(entry1, entry2, "Empty entries should be equal regardless of timestamp")
    }
    
    func testTextEntry_Equality_UnicodeContent() {
        // Given
        let timestamp = Date()
        let entry1 = TextEntry(appName: "日本語アプリ", text: "テスト内容 🎌", timestamp: timestamp)
        let entry2 = TextEntry(appName: "日本語アプリ", text: "テスト内容 🎌", timestamp: Date(timeIntervalSinceNow: 100))
        
        // When/Then
        XCTAssertEqual(entry1, entry2, "Unicode entries should be equal when appName and text match")
    }
    
    func testTextEntry_Equality_CaseSensitive() {
        // Given
        let timestamp = Date()
        let entry1 = TextEntry(appName: "app", text: "content", timestamp: timestamp)
        let entry2 = TextEntry(appName: "App", text: "Content", timestamp: timestamp)
        
        // When/Then
        XCTAssertNotEqual(entry1, entry2, "Equality should be case sensitive")
    }
    
    // MARK: - Set and Dictionary Tests
    
    func testTextEntry_InSet() {
        // Given
        let entry1 = TextEntry(appName: "App", text: "Content", timestamp: Date())
        let entry2 = TextEntry(appName: "App", text: "Content", timestamp: Date(timeIntervalSinceNow: 100))
        let entry3 = TextEntry(appName: "App", text: "Different", timestamp: Date())
        
        var entrySet: Set<TextEntry> = []
        
        // When
        entrySet.insert(entry1)
        entrySet.insert(entry2) // Should not be added (duplicate)
        entrySet.insert(entry3) // Should be added (different text)
        
        // Then
        XCTAssertEqual(entrySet.count, 2, "Set should contain only unique entries")
        XCTAssertTrue(entrySet.contains(entry1))
        XCTAssertTrue(entrySet.contains(entry2)) // Should be found since it's equal to entry1
        XCTAssertTrue(entrySet.contains(entry3))
    }
    
    func testTextEntry_AsDictionaryKey() {
        // Given
        let entry1 = TextEntry(appName: "App", text: "Content", timestamp: Date())
        let entry2 = TextEntry(appName: "App", text: "Content", timestamp: Date(timeIntervalSinceNow: 100))
        let entry3 = TextEntry(appName: "App", text: "Different", timestamp: Date())
        
        var entryDict: [TextEntry: String] = [:]
        
        // When
        entryDict[entry1] = "Value1"
        entryDict[entry2] = "Value2" // Should overwrite Value1
        entryDict[entry3] = "Value3" // Should be separate entry
        
        // Then
        XCTAssertEqual(entryDict.count, 2, "Dictionary should have only unique keys")
        XCTAssertEqual(entryDict[entry1], "Value2", "Value should be overwritten")
        XCTAssertEqual(entryDict[entry2], "Value2", "Both entries should map to same value")
        XCTAssertEqual(entryDict[entry3], "Value3", "Different entry should have its own value")
    }
    
    // MARK: - Property Mutation Tests
    
    func testTextEntry_Mutability() {
        // Given
        var entry = TextEntry(appName: "Original", text: "Original content", timestamp: Date())
        let originalTimestamp = entry.timestamp
        
        // When
        entry.appName = "Modified"
        entry.text = "Modified content"
        entry.timestamp = Date(timeIntervalSinceNow: 1000)
        
        // Then
        XCTAssertEqual(entry.appName, "Modified")
        XCTAssertEqual(entry.text, "Modified content")
        XCTAssertNotEqual(entry.timestamp, originalTimestamp)
    }
    
    // MARK: - Edge Cases and Validation Tests
    
    func testTextEntry_LongContent() {
        // Given
        let longAppName = String(repeating: "A", count: 1000)
        let longText = String(repeating: "T", count: 10000)
        let timestamp = Date()
        
        // When
        let entry = TextEntry(appName: longAppName, text: longText, timestamp: timestamp)
        
        // Then
        XCTAssertEqual(entry.appName.count, 1000)
        XCTAssertEqual(entry.text.count, 10000)
        XCTAssertEqual(entry.timestamp, timestamp)
    }
    
    func testTextEntry_SpecialCharacters() {
        // Given
        let specialAppName = "App\n\t\r\"\\/"
        let specialText = "Text with\nnewlines\tand\r\"quotes\" and emoji 🎌"
        let timestamp = Date()
        
        // When
        let entry = TextEntry(appName: specialAppName, text: specialText, timestamp: timestamp)
        
        // Then
        XCTAssertEqual(entry.appName, specialAppName)
        XCTAssertEqual(entry.text, specialText)
        XCTAssertEqual(entry.timestamp, timestamp)
    }
    
    func testTextEntry_TimestampBoundaries() {
        // Given
        let veryOldDate = Date(timeIntervalSince1970: 0) // January 1, 1970
        let veryNewDate = Date(timeIntervalSince1970: 4102444800) // January 1, 2100
        
        // When
        let oldEntry = TextEntry(appName: "OldApp", text: "Old content", timestamp: veryOldDate)
        let newEntry = TextEntry(appName: "NewApp", text: "New content", timestamp: veryNewDate)
        
        // Then
        XCTAssertEqual(oldEntry.timestamp, veryOldDate)
        XCTAssertEqual(newEntry.timestamp, veryNewDate)
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_HashCalculation() {
        let entries = (0..<1000).map { i in
            TextEntry(appName: "App\(i)", text: "Content\(i)", timestamp: Date())
        }
        
        measure {
            for entry in entries {
                _ = entry.hashValue
            }
        }
    }
    
    func testPerformance_EqualityComparison() {
        let baseEntry = TextEntry(appName: "BaseApp", text: "Base content", timestamp: Date())
        let entries = (0..<1000).map { i in
            TextEntry(appName: "App\(i)", text: "Content\(i)", timestamp: Date())
        }
        
        measure {
            for entry in entries {
                _ = (baseEntry == entry)
            }
        }
    }
    
    func testPerformance_JSONSerialization() {
        let entries = (0..<100).map { i in
            TextEntry(appName: "App\(i)", text: "Content with some longer text \(i)", timestamp: Date())
        }
        
        measure {
            for entry in entries {
                do {
                    let data = try JSONEncoder().encode(entry)
                    _ = try JSONDecoder().decode(TextEntry.self, from: data)
                } catch {
                    XCTFail("JSON serialization failed: \(error)")
                }
            }
        }
    }
    
    func testPerformance_SetOperations() {
        let entries = (0..<1000).map { i in
            TextEntry(appName: "App\(i % 100)", text: "Content\(i % 50)", timestamp: Date())
        }
        
        measure {
            var entrySet: Set<TextEntry> = []
            for entry in entries {
                entrySet.insert(entry)
            }
            
            for entry in entries {
                _ = entrySet.contains(entry)
            }
        }
    }
}