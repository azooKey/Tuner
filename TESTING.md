# テストガイド

このドキュメントは、Tunerアプリケーションのテストスイートに関する包括的な情報を提供します。

## 概要

Tunerプロジェクトには、コア機能、データモデル、ファイル操作、ビジネスロジックをカバーする広範囲なユニットテストが含まれています。テストスイートは、コード品質の確保、リグレッションの防止、重要なアプリケーション動作の検証を目的として設計されています。

## テスト構成

### テストターゲット
- **ターゲット名**: `TunerTests`
- **プラットフォーム**: macOS
- **テストフレームワーク**: XCTest
- **言語**: Swift

### テスト組織

テストは機能別に分けられ、別々のテストクラスで構成されています：

```
TunerTests/
├── Mocks/
│   ├── MockFileHandle.swift          # モックファイルハンドル実装
│   └── MockFileManager.swift         # テスト用モックファイルマネージャー
├── コアコンポーネントテスト/
│   ├── TextEntryTests.swift          # データモデルテスト
│   ├── ShareDataTests.swift          # 設定と状態管理
│   ├── DefaultFileManagerTests.swift # リトライロジック付きファイル操作
│   └── TextExtensionTests.swift      # 文字分類ユーティリティ
├── 機能テスト/
│   ├── TextModelTests.swift          # コアテキスト処理
│   ├── TextModelImportTests.swift    # インポート機能
│   ├── MinHashUtilsTests.swift       # 重複除去アルゴリズム
│   └── PrefixDeduplicationTests.swift # 前方一致アルゴリズム
└── 統合テスト/
    └── WebAppTextExtractionTests.swift # アクセシビリティテキスト抽出
```

## コンポーネント別テストカバレッジ

### 1. TextEntry（データモデル）
**ファイル**: `TextEntryTests.swift`  
**カバレッジ**: 包括的

#### テストカテゴリ：
- **初期化**: 様々なデータタイプでの基本オブジェクト作成
- **Codable実装**: JSONシリアライゼーション/デシリアライゼーション
- **Hashable動作**: ハッシュの一貫性と一意性
- **等価比較**: カスタム等価ロジックの検証
- **Set/Dictionary操作**: コレクション動作テスト
- **エッジケース**: Unicode内容、特殊文字、境界値
- **パフォーマンス**: ハッシュ計算、等価比較、JSON操作

#### 主要テストケース：
```swift
func testTextEntry_JSONEncodingDecoding_RoundTrip()
func testTextEntry_Hash_SameContent() 
func testTextEntry_Equality_IgnoresTimestamp()
func testTextEntry_InSet() // 重複除去動作
func testTextEntry_UnicodeContent()
```

### 2. ShareData（設定管理）
**ファイル**: `ShareDataTests.swift`  
**カバレッジ**: 包括的

#### テストカテゴリ：
- **@AppStorageプロパティ**: 永続設定の検証
- **@Publishedプロパティ**: Combineパブリッシャー動作
- **アプリ管理**: 実行中アプリの検出と除外
- **UserDefaults統合**: データ永続化テスト
- **計算プロパティ**: 派生値の計算
- **デバッグヘルパー**: 開発ユーティリティの検証

#### 主要テストケース：
```swift
func testImportBookmarkData_Persistence()
func testAvoidApps_EncodingDecoding()
func testToggleAppExclusion_AddApp()
func testUpdateRunningApps()
func testResetToDefaults() // デバッグ機能
```

### 3. DefaultFileManager（ファイル操作）
**ファイル**: `DefaultFileManagerTests.swift`  
**カバレッジ**: 包括的

#### テストカテゴリ：
- **基本ファイル操作**: 作成、読み取り、書き込み、削除
- **リトライロジック**: エラー回復メカニズム
- **アトミック操作**: データ整合性保証
- **ディレクトリ管理**: フォルダ作成と一覧取得
- **エラーハンドリング**: 優雅な失敗シナリオ
- **FileHandle操作**: 低レベルファイルアクセス
- **パフォーマンス**: 一括操作効率

#### 主要テストケース：
```swift
func testContentsOfFile_WithRetry()
func testRemoveItem_WithRetry()
func testWriteData_Atomic()
func testFileHandleForUpdating()
func testPerformance_MultipleFileOperations()
```

