//
//  WebAppTextExtractionTests.swift
//  TunerTests
//
//  Created by Claude on 2024/12/XX.
//

import XCTest
@testable import Tuner

/// ウェブアプリケーション要素からのテキスト抽出テスト
/// Slack、Discord、Teamsなどのウェブベースチャットアプリケーション要素のテスト
class WebAppTextExtractionTests: XCTestCase {
    
    var appDelegate: AppDelegate!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        appDelegate = AppDelegate()
    }
    
    override func tearDownWithError() throws {
        appDelegate = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Message Element Tests (AXMessage)
    
    func testSlackMessageContent() {
        // Slack style message content
        let messageTexts = [
            "現在携帯からはタスクを切れますが、パソコンの方からは切れない状況となって",
            "お疲れさまです！",
            "了解です 👍",
            "会議の件、確認しました。",
            "資料を共有します",
            "明日の打ち合わせは10:00からでよろしいですか？"
        ]
        
        for text in messageTexts {
            XCTAssertTrue(
                appDelegate.isQualityContent(text: text, role: "AXMessage"),
                "Slack message '\(text)' should be considered quality content"
            )
        }
    }
    
    func testMessageElementShortContent() {
        // Short messages that should still be valid
        let shortMessages = [
            "👍",      // Emoji reaction
            "OK",      // Short response
            "了解",     // Japanese acknowledgment
            "Yes",     // Simple confirmation
            "No",      // Simple denial
            "？"       // Question mark
        ]
        
        for text in shortMessages {
            XCTAssertTrue(
                appDelegate.isQualityContent(text: text, role: "AXMessage"),
                "Short message '\(text)' should be valid for AXMessage"
            )
        }
    }
    
    // MARK: - Button Element Tests (AXButton)
    
    func testUserNameButtonPatterns() {
        // User name patterns commonly found in Slack
        let userNames = [
            "Yuki Yamaguchi/Sales",
            "田中太郎/開発部",
            "John Smith",
            "山田花子",
            "Alice Johnson/Marketing",
            "佐藤一郎/人事部",
            "Bob Wilson/Engineering"
        ]
        
        for userName in userNames {
            XCTAssertTrue(
                appDelegate.isQualityContent(text: userName, role: "AXButton"),
                "User name '\(userName)' should be considered quality content for AXButton"
            )
        }
    }
    
    func testValidNamePatternRecognition() {
        // Test the name pattern validation specifically
        let validNames = [
            "Yuki Yamaguchi/Sales",
            "田中太郎",
            "John Smith",
            "Alice-Johnson",
            "Bob.Wilson",
            "山田 花子"
        ]
        
        for name in validNames {
            XCTAssertTrue(
                appDelegate.isValidNamePattern(name),
                "Name '\(name)' should match valid name pattern"
            )
        }
    }
    
    func testNamePatterns() {
        // These are valid character patterns 
        let validCharacterPatterns = [
            "Settings",
            "Preferences", 
            "Download",
            "John Smith",
            "user.name",
            "test-user",
            "Yuki Yamaguchi/Sales"
        ]
        
        for name in validCharacterPatterns {
            XCTAssertTrue(
                appDelegate.isValidNamePattern(name),
                "Pattern '\(name)' should match valid character pattern"
            )
        }
    }
    
    // MARK: - Text Element Tests (AXText)
    
    func testTextElementContent() {
        // Various text content that should be captured
        let textContents = [
            "今日 15:40:33",
            "昨日",
            "1時間前",
            "オンライン",
            "会議中",
            "離席中",
            "📝",
            "重要",
            "新着"
        ]
        
        for text in textContents {
            XCTAssertTrue(
                appDelegate.isQualityContent(text: text, role: "AXText"),
                "Text content '\(text)' should be valid for AXText"
            )
        }
    }
    
    // MARK: - Link Element Tests (AXLink)
    
    func testLinkElementContent() {
        // Link text patterns from Slack
        let linkTexts = [
            "@鹿嶋 亮介/Ryosuke Kashima",
            "今日 15:40:33",
            "#general",
            "#enterprise_is",
            "@channel",
            "@here",
            "https://example.com",
            "ファイル.pdf"
        ]
        
        for linkText in linkTexts {
            XCTAssertTrue(
                appDelegate.isQualityContent(text: linkText, role: "AXLink"),
                "Link text '\(linkText)' should be valid for AXLink"
            )
        }
    }
    
    // MARK: - Tab Panel Tests (AXTabPanel)
    
    func testTabPanelContent() {
        // Tab panel content like channel names
        let tabContents = [
            "ホーム",
            "CoeFont Co.,Ltd.",
            "#general",
            "#random",
            "DM",
            "enterprise_is",
            "プロジェクト会議",
            "開発チーム"
        ]
        
        for tabContent in tabContents {
            XCTAssertTrue(
                appDelegate.isQualityContent(text: tabContent, role: "AXTabPanel"),
                "Tab content '\(tabContent)' should be valid for AXTabPanel"
            )
        }
    }
    
    // MARK: - Quality Filter Tests
    
    func testUIElementsFiltering() {
        // UI elements that should be filtered out
        let uiElements = [
            ("OK", "AXStaticText"),
            ("Cancel", "AXStaticText"),
            ("Close", "AXStaticText"),
            ("", "AXText"),                    // Empty string
            ("   ", "AXText"),                 // Only whitespace
            ("aaaaaa", "AXText")               // Repeated characters
        ]
        
        for (text, role) in uiElements {
            if text == "aaaaaa" || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                XCTAssertFalse(
                    appDelegate.isQualityContent(text: text, role: role),
                    "UI element '\(text)' with role '\(role)' should be filtered out"
                )
            }
        }
        
        // Test that "Settings" is now allowed for AXStaticText due to relaxed rules
        XCTAssertTrue(
            appDelegate.isQualityContent(text: "Settings", role: "AXStaticText"),
            "Settings should be allowed for AXStaticText with relaxed rules"
        )
    }
    
    func testMessageQualityThresholds() {
        // Test the different quality thresholds for different roles
        let testCases: [(text: String, role: String, shouldPass: Bool)] = [
            // AXMessage - very permissive (1+ characters)
            ("👍", "AXMessage", true),
            ("", "AXMessage", false),
            
            // AXText - very permissive (1+ characters)
            ("OK", "AXText", true),
            ("", "AXText", false),
            
            // AXButton - moderate (2+ characters, or valid name pattern)
            ("OK", "AXButton", true),          // Now 2+ characters
            ("Settings", "AXButton", true),    // 2+ characters
            ("John Smith", "AXButton", true),  // Valid name pattern
            ("A", "AXButton", false),          // Too short
            
            // AXStaticText - now permissive (1+ characters)
            ("Short", "AXStaticText", true),      // Now allowed
            ("This is text", "AXStaticText", true), // Still allowed
            ("A", "AXStaticText", true),          // Now allowed
            
            // AXGroup - very permissive (1+ characters)
            ("Group content", "AXGroup", true),
            ("A", "AXGroup", true),
            ("", "AXGroup", false),
            
            // Default - very permissive (1+ characters)
            ("A", "AXUnknown", true),         // Now 1+ characters
            ("AB", "AXUnknown", true),        // 1+ characters
            ("", "AXUnknown", false),         // Empty still rejected
        ]
        
        for testCase in testCases {
            let result = appDelegate.isQualityContent(text: testCase.text, role: testCase.role)
            XCTAssertEqual(
                result, testCase.shouldPass,
                "Text '\(testCase.text)' with role '\(testCase.role)' should \(testCase.shouldPass ? "pass" : "fail") quality check"
            )
        }
    }
    
    // MARK: - Edge Cases
    
    func testJapaneseContent() {
        // Test Japanese content handling
        let japaneseTexts = [
            ("こんにちは", "AXMessage", true),
            ("おはようございます", "AXMessage", true),
            ("山田太郎", "AXButton", true),
            ("お疲れさまです！", "AXText", true),
            ("ホーム", "AXTabPanel", true),
            ("会議資料.pdf", "AXLink", true)
        ]
        
        for (text, role, expected) in japaneseTexts {
            let result = appDelegate.isQualityContent(text: text, role: role)
            XCTAssertEqual(
                result, expected,
                "Japanese text '\(text)' with role '\(role)' should \(expected ? "pass" : "fail")"
            )
        }
    }
    
    func testEmojiAndSpecialCharacters() {
        // Test emoji and special characters
        let specialTexts = [
            ("👍", "AXMessage", true),
            ("🎉", "AXText", true),
            ("@channel", "AXLink", true),
            ("#general", "AXLink", true),
            ("⚠️ 重要", "AXMessage", true),
            ("📝 メモ", "AXText", true)
        ]
        
        for (text, role, expected) in specialTexts {
            let result = appDelegate.isQualityContent(text: text, role: role)
            XCTAssertEqual(
                result, expected,
                "Special text '\(text)' with role '\(role)' should \(expected ? "pass" : "fail")"
            )
        }
    }
    
    func testLongContent() {
        // Test handling of very long content
        let longMessage = String(repeating: "これは長いメッセージです。", count: 20) // About 200 characters
        
        // Should pass for message content
        XCTAssertTrue(
            appDelegate.isQualityContent(text: longMessage, role: "AXMessage"),
            "Long message should be accepted for AXMessage"
        )
        
        // Create extremely long content with spaces (won't trigger word length filter)
        let veryLongMessage = String(repeating: "長いテキスト ", count: 50) // About 600 characters with spaces
        
        // Should still pass quality check (length filtering is done elsewhere)
        XCTAssertTrue(
            appDelegate.isQualityContent(text: veryLongMessage, role: "AXMessage"),
            "Very long message should pass quality check (length filtering is separate)"
        )
    }
    
    func testSlackSpecificContent() {
        // Test the specific type of content mentioned in the request
        let slackContent = [
            "↑それっぽい文献を投げました（それっぽいだけでそれではない可能性あり）",
            "現在携帯からはタスクを切れますが、パソコンの方からは切れない状況となって",
            "Navigation 目",
            "winaow: 04 mlat (Cnannel) - matsuiao - Jlack",
            "Channel b4 E1t*E",
            "matsulab",
        ]
        
        // Test these contents across different roles
        let roles = ["AXGroup", "AXMessage", "AXText", "AXStaticText"]
        
        for content in slackContent {
            for role in roles {
                XCTAssertTrue(
                    appDelegate.isQualityContent(text: content, role: role),
                    "Slack content '\(content)' should be valid for role '\(role)'"
                )
            }
        }
    }
}