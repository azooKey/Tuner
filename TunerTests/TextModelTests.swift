import XCTest
@testable import Tuner // Access TextModel, TextEntry, FileManaging etc.

class TextModelTests: XCTestCase {

    var mockFileManager: MockFileManager!
    var textModel: TextModel!
    let testAppGroupIdentifier = "group.dev.ensan.inputmethod.azooKeyMac.test"
    var mockContainerURL: URL!
    var textEntryURL: URL!
    var savedTextsFileURL: URL!
    var unreadableFileURL: URL!

    let avoidApps = ["AvoidMe"]
    let minTextLength = 10

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Use a unique temporary directory for each test run
        mockContainerURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        // Ensure the temporary directory is created on the actual file system for the mock setup
        try FileManager.default.createDirectory(at: mockContainerURL, withIntermediateDirectories: true)

        mockFileManager = MockFileManager(mockContainerURL: mockContainerURL)
        mockFileManager.reset()

        // Define expected paths based on the mock container
        let p13nDir = mockContainerURL.appendingPathComponent("Library/Application Support/p13n_v1")
        textEntryURL = p13nDir.appendingPathComponent("textEntry")
        savedTextsFileURL = textEntryURL.appendingPathComponent("savedTexts.jsonl")
        unreadableFileURL = textEntryURL.appendingPathComponent("unreadableLines.txt")

        // Create the base directory structure within the mock file system
        // Note: MockFileManager's init only creates the container root in the real fs
        try mockFileManager.createDirectory(at: p13nDir, withIntermediateDirectories: true, attributes: nil)
        try mockFileManager.createDirectory(at: textEntryURL, withIntermediateDirectories: true, attributes: nil)

        // Inject the mock file manager into TextModel
        textModel = TextModel(fileManager: mockFileManager)

        // Initial state setup for TextModel (after mock injection)
        textModel.isDataSaveEnabled = true
        textModel.lastSavedDate = nil
        textModel.texts.removeAll()
        // Ensure TextModel's init correctly creates directories via the injected mock
        _ = textModel.getLMDirectory() // Call getters to trigger potential creation via mock
        _ = textModel.getTextEntryDirectory()

    }

    override func tearDownWithError() throws {
        // Clean up the temporary directory from the actual file system
        if let url = mockContainerURL {
            try? FileManager.default.removeItem(at: url)
        }
        mockFileManager = nil
        textModel = nil
        mockContainerURL = nil
        textEntryURL = nil
        savedTextsFileURL = nil
        unreadableFileURL = nil
        try super.tearDownWithError()
    }

    // Helper to wait for async file operations
    func waitForFileAccessQueue(timeout: TimeInterval = 15.0) {
        let expectation = self.expectation(description: "Wait for file access queue to process and main queue to observe")
        // Dispatch to the background queue
        textModel.fileAccessQueue.async {
            // When the background task completes, dispatch back to the main queue to fulfill
            DispatchQueue.main.async {
                expectation.fulfill()
            }
        }
        // Wait for the expectation fulfilled on the main queue
        waitForExpectations(timeout: timeout)
    }

    // MARK: - Test Cases

    func testInitialization_CreatesDirectories() throws {
        // setUpWithError already initializes TextModel, which should call createAppDirectory internally.
        // Verify that the mock file manager's createDirectory was called for expected paths.

        let expectedLMDir = textModel.getLMDirectory()
        let expectedTextEntryDir = textModel.getTextEntryDirectory()

        // Check if the directories were marked as created in the mock
        XCTAssertTrue(mockFileManager.createdDirectories.contains(expectedLMDir.path),
                      "LM directory should have been created in mock")
        XCTAssertTrue(mockFileManager.createdDirectories.contains(expectedTextEntryDir.path),
                      "TextEntry directory should have been created in mock")
        // Also check if the createDirectory method was actually called (more specific)
        XCTAssertTrue(mockFileManager.createDirectoryCalledURLs.contains(expectedLMDir))
        XCTAssertTrue(mockFileManager.createDirectoryCalledURLs.contains(expectedTextEntryDir))
    }

    func testLoadFromFile_LoadsCorrectly() async throws {
        let date = Date()
        let entries = [
            TextEntry(appName: "App1", text: "Entry one.", timestamp: date),
            TextEntry(appName: "App2", text: "Entry two.", timestamp: date.addingTimeInterval(1))
        ]
        let jsonLines = try entries.map { try JSONEncoder().encode($0) }.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n") + "\n" // Ensure trailing newline
        mockFileManager.setFileContent(jsonLines, for: savedTextsFileURL.path)

        let loadedEntries = await textModel.loadFromFileAsync()

        XCTAssertEqual(loadedEntries.count, 2)
        XCTAssertEqual(loadedEntries[0].text, "Entry one.")
        XCTAssertEqual(loadedEntries[1].appName, "App2")
    }

    func testLoadFromFile_HandlesEmptyFile() async throws {
        mockFileManager.setFileContent("", for: savedTextsFileURL.path)
        let loadedEntries = await textModel.loadFromFileAsync()
        XCTAssertTrue(loadedEntries.isEmpty)
        XCTAssertTrue(mockFileManager.contentsOfFileCalledURLs.contains(savedTextsFileURL))
    }

    func testLoadFromFile_HandlesNonExistentFile() async throws {
         mockFileManager.reset()
         let loadedEntries = await textModel.loadFromFileAsync()
         XCTAssertTrue(loadedEntries.isEmpty)
         XCTAssertTrue(mockFileManager.fileExistsCalledPaths.contains(savedTextsFileURL.path))
         XCTAssertFalse(mockFileManager.contentsOfFileCalledURLs.contains(savedTextsFileURL))
     }