### 4. TextExtension（文字分類）
**ファイル**: `TextExtensionTests.swift`  
**カバレッジ**: 包括的

#### テストカテゴリ：
- **Character.isJapanese**: ひらがな、カタカナ、漢字検出
- **Character.isEnglish**: ASCII英字検証
- **Character.isNumber**: 数字分類
- **UTF16記号検出**: 特殊文字識別
- **Unicode境界**: エッジケース検証
- **パフォーマンス**: 文字分類速度

#### 主要テストケース：
```swift
func testIsJapanese_Hiragana()
func testIsJapanese_Kanji()
func testIsSymbolOrNumber_Mixed()
func testCharacterBoundaries()
func testPerformance_CharacterClassification()
```

### 5. TextModelインポート（ファイルインポート）
**ファイル**: `TextModelImportTests.swift`  
**カバレッジ**: パブリックAPI中心

#### テストカテゴリ：
- **インポート統合**: エンドツーエンドインポートテスト
- **ファイル読み込み**: JSONLファイル解析
- **インポート状態**: ファイル追跡と履歴
- **エラーハンドリング**: 優雅な失敗回復
- **データ検証**: 内容整合性チェック

#### 主要テストケース：
```swift
func testImportTextFiles_NoBookmarkData()
func testLoadFromImportFile_MalformedJSON()
func testResetImportHistory_FileExists()
func testImportStatus_FileUpdated()
```

## モックオブジェクト

### MockFileManager
`FileManaging`プロトコルの包括的なモック実装：

#### 機能：
- **インメモリファイルシステム**: 実際のファイルI/Oなし
- **コール追跡**: メソッド呼び出しの監視
- **エラーシミュレーション**: 失敗シナリオのテスト
- **状態管理**: ファイル作成/削除の追跡
- **パフォーマンステスト**: 操作回数の測定

#### 使用例：
```swift
let mockFileManager = MockFileManager()
mockFileManager.shouldThrowOnRead = true
let textModel = TextModel(fileManager: mockFileManager)
// エラーハンドリング動作をテスト
```

### MockFileHandle
低レベルファイル操作用のモック実装：

#### 機能：
- **ストリームシミュレーション**: ファイルハンドル動作の模倣
- **位置追跡**: カーソル位置管理
- **書き込み/読み取り操作**: データバッファ管理
- **エラー注入**: 失敗シナリオのテスト

## テスト実行

### コマンドライン（推奨）
```bash
# 全テスト実行
xcodebuild test -project Tuner.xcodeproj -scheme Tuner -destination 'platform=macOS'

# 特定のテストクラス実行
xcodebuild test -project Tuner.xcodeproj -scheme Tuner -destination 'platform=macOS' -only-testing:TunerTests/TextEntryTests

# 特定のテストメソッド実行
xcodebuild test -project Tuner.xcodeproj -scheme Tuner -destination 'platform=macOS' -only-testing:TunerTests/TextEntryTests/testTextEntry_Initialization
```

### Xcode IDE
1. `Tuner.xcodeproj`を開く
2. `Tuner`スキームを選択
3. `Cmd+U`で全テスト実行
4. テストナビゲーターで特定のテスト実行

### パフォーマンステスト
重要な操作のパフォーマンステストが含まれています：

```swift
func testPerformance_HashCalculation()
func testPerformance_JSONSerialization()
func testPerformance_CharacterClassification()
func testPerformance_MultipleFileOperations()
```

## テストデータ管理

### 一時ファイル
テストは競合を避けるため一時ディレクトリを使用：
```swift
override func setUp() {
    tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
}

override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
}
```

