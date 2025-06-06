import XCTest
@testable import Tuner

class TextExtensionTests: XCTestCase {
    
    // MARK: - Character.isJapanese Tests
    
    func testIsJapanese_Hiragana() {
        // Basic hiragana characters
        XCTAssertTrue("あ".first!.isJapanese)
        XCTAssertTrue("か".first!.isJapanese)
        XCTAssertTrue("さ".first!.isJapanese)
        XCTAssertTrue("た".first!.isJapanese)
        XCTAssertTrue("な".first!.isJapanese)
        XCTAssertTrue("は".first!.isJapanese)
        XCTAssertTrue("ま".first!.isJapanese)
        XCTAssertTrue("や".first!.isJapanese)
        XCTAssertTrue("ら".first!.isJapanese)
        XCTAssertTrue("わ".first!.isJapanese)
        XCTAssertTrue("ん".first!.isJapanese)
        
        // Small hiragana characters
        XCTAssertTrue("ぁ".first!.isJapanese)
        XCTAssertTrue("ぃ".first!.isJapanese)
        XCTAssertTrue("ぅ".first!.isJapanese)
        XCTAssertTrue("ぇ".first!.isJapanese)
        XCTAssertTrue("ぉ".first!.isJapanese)
        XCTAssertTrue("っ".first!.isJapanese)
        XCTAssertTrue("ゃ".first!.isJapanese)
        XCTAssertTrue("ゅ".first!.isJapanese)
        XCTAssertTrue("ょ".first!.isJapanese)
        
        // Boundary cases - range start and end
        XCTAssertTrue("ぁ".first!.isJapanese) // U+3041 - range start
        XCTAssertTrue("ゖ".first!.isJapanese) // U+3096 - range end
    }
    
    func testIsJapanese_Katakana() {
        // Basic katakana characters
        XCTAssertTrue("ア".first!.isJapanese)
        XCTAssertTrue("カ".first!.isJapanese)
        XCTAssertTrue("サ".first!.isJapanese)
        XCTAssertTrue("タ".first!.isJapanese)
        XCTAssertTrue("ナ".first!.isJapanese)
        XCTAssertTrue("ハ".first!.isJapanese)
        XCTAssertTrue("マ".first!.isJapanese)
        XCTAssertTrue("ヤ".first!.isJapanese)
        XCTAssertTrue("ラ".first!.isJapanese)
        XCTAssertTrue("ワ".first!.isJapanese)
        XCTAssertTrue("ン".first!.isJapanese)
        
        // Small katakana characters
        XCTAssertTrue("ァ".first!.isJapanese)
        XCTAssertTrue("ィ".first!.isJapanese)
        XCTAssertTrue("ゥ".first!.isJapanese)
        XCTAssertTrue("ェ".first!.isJapanese)
        XCTAssertTrue("ォ".first!.isJapanese)
        XCTAssertTrue("ッ".first!.isJapanese)
        XCTAssertTrue("ャ".first!.isJapanese)
        XCTAssertTrue("ュ".first!.isJapanese)
        XCTAssertTrue("ョ".first!.isJapanese)
        
        // Extended katakana
        XCTAssertTrue("ヴ".first!.isJapanese)
        XCTAssertTrue("ヵ".first!.isJapanese)
        XCTAssertTrue("ヶ".first!.isJapanese)
        
        // Boundary cases
        XCTAssertTrue("ァ".first!.isJapanese) // U+30A1 - range start
        XCTAssertTrue("ヺ".first!.isJapanese) // U+30FA - range end
    }
    
    func testIsJapanese_Kanji() {
        // Common kanji characters
        XCTAssertTrue("日".first!.isJapanese)
        XCTAssertTrue("本".first!.isJapanese)
        XCTAssertTrue("語".first!.isJapanese)
        XCTAssertTrue("文".first!.isJapanese)
        XCTAssertTrue("字".first!.isJapanese)
        XCTAssertTrue("学".first!.isJapanese)
        XCTAssertTrue("校".first!.isJapanese)
        XCTAssertTrue("会".first!.isJapanese)
        XCTAssertTrue("社".first!.isJapanese)
        XCTAssertTrue("人".first!.isJapanese)
        
        // Complex kanji
        XCTAssertTrue("麻".first!.isJapanese)
        XCTAssertTrue("鬱".first!.isJapanese)
        XCTAssertTrue("薔".first!.isJapanese)
        XCTAssertTrue("薇".first!.isJapanese)
        
        // Boundary cases
        XCTAssertTrue("一".first!.isJapanese) // U+4E00 - range start
        XCTAssertTrue("龯".first!.isJapanese) // U+9FEF - range end
    }
    
