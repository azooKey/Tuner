import XCTest
@testable import Tuner

class PrefixDeduplicationTests: XCTestCase {
    
    var mockFileManager: MockFileManager!
    var textModel: TextModel!
    var mockContainerURL: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Use a unique temporary directory for each test run
        mockContainerURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: mockContainerURL, withIntermediateDirectories: true)
        
        mockFileManager = MockFileManager(mockContainerURL: mockContainerURL)
        mockFileManager.reset()
        
        // Create the base directory structure
        let p13nDir = mockContainerURL.appendingPathComponent("Library/Application Support/p13n_v1")
        let textEntryURL = p13nDir.appendingPathComponent("textEntry")
        try mockFileManager.createDirectory(at: p13nDir, withIntermediateDirectories: true, attributes: nil)
        try mockFileManager.createDirectory(at: textEntryURL, withIntermediateDirectories: true, attributes: nil)
        
        // Inject the mock file manager into TextModel
        textModel = TextModel(fileManager: mockFileManager)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: mockContainerURL)
        try super.tearDownWithError()
    }
    
    // MARK: - Prefix Deduplication Tests
    
    func testPrefixDeduplicationKeepsLongerStrings() {
        // 90%以上の前方一致がある場合、長い文字列を残すことを確認
        let entries = [
            TextEntry(appName: "TestApp", text: "おはy", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "おはよ", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "おはよう", timestamp: Date())
        ]
        
        let (unique, duplicateCount) = textModel.testRemovePrefixDuplicates(entries: entries)
        
        print("🔍 Debug: unique.count = \(unique.count)")
        print("🔍 Debug: unique texts = \(unique.map { $0.text })")
        print("🔍 Debug: duplicateCount = \(duplicateCount)")
        
        // 実際の挙動の確認
        // 閾値0.7で3/4=0.75なので、「おはよ」と「おはy」は削除されるべき
        XCTAssertEqual(unique.count, 1, "Expected 1 unique entry but got \(unique.count). Texts: \(unique.map { $0.text })")
        XCTAssertEqual(unique.first?.text, "おはよう", "Expected 'おはよう' but got '\(unique.first?.text ?? "nil")'")
        XCTAssertEqual(duplicateCount, 2, "Expected 2 duplicates but got \(duplicateCount)")
    }
    
    func testPrefixDeduplicationWithPartialMatches() {
        // 90%未満の前方一致は削除されないことを確認
        let entries = [
            TextEntry(appName: "TestApp", text: "Hello", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hello World", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hello World from Swift", timestamp: Date())
        ]
        
        let (unique, _) = textModel.testRemovePrefixDuplicates(entries: entries)
        
        // "Hello"は"Hello World"の45%なので削除されない
        // "Hello World"は"Hello World from Swift"の50%なので削除されない
        XCTAssertEqual(unique.count, 3)
    }
    
    func testPrefixDeduplicationWith90PercentMatch() {
        // ちょうど90%の前方一致の場合
        let entries = [
            TextEntry(appName: "TestApp", text: "123456789", timestamp: Date()), // 9文字
            TextEntry(appName: "TestApp", text: "1234567890", timestamp: Date()) // 10文字
        ]
        
        let (unique, duplicateCount) = textModel.testRemovePrefixDuplicates(entries: entries)
        
        // 90%の前方一致なので短い方が削除される
        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique.first?.text, "1234567890")
        XCTAssertEqual(duplicateCount, 1)
    }
    
    func testPrefixDeduplicationAcrossDifferentApps() {
        // 異なるアプリ間では前方一致削除が行われないことを確認
        let entries = [
            TextEntry(appName: "App1", text: "おはよう", timestamp: Date()),
            TextEntry(appName: "App2", text: "おはよ", timestamp: Date()),
            TextEntry(appName: "App3", text: "おは", timestamp: Date())
        ]
        
        let (unique, duplicateCount) = textModel.testRemovePrefixDuplicates(entries: entries)
        
        // 異なるアプリなので全て残る
        XCTAssertEqual(unique.count, 3)
        XCTAssertEqual(duplicateCount, 0)
    }
    
    func testPrefixDeduplicationComplexCase() {
        // より複雑なケース：複数の前方一致グループ
        let entries = [
            TextEntry(appName: "TestApp", text: "Hello", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hello World", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hello World!", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hi", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hi there", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "Hi there!", timestamp: Date())
        ]
        
        let (unique, _) = textModel.testRemovePrefixDuplicates(entries: entries)
        
        // 各グループから最長のものが残る
        let texts = unique.map { $0.text }.sorted()
        XCTAssertTrue(texts.contains("Hello World!"))
        XCTAssertTrue(texts.contains("Hi there!"))
        // "Hello"は"Hello World!"の約45%なので残る
        XCTAssertTrue(texts.contains("Hello"))
        XCTAssertTrue(texts.contains("Hi"))
    }
    
    func testPrefixDeduplicationPerformance() {
        // パフォーマンステスト：大量のエントリでも効率的に動作することを確認
        var entries: [TextEntry] = []
        let baseTexts = ["Hello", "World", "Swift", "Programming", "Test"]
        
        // 各ベーステキストから段階的に長い文字列を生成
        for base in baseTexts {
            var text = base
            for i in 0..<10 {
                entries.append(TextEntry(appName: "TestApp", text: text, timestamp: Date()))
                text += " \(i)"
            }
        }
        
        let startTime = Date()
        let (unique, _) = textModel.testRemovePrefixDuplicates(entries: entries)
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // 各グループから最長の1つだけが残る
        XCTAssertEqual(unique.count, baseTexts.count)
        
        // 処理時間が妥当であることを確認（1秒以内）
        XCTAssertLessThan(elapsedTime, 1.0)
    }
    
    func testPrefixDeduplicationEdgeCase() {
        // エッジケース：空文字列や1文字の文字列
        let entries = [
            TextEntry(appName: "TestApp", text: "", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "a", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "ab", timestamp: Date()),
            TextEntry(appName: "TestApp", text: "abc", timestamp: Date())
        ]
        
        let (unique, _) = textModel.testRemovePrefixDuplicates(entries: entries)
        
        // 空文字列は除外され、"abc"だけが残る（"a"と"ab"は90%以上の前方一致）
        let texts = unique.map { $0.text }
        XCTAssertFalse(texts.contains(""))
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts.first, "abc")
    }
}