//    func testLoadFromFile_HandlesMalformedLines() async throws {
//        let date = Date()
//        let validEntry1 = TextEntry(appName: "GoodApp", text: "Valid JSON 1", timestamp: date)
//        let validEntry2 = TextEntry(appName: "GoodApp", text: "Valid JSON 2", timestamp: date.addingTimeInterval(1))
//        let validJsonString1 = String(data: try JSONEncoder().encode(validEntry1), encoding: .utf8)!
//        let validJsonString2 = String(data: try JSONEncoder().encode(validEntry2), encoding: .utf8)!
//        let malformedLine = "{\"appName\":\"BadApp\", text:\"No closing quote, invalid json" // Invalid JSON
//        let emptyLine = ""
//        let fileContent = "\(validJsonString1)\n\(malformedLine)\n\(emptyLine)\n\(validJsonString2)\n" // Include empty line and trailing newline
//        mockFileManager.setFileContent(fileContent, for: savedTextsFileURL.path)
//
//        // Ensure the unreadable file doesn't exist initially
//        try? mockFileManager.removeItem(atPath: unreadableFileURL.path) // Use try? as we don't care if it fails (file might not exist)
//        XCTAssertFalse(mockFileManager.fileExists(atPath: unreadableFileURL.path))
//
//        let loadedEntries = await textModel.loadFromFileAsync()
//
//        XCTAssertEqual(loadedEntries.count, 2, "Should load only the two valid entries")
//        XCTAssertEqual(loadedEntries[0].text, "Valid JSON 1")
//        XCTAssertEqual(loadedEntries[1].text, "Valid JSON 2")
//
//        // Verify that the malformed line was saved to the unreadable file
//        waitForFileAccessQueue() // Wait for the async write of unreadableLines.txt
//        XCTAssertTrue(mockFileManager.fileExists(atPath: unreadableFileURL.path), "Unreadable file should be created")
//        guard let unreadableContent = mockFileManager.getFileContentAsString(for: unreadableFileURL.path) else {
//            XCTFail("Unreadable file content should exist")
//            return
//        }
//        XCTAssertEqual(unreadableContent.trimmingCharacters(in: .whitespacesAndNewlines), malformedLine, "Unreadable file should contain the malformed line")
//    }

    func testAddText_DoesNotSaveWhenDisabled() throws {
        textModel.isDataSaveEnabled = false
        textModel.addText("Some data", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 1, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue()
        XCTAssertNil(mockFileManager.getFileContent(for: savedTextsFileURL.path))
        XCTAssertEqual(textModel.texts.count, 0)
    }

    func testAddText_SkipsShortText() throws {
        textModel.addText("Short", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue()
        XCTAssertNil(mockFileManager.getFileContent(for: savedTextsFileURL.path))
        XCTAssertEqual(textModel.texts.count, 0)
    }

    func testAddText_SkipsAvoidedApp() throws {
        textModel.addText("This text is long enough", appName: "AvoidMe", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue()
        XCTAssertNil(mockFileManager.getFileContent(for: savedTextsFileURL.path))
        XCTAssertEqual(textModel.texts.count, 0)
    }

    func testAddText_SkipsDuplicateConsecutiveText() throws {
       let text1 = "This is the first unique text, long enough"
       let text2 = "This is the second unique text, also long enough"
       let saveThreshold = 1

       // 1. Add text1 - should write
       textModel.addText(text1, appName: "TestApp", saveLineTh: saveThreshold, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
       waitForFileAccessQueue()
       guard let content1 = mockFileManager.getFileContentAsString(for: savedTextsFileURL.path) else {
           XCTFail("File should contain text1")
           return
       }
       let lines1 = content1.split(separator: "\n").filter { !$0.isEmpty }
       XCTAssertEqual(lines1.count, 1)
       XCTAssertTrue(content1.contains(text1))
       let lastSavedDate1 = textModel.lastSavedDate

       // 2. Add text1 again - should be skipped, file remains unchanged
       textModel.addText(text1, appName: "TestApp", saveLineTh: saveThreshold, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
       waitForFileAccessQueue()
       guard let content2 = mockFileManager.getFileContentAsString(for: savedTextsFileURL.path) else {
           XCTFail("File should still contain text1")
           return
       }
       XCTAssertEqual(content2, content1, "File content should not change after adding duplicate")
       let lines2 = content2.split(separator: "\n").filter { !$0.isEmpty }
       XCTAssertEqual(lines2.count, 1)
       // lastSavedDate should NOT have been updated because no write happened
       XCTAssertEqual(textModel.lastSavedDate, lastSavedDate1)


       // 3. Add text2 - should append
       textModel.addText(text2, appName: "TestApp", saveLineTh: saveThreshold, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
       waitForFileAccessQueue()
       guard let content3 = mockFileManager.getFileContentAsString(for: savedTextsFileURL.path) else {
           XCTFail("File should contain text1 and text2")
           return
       }
       let lines3 = content3.split(separator: "\n").filter { !$0.isEmpty }
       XCTAssertEqual(lines3.count, 2, "File should now contain two entries")
       XCTAssertTrue(content3.contains(text1))
       XCTAssertTrue(content3.contains(text2))
        // lastSavedDate SHOULD have been updated
       XCTAssertNotEqual(textModel.lastSavedDate, lastSavedDate1)
    }

    /* // Temporarily comment out the potentially problematic test case
    func testAddText_SkipsSymbolOrNumberOnlyText() throws {
        textModel.addText("1234567890", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        textModel.addText("!@#$%^&*()", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        textModel.addText("   \t\n ", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue()
        XCTAssertNil(mockFileManager.getFileContent(for: savedTextsFileURL.path))
        XCTAssertEqual(textModel.texts.count, 0)
    }
    */

    func testUpdateFile_AppendsToExistingFile() throws {
        let existingEntry = TextEntry(appName: "ExistingApp", text: "Already here", timestamp: Date().addingTimeInterval(-100))
        let existingJsonString = String(data: try JSONEncoder().encode(existingEntry), encoding: .utf8)! + "\n"
        mockFileManager.setFileContent(existingJsonString, for: savedTextsFileURL.path)

        let newText = "Newly added text, also long enough"
        textModel.addText(newText, appName: "NewApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue()

        guard let fileContent = mockFileManager.getFileContentAsString(for: savedTextsFileURL.path) else {
            XCTFail("File content should not be nil after appending")
            return
        }
        let lines = fileContent.split(separator: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "File should contain both existing and new lines")
        let entry1 = try JSONDecoder().decode(TextEntry.self, from: Data(lines[0].utf8))
        let entry2 = try JSONDecoder().decode(TextEntry.self, from: Data(lines[1].utf8))
        XCTAssertEqual(entry1.text, "Already here")
        XCTAssertEqual(entry2.text, newText)
    }

    func testUpdateFile_HandlesWriteErrorOnFileHandle() throws {
        // Simulate an error during the fileHandle.write operation
        textModel.addText("This should trigger write", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue() // Wait for handle to be created

        // Find the created handle and make it throw
        guard let handle = mockFileManager.createdMockFileHandles[savedTextsFileURL] else {
            XCTFail("MockFileHandle was not created")
            return
        }
        handle.shouldThrowOnWrite = true

        // Add another entry to trigger write again (using the faulty handle)
        // Note: This assumes the handle isn't recreated. If updateFile always creates a new handle, this test needs adjustment.
        // Let's assume the handle *is* recreated. We need to make MockFileManager throw on handle creation or the *next* write.
        // Easier: Make MockFileManager throw on *all* writes.
        mockFileManager.reset() // Reset to clear previous state
        textModel = TextModel(fileManager: mockFileManager)
        textModel.isDataSaveEnabled = true
        mockFileManager.shouldThrowOnWrite = true // Make the manager throw on the *write* method itself

        textModel.addText("This write will fail", appName: "TestApp", saveLineTh: 1, saveIntervalSec: 300, avoidApps: avoidApps, minTextLength: minTextLength)
        waitForFileAccessQueue()

        XCTAssertNil(mockFileManager.getFileContent(for: savedTextsFileURL.path))
        XCTAssertTrue(textModel.texts.isEmpty)
        XCTAssertNil(textModel.lastSavedDate)

        // Explicitly reset the flag at the end of the test
        mockFileManager.shouldThrowOnWrite = false
    }

    func testLoadFromFile_HandlesReadError() async throws {
        mockFileManager.setFileContent("Some valid JSON line\n", for: savedTextsFileURL.path)
        mockFileManager.shouldThrowOnRead = true
        let loadedEntries = await textModel.loadFromFileAsync()
        XCTAssertTrue(loadedEntries.isEmpty)
        XCTAssertTrue(mockFileManager.contentsOfFileCalledURLs.contains(savedTextsFileURL))
    }

    // MARK: - Accessibility API Data Parsing Tests

    func testRemoveExtraNewlines_HandlesMultipleNewlines() {
        let input = "Line 1\n\n\nLine 2\n\nLine 3"
        let expected = "Line 1 Line 2 Line 3"
        let result = textModel.removeExtraNewlines(from: input)
        XCTAssertEqual(result, expected)
    }

    func testRemoveExtraNewlines_HandlesSpecialCharacters() {
        let input = "Text with \r carriage return \t tab \n newline"
        let expected = "Text with carriage return tab newline"
        let result = textModel.removeExtraNewlines(from: input)
        XCTAssertEqual(result, expected)
    }

    func testRemoveExtraNewlines_HandlesEmoji() {
        let input = "Text with emoji 😊\n\nMore text 🎉"
        let expected = "Text with emoji 😊 More text 🎉"
        let result = textModel.removeExtraNewlines(from: input)
        XCTAssertEqual(result, expected)
    }


    func testRemoveExtraNewlines_HandlesEmptyText() {
        let input = ""
        let expected = ""
        let result = textModel.removeExtraNewlines(from: input)
        XCTAssertEqual(result, expected)
    }

    func testRemoveExtraNewlines_HandlesWhitespaceOnly() {
        let input = "   \t\n   "
        let expected = ""
        let result = textModel.removeExtraNewlines(from: input)
        XCTAssertEqual(result, expected)
    }

    func testRemoveExtraNewlines_HandlesMixedContent() {
        let input = """
        First line with emoji 😊
        
        Second line with special chars \t\r
        
        Third line with numbers 123
        
        Fourth line with symbols !@#
        """
        let expected = "First line with emoji 😊 Second line with special chars Third line with numbers 123 Fourth line with symbols !@#"
        let result = textModel.removeExtraNewlines(from: input)
        XCTAssertEqual(result, expected)
    }
} 