    func testIsJapanese_NonJapanese() {
        // English characters
        XCTAssertFalse("a".first!.isJapanese)
        XCTAssertFalse("Z".first!.isJapanese)
        XCTAssertFalse("m".first!.isJapanese)
        
        // Numbers
        XCTAssertFalse("0".first!.isJapanese)
        XCTAssertFalse("5".first!.isJapanese)
        XCTAssertFalse("9".first!.isJapanese)
        
        // Symbols
        XCTAssertFalse("!".first!.isJapanese)
        XCTAssertFalse("@".first!.isJapanese)
        XCTAssertFalse("#".first!.isJapanese)
        XCTAssertFalse("$".first!.isJapanese)
        XCTAssertFalse("%".first!.isJapanese)
        
        // Spaces and punctuation
        XCTAssertFalse(" ".first!.isJapanese)
        XCTAssertFalse(".".first!.isJapanese)
        XCTAssertFalse(",".first!.isJapanese)
        XCTAssertFalse("?".first!.isJapanese)
        
        // Korean characters (Hangul)
        XCTAssertFalse("한".first!.isJapanese)
        XCTAssertFalse("글".first!.isJapanese)
        
        // Chinese characters outside the kanji range
        // Note: Many Chinese characters overlap with kanji, so this is limited
        
        // Emoji
        XCTAssertFalse("😀".first!.isJapanese)
        XCTAssertFalse("🎌".first!.isJapanese)
    }
    
    // MARK: - Character.isEnglish Tests
    
    func testIsEnglish_Lowercase() {
        // Test all lowercase letters
        for char in "abcdefghijklmnopqrstuvwxyz" {
            XCTAssertTrue(char.isEnglish, "Character '\(char)' should be English")
        }
        
        // Boundary cases
        XCTAssertTrue("a".first!.isEnglish) // Range start
        XCTAssertTrue("z".first!.isEnglish) // Range end
    }
    
    func testIsEnglish_Uppercase() {
        // Test all uppercase letters
        for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            XCTAssertTrue(char.isEnglish, "Character '\(char)' should be English")
        }
        
