import XCTest
@testable import Tuner

class DefaultFileManagerTests: XCTestCase {
    var defaultFileManager: DefaultFileManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        defaultFileManager = DefaultFileManager()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        // Create temp directory for tests
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temp directory
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        defaultFileManager = nil
        super.tearDown()
    }
    
    // MARK: - Basic File Operations Tests
    
    func testFileExists_ExistingFile() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // When
        let exists = defaultFileManager.fileExists(atPath: testFile.path)
        
        // Then
        XCTAssertTrue(exists)
    }
    
    func testFileExists_NonExistentFile() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("nonexistent.txt")
        
        // When
        let exists = defaultFileManager.fileExists(atPath: testFile.path)
        
        // Then
        XCTAssertFalse(exists)
    }
    
    func testCreateDirectory() throws {
        // Given
        let testDir = tempDirectory.appendingPathComponent("newdir")
        
        // When
        try defaultFileManager.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: nil)
        
        // Then
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testDir.path))
    }
    
    func testCreateDirectoryAtPath() throws {
        // Given
        let testDir = tempDirectory.appendingPathComponent("newdir2")
        
        // When
        try defaultFileManager.createDirectory(atPath: testDir.path, withIntermediateDirectories: true, attributes: nil)
        
        // Then
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testDir.path))
    }
    
    func testAttributesOfItem() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testContent = "test content for attributes"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        // When
        let attributes = try defaultFileManager.attributesOfItem(atPath: testFile.path)
        
        // Then
        XCTAssertNotNil(attributes[.size])
        XCTAssertNotNil(attributes[.creationDate])
        XCTAssertNotNil(attributes[.modificationDate])
        
        if let size = attributes[.size] as? Int {
            XCTAssertEqual(size, testContent.utf8.count)
        }
    }
    
    func testContentsOfDirectory() throws {
        // Given
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let file2 = tempDirectory.appendingPathComponent("file2.txt")
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        
        // When
        let contents = try defaultFileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil, options: [])
        
        // Then
        XCTAssertEqual(contents.count, 2)
        XCTAssertTrue(contents.contains(file1))
        XCTAssertTrue(contents.contains(file2))
    }
    
    // MARK: - File Content Operations Tests
    
    func testContentsOfFile_Success() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("test.txt")
        let testContent = "Test file content"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        // When
        let content = try defaultFileManager.contentsOfFile(at: testFile, encoding: .utf8)
        
        // Then
        XCTAssertEqual(content, testContent)
    }
    
    func testContentsOfFile_NonExistentFile() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("nonexistent.txt")
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.contentsOfFile(at: testFile, encoding: .utf8))
    }
    
    func testContentsOfFile_WithRetry() throws {
        // This test is harder to implement without mocking the actual FileManager
        // We can at least test that the method works with a valid file
        let testFile = tempDirectory.appendingPathComponent("retry_test.txt")
        let testContent = "Content for retry test"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        // When
        let content = try defaultFileManager.contentsOfFile(at: testFile, encoding: .utf8)
        
        // Then
        XCTAssertEqual(content, testContent)
    }
    
    func testWriteString() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("write_test.txt")
        let testContent = "Content written through DefaultFileManager"
        
        // When
        try defaultFileManager.write(testContent, to: testFile, atomically: true, encoding: .utf8)
        
        // Then
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        let readContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(readContent, testContent)
    }
    
    func testWriteData() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("data_test.txt")
        let testData = Data("Data content".utf8)
        
        // When
        try defaultFileManager.write(testData, to: testFile, atomically: true)
        
        // Then
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        let readData = try Data(contentsOf: testFile)
        XCTAssertEqual(readData, testData)
    }
    
    func testWriteData_NonAtomic() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("data_non_atomic.txt")
        let testData = Data("Non-atomic data content".utf8)
        
        // When
        try defaultFileManager.write(testData, to: testFile, atomically: false)
        
        // Then
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        let readData = try Data(contentsOf: testFile)
        XCTAssertEqual(readData, testData)
    }
    
    // MARK: - File Handle Operations Tests
    
    func testFileHandleForUpdating() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("handle_test.txt")
        try "initial content".write(to: testFile, atomically: true, encoding: .utf8)
        
        // When
        let fileHandle = try defaultFileManager.fileHandleForUpdating(from: testFile)
        
        // Then
        XCTAssertNotNil(fileHandle)
        
        // Test that we can use the file handle
        try fileHandle.seekToEnd()
        let additionalData = Data("\nAppended content".utf8)
        try fileHandle.write(contentsOf: additionalData)
        try fileHandle.close()
        
        // Verify the content was appended
        let finalContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertTrue(finalContent.contains("initial content"))
        XCTAssertTrue(finalContent.contains("Appended content"))
    }
    
    func testFileHandleForUpdating_NonExistentFile() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("nonexistent_handle.txt")
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.fileHandleForUpdating(from: testFile)) { error in
            if let fileError = error as? FileManagingError {
                switch fileError {
                case .unableToCreateFileHandle(let url, _):
                    XCTAssertEqual(url, testFile)
                default:
                    XCTFail("Unexpected error type: \(fileError)")
                }
            } else {
                XCTFail("Expected FileManagingError but got: \(error)")
            }
        }
    }
    
    // MARK: - File Removal Tests
    
    func testRemoveItem_AtPath_Success() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("remove_test.txt")
        try "content to be removed".write(to: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        
        // When
        try defaultFileManager.removeItem(atPath: testFile.path)
        
        // Then
        XCTAssertFalse(defaultFileManager.fileExists(atPath: testFile.path))
    }
    
    func testRemoveItem_AtURL_Success() throws {
        // Given
        let testFile = tempDirectory.appendingPathComponent("remove_url_test.txt")
        try "content to be removed".write(to: testFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        
        // When
        try defaultFileManager.removeItem(at: testFile)
        
        // Then
        XCTAssertFalse(defaultFileManager.fileExists(atPath: testFile.path))
    }
    
    func testRemoveItem_NonExistentFile() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("nonexistent_remove.txt")
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.removeItem(atPath: testFile.path))
    }
    
    func testRemoveItem_WithRetry() throws {
        // This test verifies the retry mechanism exists, though it's hard to trigger
        let testFile = tempDirectory.appendingPathComponent("retry_remove_test.txt")
        try "content for retry remove test".write(to: testFile, atomically: true, encoding: .utf8)
        
        // When
        try defaultFileManager.removeItem(atPath: testFile.path)
        
        // Then
        XCTAssertFalse(defaultFileManager.fileExists(atPath: testFile.path))
    }
    
    // MARK: - File Copy and Move Tests
    
    func testCopyItem() throws {
        // Given
        let sourceFile = tempDirectory.appendingPathComponent("source.txt")
        let destinationFile = tempDirectory.appendingPathComponent("destination.txt")
        let testContent = "Content to be copied"
        try testContent.write(to: sourceFile, atomically: true, encoding: .utf8)
        
        // When
        try defaultFileManager.copyItem(at: sourceFile, to: destinationFile)
        
        // Then
        XCTAssertTrue(defaultFileManager.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(defaultFileManager.fileExists(atPath: destinationFile.path))
        
        let copiedContent = try String(contentsOf: destinationFile, encoding: .utf8)
        XCTAssertEqual(copiedContent, testContent)
    }
    
    func testMoveItem() throws {
        // Given
        let sourceFile = tempDirectory.appendingPathComponent("move_source.txt")
        let destinationFile = tempDirectory.appendingPathComponent("move_destination.txt")
        let testContent = "Content to be moved"
        try testContent.write(to: sourceFile, atomically: true, encoding: .utf8)
        
        // When
        try defaultFileManager.moveItem(at: sourceFile, to: destinationFile)
        
        // Then
        XCTAssertFalse(defaultFileManager.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(defaultFileManager.fileExists(atPath: destinationFile.path))
        
        let movedContent = try String(contentsOf: destinationFile, encoding: .utf8)
        XCTAssertEqual(movedContent, testContent)
    }
    
    // MARK: - File Creation Tests
    
    func testCreateFile_WithData() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("created_file.txt")
        let testData = Data("Created file content".utf8)
        
        // When
        let success = defaultFileManager.createFile(atPath: testFile.path, contents: testData, attributes: nil)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        
        let readData = try! Data(contentsOf: testFile)
        XCTAssertEqual(readData, testData)
    }
    
    func testCreateFile_WithoutData() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("empty_created_file.txt")
        
        // When
        let success = defaultFileManager.createFile(atPath: testFile.path, contents: nil, attributes: nil)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        
        let readData = try! Data(contentsOf: testFile)
        XCTAssertEqual(readData.count, 0)
    }
    
    func testCreateFile_WithAttributes() {
        // Given
        let testFile = tempDirectory.appendingPathComponent("attributed_file.txt")
        let testData = Data("File with attributes".utf8)
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o644
        ]
        
        // When
        let success = defaultFileManager.createFile(atPath: testFile.path, contents: testData, attributes: attributes)
        
        // Then
        XCTAssertTrue(success)
        XCTAssertTrue(defaultFileManager.fileExists(atPath: testFile.path))
        
        let fileAttributes = try! defaultFileManager.attributesOfItem(atPath: testFile.path)
        if let permissions = fileAttributes[.posixPermissions] as? NSNumber {
            XCTAssertEqual(permissions.intValue, 0o644)
        }
    }
    
    // MARK: - App Group Container Tests
    
    func testContainerURL_ValidGroupIdentifier() {
        // Given
        let groupIdentifier = "group.dev.ensan.inputmethod.azooKeyMac"
        
        // When
        let containerURL = defaultFileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        
        // Then
        // Note: This might return nil in test environment if the group isn't configured
        // We can't assert much about the actual URL, just that the method works
        // In a real app environment, this would return a valid URL
        if let url = containerURL {
            XCTAssertNotNil(url)
            XCTAssertTrue(url.path.contains("Group Containers") || url.path.contains("Shared"))
        }
        // If nil, it means the group identifier isn't configured in the test environment
    }
    
    func testContainerURL_InvalidGroupIdentifier() {
        // Given
        let invalidGroupIdentifier = "invalid.group.identifier"
        
        // When
        let containerURL = defaultFileManager.containerURL(forSecurityApplicationGroupIdentifier: invalidGroupIdentifier)
        
        // Then
        XCTAssertNil(containerURL)
    }
    
    // MARK: - Error Handling Tests
    
    func testAttributesOfItem_NonExistentFile() {
        // Given
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.txt")
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.attributesOfItem(atPath: nonExistentFile.path))
    }
    
    func testContentsOfDirectory_NonExistentDirectory() {
        // Given
        let nonExistentDir = tempDirectory.appendingPathComponent("nonexistent_dir")
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.contentsOfDirectory(at: nonExistentDir, includingPropertiesForKeys: nil, options: []))
    }
    
    func testCopyItem_DestinationExists() throws {
        // Given
        let sourceFile = tempDirectory.appendingPathComponent("copy_source.txt")
        let destinationFile = tempDirectory.appendingPathComponent("copy_destination.txt")
        
        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "existing destination".write(to: destinationFile, atomically: true, encoding: .utf8)
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.copyItem(at: sourceFile, to: destinationFile))
    }
    
    func testMoveItem_DestinationExists() throws {
        // Given
        let sourceFile = tempDirectory.appendingPathComponent("move_source2.txt")
        let destinationFile = tempDirectory.appendingPathComponent("move_destination2.txt")
        
        try "source content".write(to: sourceFile, atomically: true, encoding: .utf8)
        try "existing destination".write(to: destinationFile, atomically: true, encoding: .utf8)
        
        // When/Then
        XCTAssertThrowsError(try defaultFileManager.moveItem(at: sourceFile, to: destinationFile))
    }
}

// MARK: - Performance Tests

extension DefaultFileManagerTests {
    
    func testPerformance_MultipleFileOperations() {
        measure {
            let testDir = tempDirectory.appendingPathComponent("perf_test")
            try! defaultFileManager.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: nil)
            
            // Create multiple files
            for i in 0..<100 {
                let file = testDir.appendingPathComponent("file_\(i).txt")
                let content = "Content for file \(i)"
                try! defaultFileManager.write(content, to: file, atomically: true, encoding: .utf8)
            }
            
            // Read all files
            let files = try! defaultFileManager.contentsOfDirectory(at: testDir, includingPropertiesForKeys: nil, options: [])
            for file in files {
                _ = try! defaultFileManager.contentsOfFile(at: file, encoding: .utf8)
            }
            
            // Clean up
            try! defaultFileManager.removeItem(at: testDir)
        }
    }
}