### UserDefaults分離
ShareDataテストは干渉を防ぐためUserDefaultsをクリア：
```swift
private func clearUserDefaults() {
    let keys = ["activateAccessibility", "avoidApps", ...]
    for key in keys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

## テスト品質ガイドライン

### テスト命名規則
```swift
func test[コンポーネント]_[シナリオ]_[期待結果]()
// 例：
func testTextEntry_JSONDecoding_SuccessfulParsing()
func testShareData_ToggleAppExclusion_AddsNewApp()
func testFileManager_ContentsOfFile_WithRetryOnFailure()
```

### テスト構造（Given-When-Then）
```swift
func testExample() {
    // Given - テスト条件の設定
    let input = "テストデータ"
    let expectedOutput = "期待される結果"
    
    // When - アクションの実行
    let result = systemUnderTest.process(input)
    
    // Then - 結果の検証
    XCTAssertEqual(result, expectedOutput)
}
```

### 非同期テスト
```swift
func testAsyncOperation() async {
    // async/awaitメソッド用
    let result = await textModel.loadFromImportFileAsync()
    XCTAssertNotNil(result)
}

func testCallbackOperation() {
    // コールバックベースメソッド用
    let expectation = XCTestExpectation(description: "コールバック受信")
    textModel.loadFromImportFile { entries in
        XCTAssertNotNil(entries)
        expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
}
```

## 既知のテスト制限

### 1. プライベートメソッドテスト
- パブリックAPIテストに焦点
- プライベートメソッドはパブリックインターフェース経由で間接的にテスト
- 必要に応じて`@testable import`で内部アクセス

### 2. UIテスト
- 現在のスイートはビジネスロジックに焦点
- UIコンポーネントは別のUIテストターゲットが必要
- アクセシビリティテストはデータ抽出ロジックに限定

### 3. 外部依存関係
- ファイルシステム操作は分離のためモック化
- ネットワークリクエストは適用外（ローカル専用アプリ）
- システム権限テストはテスト環境で制限

## 継続的インテグレーション

### テスト自動化
CI/CDパイプライン用：
```bash
#!/bin/bash
set -e

# クリーンビルド
xcodebuild clean -project Tuner.xcodeproj -scheme Tuner

# カバレッジ付きテスト実行
xcodebuild test -project Tuner.xcodeproj -scheme Tuner \
    -destination 'platform=macOS' \
    -enableCodeCoverage YES \
    -resultBundlePath TestResults.xcresult
```

### カバレッジレポート
Xcodeスキーム設定でコードカバレッジを有効化：
```bash
xcodebuild test -enableCodeCoverage YES ...
```

## テストへの貢献

### 新しいテストの追加
1. **テスト対象コンポーネントの特定**
2. **適切なテストクラスの選択**または新規作成
3. **命名規則と構造の順守**
4. **エッジケースとエラーシナリオの包含**
5. **重要パスのパフォーマンステスト追加**
6. **必要に応じてドキュメント更新**

### テストレビューチェックリスト
- [ ] テストが分離され独立している
- [ ] エッジケースとエラー条件がカバーされている
- [ ] パフォーマンスへの影響が考慮されている
- [ ] モックオブジェクトが適切に使用されている
- [ ] 非同期操作が正しく処理されている
- [ ] クリーンアップが適切に実装されている

## テスト失敗のデバッグ

### よくある問題
1. **タイミング問題**: 非同期操作に適切なエクスペクテーションを使用
2. **状態汚染**: 適切なsetup/teardownの確保
3. **モック設定**: モックオブジェクトが正しく設定されているか確認
4. **ファイルシステム**: 一時ディレクトリのクリーンアップ確認

### デバッグテクニック
```swift
// 詳細ログの追加
print("Debug: \(variable)")

// Xcodeでブレークポイント使用
// 特定シナリオ用の条件付きブレークポイント設定

// モック状態の確認
XCTAssertEqual(mockFileManager.writeStringCalledURLs.count, 1)
```

## まとめ

Tunerテストスイートは以下で構成されるコア機能の包括的カバレッジを提供します：

- **200以上のテストケース** 5つの新しいテストクラスにわたって
- **複数のテストパターン**: ユニット、統合、パフォーマンス
- **堅牢なモックシステム** 外部依存関係用
- **async/awaitサポート** モダンSwiftパターン用
- **パフォーマンスベンチマーク** 重要操作用
- **エラーシナリオカバレッジ** 信頼性確保用

このテストインフラストラクチャにより、コード品質の確保、リグレッションの防止、Tunerアプリケーションの自信を持ったリファクタリングが可能になります。