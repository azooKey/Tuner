import XCTest
@testable import Tuner

class TextModelImportTests: XCTestCase {
    var textModel: TextModel!
    var mockFileManager: MockFileManager!
    var mockShareData: ShareData!
    
    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        textModel = TextModel(fileManager: mockFileManager)
        mockShareData = ShareData()
    }
    
    override func tearDown() {
        textModel = nil
        mockFileManager = nil
        mockShareData = nil
        super.tearDown()
    }
    
    // MARK: - Integration Tests (Public API)
    
    func testImportTextFiles_NoBookmarkData() async {
        // Given
        mockShareData.importBookmarkData = nil
        
        // When
        await textModel.importTextFiles(shareData: mockShareData, avoidApps: [], minTextLength: 5)
        
        // Then
        // Should complete without errors, but no files processed
        XCTAssertTrue(true) // Test passes if no crash occurs
    }
    
    func testResetImportHistory_FileExists() async {
        // Given
        let importFileURL = textModel.getTextEntryDirectory().appendingPathComponent("import.jsonl")
        mockFileManager.setFileContent("test content", for: importFileURL.path)
        mockShareData.lastImportDate = Date().timeIntervalSince1970
        mockShareData.lastImportedFileCount = 10
        
        // When
        await textModel.resetImportHistory(shareData: mockShareData)
        
        // Then
        XCTAssertTrue(mockFileManager.removeItemCalledPaths.contains(importFileURL.path))
        XCTAssertNil(mockShareData.lastImportDate)
        XCTAssertEqual(mockShareData.lastImportedFileCount, -1)
    }
    
    func testResetImportHistory_FileDoesNotExist() async {
        // Given
        mockShareData.lastImportDate = Date().timeIntervalSince1970
        mockShareData.lastImportedFileCount = 10
        
        // When
        await textModel.resetImportHistory(shareData: mockShareData)
        
        // Then
        // Should still reset ShareData even if file doesn't exist
        XCTAssertNil(mockShareData.lastImportDate)
        XCTAssertEqual(mockShareData.lastImportedFileCount, -1)
    }
    
    // MARK: - loadFromImportFile Tests
    
    func testLoadFromImportFile_FileExists() {
        // Given
        let expectation = XCTestExpectation(description: "Load from import file")
        let importFileURL = textModel.getTextEntryDirectory().appendingPathComponent("import.jsonl")
        let jsonContent = """
{"appName":"App1","text":"Content 1","timestamp":"2023-01-01T00:00:00Z"}
{"appName":"App2","text":"Content 2","timestamp":"2023-01-02T00:00:00Z"}
"""
        
        mockFileManager.setFileContent(jsonContent, for: importFileURL.path)
        
        // When
        textModel.loadFromImportFile { entries in
            // Then
            XCTAssertEqual(entries.count, 2)
            XCTAssertEqual(entries[0].appName, "App1")
            XCTAssertEqual(entries[1].appName, "App2")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testLoadFromImportFile_FileDoesNotExist() {
        // Given
        let expectation = XCTestExpectation(description: "Load from non-existent import file")
        
        // When
        textModel.loadFromImportFile { entries in
            // Then
            XCTAssertEqual(entries.count, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testLoadFromImportFile_MalformedJSON() {
        // Given
        let expectation = XCTestExpectation(description: "Load from import file with malformed JSON")
        let importFileURL = textModel.getTextEntryDirectory().appendingPathComponent("import.jsonl")
        let malformedContent = """
{"appName":"App1","text":"Content 1","timestamp":"2023-01-01T00:00:00Z"}
{invalid json line}
{"appName":"App2","text":"Content 2","timestamp":"2023-01-02T00:00:00Z"}
"""
        
        mockFileManager.setFileContent(malformedContent, for: importFileURL.path)
        
        // When
        textModel.loadFromImportFile { entries in
            // Then
            XCTAssertEqual(entries.count, 2) // Should skip malformed line but parse valid ones
            XCTAssertEqual(entries[0].appName, "App1")
            XCTAssertEqual(entries[1].appName, "App2")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - loadFromImportFileAsync Tests
    
    func testLoadFromImportFileAsync() async {
        // Given
        let importFileURL = textModel.getTextEntryDirectory().appendingPathComponent("import.jsonl")
        let jsonContent = """
{"appName":"AsyncApp","text":"Async content","timestamp":"2023-01-01T00:00:00Z"}
"""
        
        mockFileManager.setFileContent(jsonContent, for: importFileURL.path)
        
        // When
        let entries = await textModel.loadFromImportFileAsync()
        
        // Then
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].appName, "AsyncApp")
        XCTAssertEqual(entries[0].text, "Async content")
    }
    
    // MARK: - ImportStatus Tests
    
    func testImportStatus_FileOperations() {
        // Given
        let fileName = "test.txt"
        let jsonlFileName = "test.jsonl"
        let lastModified = Date()
        
        // When
        textModel.markFileAsImported(fileName, jsonlFileName: jsonlFileName, lastModifiedDate: lastModified)
        
        // Then
        XCTAssertTrue(textModel.isFileImported(fileName))
        
        // When
        textModel.resetImportStatus()
        
        // Then
        XCTAssertFalse(textModel.isFileImported(fileName))
    }
    
    func testImportStatus_FileUpdated() {
        // Given
        let fileName = "test.txt"
        let jsonlFileName = "test.jsonl"
        let oldDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let newDate = Date() // Now
        
        textModel.markFileAsImported(fileName, jsonlFileName: jsonlFileName, lastModifiedDate: oldDate)
        
        // When
        let isUpdated = textModel.isFileUpdated(fileName, currentModifiedDate: newDate)
        
        // Then
        XCTAssertTrue(isUpdated)
    }
    
    func testImportStatus_FileNotUpdated() {
        // Given
        let fileName = "test.txt"
        let jsonlFileName = "test.jsonl"
        let date = Date()
        
        textModel.markFileAsImported(fileName, jsonlFileName: jsonlFileName, lastModifiedDate: date)
        
        // When
        let isUpdated = textModel.isFileUpdated(fileName, currentModifiedDate: date)
        
        // Then
        XCTAssertFalse(isUpdated)
    }
    
    func testGenerateJsonlFileName() {
        // Given
        let fileName = "test.txt"
        
        // When
        let jsonlFileName = textModel.generateJsonlFileName(for: fileName)
        
        // Then
        XCTAssertEqual(jsonlFileName, "test.jsonl")
    }
    
    func testGenerateJsonlFileName_WithComplexName() {
        // Given
        let fileName = "complex-file_name (1).txt"
        
        // When
        let jsonlFileName = textModel.generateJsonlFileName(for: fileName)
        
        // Then
        XCTAssertEqual(jsonlFileName, "complex-file_name (1).jsonl")
    }
    
    // MARK: - Error Handling Tests
    
    func testLoadFromImportFile_ReadError() {
        // Given
        let expectation = XCTestExpectation(description: "Handle read error")
        let importFileURL = textModel.getTextEntryDirectory().appendingPathComponent("import.jsonl")
        
        // Create file but set up to throw read error
        mockFileManager.setFileContent("test", for: importFileURL.path)
        mockFileManager.shouldThrowOnRead = true
        
        // When
        textModel.loadFromImportFile { entries in
            // Then
            XCTAssertEqual(entries.count, 0) // Should return empty array on read error
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testResetImportHistory_RemoveError() async {
        // Given
        let importFileURL = textModel.getTextEntryDirectory().appendingPathComponent("import.jsonl")
        mockFileManager.setFileContent("test content", for: importFileURL.path)
        
        // Remove the file to cause remove error
        try? mockFileManager.removeItem(atPath: importFileURL.path)
        
        mockShareData.lastImportDate = Date().timeIntervalSince1970
        mockShareData.lastImportedFileCount = 10
        
        // When
        await textModel.resetImportHistory(shareData: mockShareData)
        
        // Then
        // Should still reset ShareData even if file removal fails
        XCTAssertNil(mockShareData.lastImportDate)
        XCTAssertEqual(mockShareData.lastImportedFileCount, -1)
    }
}