        // Boundary cases
        XCTAssertTrue("A".first!.isEnglish) // Range start
        XCTAssertTrue("Z".first!.isEnglish) // Range end
    }
    
    func testIsEnglish_NonEnglish() {
        // Numbers
        for char in "0123456789" {
            XCTAssertFalse(char.isEnglish, "Character '\(char)' should not be English")
        }
        
        // Symbols
        for char in "!@#$%^&*()_+-=[]{}|;':\",./<>?" {
            XCTAssertFalse(char.isEnglish, "Character '\(char)' should not be English")
        }
        
        // Spaces
        XCTAssertFalse(" ".first!.isEnglish)
        XCTAssertFalse("\t".first!.isEnglish)
        XCTAssertFalse("\n".first!.isEnglish)
        
        // Japanese characters
        XCTAssertFalse("あ".first!.isEnglish)
        XCTAssertFalse("ア".first!.isEnglish)
        XCTAssertFalse("日".first!.isEnglish)
        
        // Accented characters (not in basic English range)
        XCTAssertFalse("á".first!.isEnglish)
        XCTAssertFalse("é".first!.isEnglish)
        XCTAssertFalse("ñ".first!.isEnglish)
        XCTAssertFalse("ü".first!.isEnglish)
        
        // Emoji
        XCTAssertFalse("😀".first!.isEnglish)
    }
    
    // MARK: - Character.isNumber Tests
    
    func testIsNumber_ValidNumbers() {
        // Test all digits
        for char in "0123456789" {
            XCTAssertTrue(char.isNumber, "Character '\(char)' should be a number")
        }
        
        // Boundary cases
        XCTAssertTrue("0".first!.isNumber) // Range start
        XCTAssertTrue("9".first!.isNumber) // Range end
    }
    
    func testIsNumber_NonNumbers() {
        // Letters
        for char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            XCTAssertFalse(char.isNumber, "Character '\(char)' should not be a number")
        }
        
        // Symbols
        for char in "!@#$%^&*()_+-=[]{}|;':\",./<>?" {
            XCTAssertFalse(char.isNumber, "Character '\(char)' should not be a number")
        }
        
        // Spaces
        XCTAssertFalse(" ".first!.isNumber)
        XCTAssertFalse("\t".first!.isNumber)
        
        // Japanese numbers (different from ASCII digits)
        XCTAssertFalse("１".first!.isNumber) // Full-width 1
        XCTAssertFalse("２".first!.isNumber) // Full-width 2
        XCTAssertFalse("一".first!.isNumber) // Kanji 1
        XCTAssertFalse("二".first!.isNumber) // Kanji 2
        
        // Decimal point and negative sign
        XCTAssertFalse(".".first!.isNumber)
        XCTAssertFalse("-".first!.isNumber)
        XCTAssertFalse("+".first!.isNumber)
        
        // Emoji numbers
        XCTAssertFalse("1️⃣".first!.isNumber)
    }
    
    // MARK: - String.UTF16View.isSymbolOrNumber Tests
    
    func testIsSymbolOrNumber_Numbers() {
        // Single digits
        XCTAssertTrue("0".utf16.isSymbolOrNumber)
        XCTAssertTrue("1".utf16.isSymbolOrNumber)
        XCTAssertTrue("5".utf16.isSymbolOrNumber)
        XCTAssertTrue("9".utf16.isSymbolOrNumber)
        
        // Multiple digits
        XCTAssertTrue("123".utf16.isSymbolOrNumber)
        XCTAssertTrue("456789".utf16.isSymbolOrNumber)
        XCTAssertTrue("0000".utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_Symbols_Range1() {
        // Symbols from 0x0021 to 0x002F ('!' to '/')
        let symbols1 = "!\"#$%&'()*+,-./"
        for char in symbols1 {
            XCTAssertTrue(String(char).utf16.isSymbolOrNumber, "Character '\(char)' should be symbol or number")
        }
        
        // Test the whole range together
        XCTAssertTrue(symbols1.utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_Symbols_Range2() {
        // Symbols from 0x003A to 0x0040 (':' to '@')
        let symbols2 = ":;<=>?@"
        for char in symbols2 {
            XCTAssertTrue(String(char).utf16.isSymbolOrNumber, "Character '\(char)' should be symbol or number")
        }
        
        // Test the whole range together
        XCTAssertTrue(symbols2.utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_Symbols_Range3() {
        // Symbols from 0x005B to 0x0060 ('[' to '`')
        let symbols3 = "[\\]^_`"
        for char in symbols3 {
            XCTAssertTrue(String(char).utf16.isSymbolOrNumber, "Character '\(char)' should be symbol or number")
        }
        
        // Test the whole range together
        XCTAssertTrue(symbols3.utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_Symbols_Range4() {
        // Symbols from 0x007B to 0x007E ('{' to '~')
        let symbols4 = "{|}~"
        for char in symbols4 {
            XCTAssertTrue(String(char).utf16.isSymbolOrNumber, "Character '\(char)' should be symbol or number")
        }
        
        // Test the whole range together
        XCTAssertTrue(symbols4.utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_Mixed() {
        // Mixed numbers and symbols
        XCTAssertTrue("123!@#".utf16.isSymbolOrNumber)
        XCTAssertTrue("$%^456".utf16.isSymbolOrNumber)
        XCTAssertTrue("789&*()".utf16.isSymbolOrNumber)
        XCTAssertTrue("+-=[]{}|;':\",./<>?".utf16.isSymbolOrNumber)
        XCTAssertTrue("0123456789!@#$%^&*()".utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_NotSymbolOrNumber() {
        // English letters
        XCTAssertFalse("a".utf16.isSymbolOrNumber)
        XCTAssertFalse("Z".utf16.isSymbolOrNumber)
        XCTAssertFalse("Hello".utf16.isSymbolOrNumber)
        XCTAssertFalse("ABC".utf16.isSymbolOrNumber)
        XCTAssertFalse("abcDEF".utf16.isSymbolOrNumber)
        
        // Japanese characters
        XCTAssertFalse("あ".utf16.isSymbolOrNumber)
        XCTAssertFalse("ア".utf16.isSymbolOrNumber)
        XCTAssertFalse("日本".utf16.isSymbolOrNumber)
        XCTAssertFalse("カタカナ".utf16.isSymbolOrNumber)
        
        // Spaces and control characters
        XCTAssertFalse(" ".utf16.isSymbolOrNumber)
        XCTAssertFalse("\t".utf16.isSymbolOrNumber)
        XCTAssertFalse("\n".utf16.isSymbolOrNumber)
        XCTAssertFalse("\r".utf16.isSymbolOrNumber)
        
        // Unicode characters outside the defined ranges
        XCTAssertFalse("€".utf16.isSymbolOrNumber) // Euro symbol
        XCTAssertFalse("©".utf16.isSymbolOrNumber) // Copyright symbol
        XCTAssertFalse("®".utf16.isSymbolOrNumber) // Registered symbol
        XCTAssertFalse("™".utf16.isSymbolOrNumber) // Trademark symbol
        
        // Emoji
        XCTAssertFalse("😀".utf16.isSymbolOrNumber)
        XCTAssertFalse("🎉".utf16.isSymbolOrNumber)
        
        // Full-width characters
        XCTAssertFalse("１２３".utf16.isSymbolOrNumber) // Full-width numbers
        XCTAssertFalse("ａｂｃ".utf16.isSymbolOrNumber) // Full-width letters
    }
    
    func testIsSymbolOrNumber_MixedWithNonSymbols() {
        // Mixed with letters - should return false
        XCTAssertFalse("123a".utf16.isSymbolOrNumber)
        XCTAssertFalse("a123".utf16.isSymbolOrNumber)
        XCTAssertFalse("12a34".utf16.isSymbolOrNumber)
        XCTAssertFalse("!@#A".utf16.isSymbolOrNumber)
        XCTAssertFalse("A!@#".utf16.isSymbolOrNumber)
        
        // Mixed with spaces - should return false
        XCTAssertFalse("123 456".utf16.isSymbolOrNumber)
        XCTAssertFalse(" 123".utf16.isSymbolOrNumber)
        XCTAssertFalse("123 ".utf16.isSymbolOrNumber)
        XCTAssertFalse("!@# $%^".utf16.isSymbolOrNumber)
        
        // Mixed with Japanese - should return false
        XCTAssertFalse("123あ".utf16.isSymbolOrNumber)
        XCTAssertFalse("!@#日".utf16.isSymbolOrNumber)
        XCTAssertFalse("あ123".utf16.isSymbolOrNumber)
    }
    
    func testIsSymbolOrNumber_EmptyString() {
        // Empty string should return true (vacuous truth)
        XCTAssertTrue("".utf16.isSymbolOrNumber)
    }
    
    // MARK: - Edge Cases and Boundary Tests
    
    func testCharacterBoundaries() {
        // Test characters just outside the defined ranges
        
        // Just before hiragana range
        let beforeHiragana = Character(UnicodeScalar(0x3040)!) // Just before "ぁ"
        XCTAssertFalse(beforeHiragana.isJapanese)
        
        // Just after hiragana range
        let afterHiragana = Character(UnicodeScalar(0x3097)!) // Just after "ゖ"
        XCTAssertFalse(afterHiragana.isJapanese)
        
        // Just before katakana range
        let beforeKatakana = Character(UnicodeScalar(0x30A0)!) // Just before "ァ"
        XCTAssertFalse(beforeKatakana.isJapanese)
        
        // Just after katakana range
        let afterKatakana = Character(UnicodeScalar(0x30FB)!) // Just after "ヺ"
        XCTAssertFalse(afterKatakana.isJapanese)
        
        // Just before kanji range
        let beforeKanji = Character(UnicodeScalar(0x4DFF)!) // Just before "一"
        XCTAssertFalse(beforeKanji.isJapanese)
        
        // Just after kanji range
        let afterKanji = Character(UnicodeScalar(0x9FF0)!) // Just after "龯"
        XCTAssertFalse(afterKanji.isJapanese)
    }
    
    func testUTF16Boundaries() {
        // Test UTF16 values just outside the defined ranges
        
        // Just before '0' (0x002F)
        let before0 = String(Character(UnicodeScalar(0x002F)!)) // '/'
        XCTAssertTrue(before0.utf16.isSymbolOrNumber) // This is actually in range
        
        // Just after '9' (0x003A)
        let after9 = String(Character(UnicodeScalar(0x003A)!)) // ':'
        XCTAssertTrue(after9.utf16.isSymbolOrNumber) // This is actually in range
        
        // Just before '!' (0x0020)
        let beforeExclamation = String(Character(UnicodeScalar(0x0020)!)) // Space
        XCTAssertFalse(beforeExclamation.utf16.isSymbolOrNumber)
        
        // Just after '~' (0x007F)
        let afterTilde = String(Character(UnicodeScalar(0x007F)!)) // DEL character
        XCTAssertFalse(afterTilde.utf16.isSymbolOrNumber)
    }
    
    // MARK: - Performance Tests
    
    func testPerformance_CharacterClassification() {
        let testString = "これはテストです。This is a test. 123!@#$%^&*()"
        
        measure {
            for _ in 0..<1000 {
                for char in testString {
                    _ = char.isJapanese
                    _ = char.isEnglish
                    _ = char.isNumber
                }
            }
        }
    }
    
    func testPerformance_UTF16SymbolNumberCheck() {
        let testStrings = [
            "123456789",
            "!@#$%^&*()",
            "abcdefghijk",
            "あいうえおかきくけこ",
            "123!@#abc",
            "混合テストstring123!@#"
        ]
        
        measure {
            for _ in 0..<1000 {
                for string in testStrings {
                    _ = string.utf16.isSymbolOrNumber
                }
            }
        }
    }
}