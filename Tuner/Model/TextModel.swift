//
//  TextModel.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/06/30.
//

import Foundation
import EfficientNGram

/// テキストデータの管理と処理を行うモデルクラス
/// - テキストエントリの保存と読み込み
/// - テキストの重複除去
/// - N-gramモデルの学習
/// - 統計情報の生成
class TextModel: ObservableObject {
    @Published var texts: [TextEntry] = []
    @Published var lastSavedDate: Date? = nil
    @Published var isDataSaveEnabled: Bool = true
    @Published var lastNGramTrainingDate: Date? = nil
    @Published var lastPurifyDate: Date? = nil
    
    private let ngramSize: Int = 5
    private var saveCounter = 0
    private let saveThreshold = 100  // 100エントリごとに学習
    private var textHashes: Set<TextEntry> = []
    private let fileAccessQueue = DispatchQueue(label: "com.contextdatabaseapp.fileAccessQueue")
    private var isUpdatingFile = false
    
    // MinHash関連のプロパティ
    private var minHashOptimizer = TextModelOptimizedWithLRU()
    private let similarityThreshold: Double = 0.8
    
    init() {
        createAppDirectory()
        printFileURL() // ファイルパスを表示
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    // LM (.marisa) ファイルの保存ディレクトリを取得
    private func getLMDirectory() -> URL {
        let fileManager = FileManager.default

        // App Group コンテナの URL を取得
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ensan.inputmethod.azooKeyMac") else {
             // コンテナURLが取得できない場合のエラー処理（fatalErrorのまま）
             fatalError("❌ Failed to get App Group container URL.")
        }

        // 正しい LM ディレクトリのパスを構築 (コンテナURL + Library/Application Support/p13n_v1)
        let p13nDirectory = containerURL.appendingPathComponent("Library/Application Support/p13n_v1") // "lm" を削除

        // ディレクトリが存在しない場合は作成
        do {
            // withIntermediateDirectories: true なので、中間のディレクトリも必要に応じて作成される
            try fileManager.createDirectory(at: p13nDirectory, withIntermediateDirectories: true)
        } catch {
            // ディレクトリ作成失敗時のエラーログ
            print("❌ Failed to create LM directory: \(error.localizedDescription)")
            // ここで fatalError にしないのは、ディレクトリが既に存在する可能性などを考慮
        }

        return p13nDirectory
    }
    
    // TextEntry (.jsonl など) ファイルの保存ディレクトリを取得
    private func getTextEntryDirectory() -> URL {
        let fileManager = FileManager.default

        // App Group コンテナの URL を取得
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ensan.inputmethod.azooKeyMac") else {
             fatalError("❌ Failed to get App Group container URL.") // エラー処理は維持
        }

        // 正しい TextEntry ディレクトリのパスを構築 (コンテナURL + Library/Application Support/p13n_v1/textEntry)
        let textEntryDirectory = containerURL.appendingPathComponent("Library/Application Support/p13n_v1/textEntry") // "Library" をパスに追加

        // ディレクトリが存在しない場合は作成
        do {
            try fileManager.createDirectory(at: textEntryDirectory, withIntermediateDirectories: true) // 中間ディレクトリも作成
        } catch {
            print("❌ Failed to create TextEntry directory: \(error.localizedDescription)") // エラーログは維持
        }

        return textEntryDirectory
    }
    
    func getFileURL() -> URL {
        return getTextEntryDirectory().appendingPathComponent("savedTexts.jsonl")
    }
    
    private func createAppDirectory() {
        // Ensure both directories are created upon initialization
        _ = getLMDirectory()
        _ = getTextEntryDirectory()
    }
    
    private func updateFile(avoidApps: [String], minTextLength: Int) {
        // ファイル更新中なら早期リターン
        guard !isUpdatingFile else {
            print("⚠️ ファイル更新中です。処理をスキップします")
            return
        }
        
        // ★★★ 保存対象のエントリをキャプチャ ★★★
        let entriesToSave = self.texts
        
        // 書き込み対象がなければ終了（キャプチャ後にチェック）
        guard !entriesToSave.isEmpty else {
            // print("⚠️ 保存するテキストがありません") // ログレベル調整
            return
        }
        
        // ★★★ texts配列を直ちにクリア ★★★
        // これにより、ファイル書き込み中にaddTextで追加されたエントリは保持される
        self.texts.removeAll()
        print("🔄 メモリ内テキストをクリアし、\(entriesToSave.count)件の保存処理を開始")
        
        isUpdatingFile = true
        // print("💾 ファイル更新を開始: \(entriesToSave.count)件のエントリ") // ログ変更

        let fileURL = getFileURL()
        fileAccessQueue.async { [weak self] in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isUpdatingFile = false
                    // print("🔓 isUpdatingFile を false に設定") // デバッグ用
                }
            }

            // ファイルの有無を確認し、なければ作成
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try "".write(to: fileURL, atomically: true, encoding: .utf8)
                    print("📄 新規ファイルを作成: \(fileURL.path)")
                } catch {
                    print("❌ ファイル作成に失敗: \(error.localizedDescription)")
                    // ★★★ エラー発生時もisUpdatingFileはdeferでfalseになる ★★★
                    return
                }
            }

            // 書き込む前に、TextEntry ディレクトリの存在を確認（念のため）
            let textEntryDir = self.getTextEntryDirectory()
            if !FileManager.default.fileExists(atPath: textEntryDir.path) {
                do {
                    try FileManager.default.createDirectory(at: textEntryDir, withIntermediateDirectories: true)
                    print("📁 TextEntryディレクトリを作成: \(textEntryDir.path)")
                } catch {
                    print("❌ TextEntryディレクトリの作成に失敗: \(error.localizedDescription)")
                    return
                }
            }

            do {
                let fileHandle = try FileHandle(forUpdating: fileURL)
                defer {
                    fileHandle.closeFile()
                }

                // 末尾に移動
                fileHandle.seekToEndOfFile()
                
                // 最初の追記でなければ改行を追加
                let currentOffset = fileHandle.offsetInFile
                if currentOffset > 0 {
                    fileHandle.seek(toFileOffset: currentOffset - 1)
                    if let lastByte = try fileHandle.read(upToCount: 1), lastByte != "\n".data(using: .utf8) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write("\n".data(using: .utf8)!)
                    } else {
                        fileHandle.seekToEndOfFile()
                    }
                }

                // ★★★ キャプチャしたentriesToSaveでフィルタリング ★★★
                let avoidAppsSet = Set(avoidApps)
                let filteredEntries = entriesToSave.filter {
                    !avoidAppsSet.contains($0.appName) &&
                    $0.text.count >= minTextLength
                }
                
                // フィルタリングで除外されたエントリをログ出力
                let skippedCount = entriesToSave.count - filteredEntries.count
                if skippedCount > 0 {
                    // print("🔍 Filtered out \(skippedCount) entries before saving:") // 削除
                    // 詳細ログループも削除
                }

                // print("📝 フィルタリング後: \(filteredEntries.count)件のエントリを保存") // 削除

                // 各エントリを jsonl 形式で追記
                var linesWritten = 0
                // var encodingErrors = 0 // 削除
                // var writeErrors = 0 // 削除
                for textEntry in filteredEntries {
                    do {
                        let jsonData = try JSONEncoder().encode(textEntry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            let jsonLine = jsonString + "\n"
                            if let data = jsonLine.data(using: .utf8) {
                                do {
                                    try fileHandle.write(contentsOf: data)
                                    linesWritten += 1
                                } catch {
                                    // 個別エラーログは抑制（全体のエラーハンドリングで捕捉）
                                    // print("❌ Write Error for entry...") // 削除
                                    // writeErrors += 1 // 削除
                                }
                            } else {
                                // print("❌ Encoding Error (data using .utf8)...") // 削除
                                // encodingErrors += 1 // 削除
                            }
                        } else {
                            // print("❌ Encoding Error (String from data)...") // 削除
                            // encodingErrors += 1 // 削除
                        }
                    } catch {
                        // print("❌ JSON Encoding Error for entry...") // 削除
                        // encodingErrors += 1 // 削除
                    }
                }
                
                // エラーサマリーログは削除
                // if encodingErrors > 0 || writeErrors > 0 { ... }

                // print("✅ ファイル更新完了: \(linesWritten)件のエントリを'\(fileURL.lastPathComponent)'に保存") // 元のログに近い形に（必要なら調整）
                if linesWritten > 0 {
                    print("💾 Saved \(linesWritten) entries to \(fileURL.lastPathComponent)")
                }

                // 定期的に追加されたエントリを使って学習 (lmモデルのみ)
                if !filteredEntries.isEmpty && saveCounter % (saveThreshold * 5) == 0 {
                    print("🔄 N-gramモデルの学習を開始")
                    Task {
                        // ここでは self.ngramSize など self のプロパティアクセスが必要
                        // capture list [self] で self を弱参照ではなく強参照でキャプチャするか、
                        // または self?.ngramSize のようにオプショナルチェーンを使う必要がある。
                        // Task内でselfが解放されていない前提で、ここでは self. を使う。
                        await self.trainNGramOnNewEntries(newEntries: filteredEntries, n: self.ngramSize, baseFilePattern: "lm")
                    }
                }

                // ★★★ 完了ブロックでは lastSavedDate の更新のみ行う ★★★
                DispatchQueue.main.async {
                    // self.texts.removeAll() // ここではクリアしない！
                    self.lastSavedDate = Date()
                    // print("✅ lastSavedDate を更新") // デバッグ用
                }
            } catch {
                print("❌ ファイル更新処理全体でエラー: \(error.localizedDescription)")
                // エラーが発生した場合でも、textsは既にクリアされているため、元に戻す処理は難しい
                // 必要であれば、クリア前にバックアップを取るなどの対策が必要
                DispatchQueue.main.async {
                    // self.texts.removeAll() // ここでもクリアしない
                }
            }
        }
    }
    
    private func printFileURL() {
        let fileURL = getFileURL()
        print("File saved at: \(fileURL.path)")
    }
    
    private func removeExtraNewlines(from text: String) -> String {
        // 改行の処理を改善
        let pattern = "\n+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        let modifiedText = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        
        // 特殊文字の処理を追加
        let cleanedText = modifiedText ?? text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedText
    }
    
    /// テキストエントリを追加し、条件に応じてファイルに保存
    /// - Parameters:
    ///   - text: 追加するテキスト
    ///   - appName: アプリケーション名
    ///   - saveLineTh: 保存をトリガーする行数閾値
    ///   - saveIntervalSec: 保存をトリガーする時間間隔（秒）
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    func addText(_ text: String, appName: String, saveLineTh: Int = 10, saveIntervalSec: Int = 30, avoidApps: [String], minTextLength: Int) {
        if !isDataSaveEnabled {
            // print("⚠️ データ保存が無効化されています") // 必要ならコメント解除
            return
        }
        
        // 空のテキストはスキップ
        if text.isEmpty {
            return
        }
        
        // 最小テキスト長チェック
        if text.count < minTextLength {
            // print("🔍 SKIP(Length): [\(appName)] Length \(text.count) < \(minTextLength). Text: \(text)") // 削除
            return
        }
        
        // 改行の処理
        let cleanedText = removeExtraNewlines(from: text)
        // 変更ログは削除
        
        // 直前のテキストとの重複チェック
        if let lastAdded = texts.last?.text, lastAdded == cleanedText {
            // print("🔍 SKIP(Duplicate): [\(appName)] Same as last. Text: \(cleanedText)") // 削除
            return
        }
        
        // 記号や数字のみのテキストのチェック
        if cleanedText.utf16.isSymbolOrNumber {
            // print("🔍 SKIP(Symbol/Num): [\(appName)] Symbol/Number only. Text: \(cleanedText)") // 削除
            return
        }
        
        // 除外アプリのチェック
        if avoidApps.contains(appName) {
            // print("🔍 SKIP(AvoidApp): [\(appName)] App is in avoid list. Text: \(cleanedText)") // 削除
            return
        }

        
        let timestamp = Date()
        let newTextEntry = TextEntry(appName: appName, text: cleanedText, timestamp: timestamp)
        
        texts.append(newTextEntry)
        saveCounter += 1
        
        let intervalFlag : Bool = {
            if let lastSavedDate = lastSavedDate {
                let interval = Date().timeIntervalSince(lastSavedDate)
                return interval > Double(saveIntervalSec)
            } else {
                return true
            }
        }()
        
        if texts.count >= saveLineTh && intervalFlag && !isUpdatingFile{
            // print("💾 ファイル保存トリガー: ...") // 必要なら維持・調整
            updateFile(avoidApps: avoidApps, minTextLength: minTextLength)
        }
        
        // ★★★ purifyFile の呼び出しを元に戻す ★★★
        // 高頻度でMinHashによる重複削除処理を実行
        if saveCounter % 1000 == 0 { // 1000エントリごとに実行
            // print("🔄 MinHashによる重複削除処理を開始 (saveCounter: \(saveCounter))") // 必要ならコメント解除
            Task {
                await purifyFile(avoidApps: avoidApps, minTextLength: minTextLength) {
                    // print("✅ MinHashによる重複削除処理が完了") // 必要ならコメント解除
                }
            }
        }
    }
    
    private func clearMemory() {
        texts = []
    }
    
    /// ファイルからテキストエントリを読み込む
    /// - Parameter completion: 読み込み完了時に実行するコールバック
    func loadFromFile(completion: @escaping ([TextEntry]) -> Void) {
        let fileURL = getFileURL()
        fileAccessQueue.async {
            var loadedTexts: [TextEntry] = []
            var unreadableLines: [String] = []
            
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                DispatchQueue.main.async {
                    completion(loadedTexts)
                }
                return
            }
            
            var fileContents = ""
            do {
                fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                print("❌ Failed to load from file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            var skipCount = 0
            let lines = fileContents.split(separator: "\n")
            for line in lines {
                if line.isEmpty {
                    continue
                }
                do {
                    if let jsonData = line.data(using: .utf8) {
                        let textEntry = try JSONDecoder().decode(TextEntry.self, from: jsonData)
                        loadedTexts.append(textEntry)
                    }
                } catch {
                    if error.localizedDescription.contains("The data couldn't be read because it isn't in the correct format.") {
                        skipCount += 1
                        unreadableLines.append(String(line))
                    }
                    continue
                }
            }

            if unreadableLines.count > 0 {
                let unreadableFileURL = self.getFileURL().deletingLastPathComponent().appendingPathComponent("unreadableLines.txt") // Use same directory
                let unreadableText = unreadableLines.joined(separator
                                                            : "\n")
                do {
                    try unreadableText.write(to: unreadableFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("❌ Failed to save unreadable lines: \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                completion(loadedTexts)
            }
        }
    }
    
    // loadFromFile を async/await でラップした関数
    func loadFromFileAsync() async -> [TextEntry] {
        await withCheckedContinuation { continuation in
            self.loadFromFile { loadedTexts in
                continuation.resume(returning: loadedTexts)
            }
        }
    }
    
    /// アプリケーション名ごとのエントリ数を集計
    /// - Parameter completion: 集計完了時に実行するコールバック
    func aggregateAppNames(completion: @escaping ([String: Int]) -> Void) {
        loadFromFile { loadedTexts in
            var appNameCounts: [String: Int] = [:]
            
            for entry in loadedTexts {
                appNameCounts[entry.appName, default: 0] += 1
            }
            
            completion(appNameCounts)
        }
    }
    
    /// 統計情報を生成する
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - completion: 生成完了時に実行するコールバック
    func generateStatisticsParameter(avoidApps: [String], minTextLength: Int, completion: @escaping (([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String, [(key: String, value: Int)])) -> Void) {
        // データのクリーンアップ
        purifyFile(avoidApps: avoidApps, minTextLength: minTextLength) {
            self.loadFromFile { loadedTexts in
                var textEntries: [TextEntry] = []
                var appNameCounts: [String: Int] = [:]
                var appNameTextCounts: [String: Int] = [:]
                var totalTextLength = 0
                var totalEntries = 0
                var uniqueEntries: Set<String> = []
                
                var duplicatedCount = 0
                
                // 言語のカウント
                var langText: [String: Int] = ["JA": 0, "EN": 0, "Num": 0]
                var langOther: Int = 0
                
                for entry in loadedTexts {
                    let uniqueKey = "\(entry.appName)-\(entry.text)"
                    // 重複をスキップ
                    if uniqueEntries.contains(uniqueKey) {
                        duplicatedCount += 1
                        continue
                    }
                    uniqueEntries.insert(uniqueKey)
                    textEntries.append(entry)
                    
                    if avoidApps.contains(entry.appName) {
                        continue
                    }
                    appNameCounts[entry.appName, default: 0] += 1
                    appNameTextCounts[entry.appName, default: 0] += entry.text.count
                    totalTextLength += entry.text.count
                    totalEntries += 1
                    
                    // 言語ごとのテキスト長を計算
                    for char in entry.text {
                        if char.isJapanese {
                            langText["JA"]! += 1
                        } else if char.isEnglish {
                            langText["EN"]! += 1
                        } else if char.isNumber {
                            langText["Num"]! += 1
                        } else {
                            langOther += 1
                        }
                    }
                }
                
                // 日本語・英語の割合計算
                var stats = ""
                stats += "Total Text Entries: \(totalEntries)\n"
                stats += "Total Text Length: \(totalTextLength) characters\n"
                
                let sortedAppNameCounts = appNameCounts.sorted { $0.value > $1.value }
                let sortedAppNameTextCounts = appNameTextCounts.sorted { $0.value > $1.value }
                let sortedLangTextCounts = langText.sorted { $0.value > $1.value } + [("Other", langOther)]
                
                completion((sortedAppNameCounts, sortedAppNameTextCounts, totalEntries, totalTextLength, stats, sortedLangTextCounts))
            }
        }
    }

    /// ファイルの重複エントリを除去し、クリーンアップを実行
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - completion: クリーンアップ完了時に実行するコールバック
    func purifyFile(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        let fileURL = getFileURL()
        let tempFileURL = getTextEntryDirectory().appendingPathComponent("tempSavedTexts.jsonl")

        loadFromFile { loadedTexts in
            if loadedTexts.isEmpty {
                print("No texts loaded from file - skipping purify to avoid empty file")
                completion()
                return
            }

            // MinHashを使用した重複検出と削除
            let minHash = MinHashOptimized(numHashFunctions: 20)
            let avoidAppsSet = Set(avoidApps)
            
            // バケットベースの重複検出
            var buckets: [Int: [TextEntry]] = [:]
            var uniqueEntries: [TextEntry] = []
            var duplicateCount = 0
            var potentialDuplicates: [(TextEntry, TextEntry, Double)] = [] // デバッグ用
            
            // バケットを計算する関数
            func getBucket(signature: [Int]) -> Int {
                var hasher = Hasher()
                signature[0..<3].forEach { hasher.combine($0) }
                return hasher.finalize()
            }
            
            for entry in loadedTexts {
                // 除外アプリの場合はスキップ
                if avoidAppsSet.contains(entry.appName) || entry.text.count < minTextLength {
                    continue
                }
                
                let signature = minHash.computeMinHashSignature(for: entry.text)
                let bucket = getBucket(signature: signature)
                
                var isDuplicate = false
                
                // 同じバケット内のエントリとのみ比較
                if let existingEntries = buckets[bucket] {
                    for existingEntry in existingEntries {
                        // 完全一致の場合は必ず重複と判定
                        if entry.text == existingEntry.text {
                            isDuplicate = true
                            duplicateCount += 1
                            print("🔍 完全一致による重複を検出: [\(entry.appName)] \(entry.text)")
                            break
                        }
                        
                        // テキストの長さの差が大きい場合は重複と判定しない
                        let lengthDiff = abs(entry.text.count - existingEntry.text.count)
                        let maxLength = max(entry.text.count, existingEntry.text.count)
                        if Double(lengthDiff) / Double(maxLength) > 0.1 { // 0.2から0.1に変更
                            continue
                        }
                        
                        // 類似度が0.98以上の場合のみ重複とみなす（0.95から0.98に変更）
                        let existingSignature = minHash.computeMinHashSignature(for: existingEntry.text)
                        let similarity = minHash.computeJaccardSimilarity(signature1: signature, signature2: existingSignature)
                        
                        // デバッグ用に類似度が高いペアを記録
                        if similarity >= 0.95 { // 0.98未満でも0.95以上の場合は記録
                            potentialDuplicates.append((entry, existingEntry, similarity))
                        }
                        
                        if similarity >= 0.98 { // 0.95から0.98に変更
                            isDuplicate = true
                            duplicateCount += 1
                            print("🔍 類似度による重複を検出: [\(entry.appName)] \(entry.text)")
                            print("  類似度: \(similarity), 既存テキスト: \(existingEntry.text)")
                            break
                        }
                    }
                }
                
                if !isDuplicate {
                    uniqueEntries.append(entry)
                    buckets[bucket, default: []].append(entry)
                }
            }
            
            // デバッグ情報の出力
            if !potentialDuplicates.isEmpty {
                print("\n🔍 高類似度ペアの一覧:")
                for (entry1, entry2, similarity) in potentialDuplicates {
                    print("  類似度: \(similarity)")
                    print("  テキスト1: [\(entry1.appName)] \(entry1.text)")
                    print("  テキスト2: [\(entry2.appName)] \(entry2.text)")
                    print("  ---")
                }
            }
            
            if duplicateCount == 0 {
                print("No duplicates found - skipping file update")
                completion()
                return
            }

            print("Found \(duplicateCount) duplicates out of \(loadedTexts.count) entries")

            self.fileAccessQueue.async {
                // バックアップファイルの作成
                let backupFileURL = self.getTextEntryDirectory().appendingPathComponent("backup_savedTexts_\(Int(Date().timeIntervalSince1970)).jsonl")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: backupFileURL)
                    print("Backup file created at: \(backupFileURL.path)")
                } catch {
                    print("Failed to create backup file: \(error.localizedDescription)")
                }

                // 新規ファイルとして一時ファイルに保存
                do {
                    var tempFileHandle: FileHandle?

                    if !FileManager.default.fileExists(atPath: tempFileURL.path) {
                        FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
                    }

                    tempFileHandle = try FileHandle(forWritingTo: tempFileURL)
                    tempFileHandle?.seekToEndOfFile()

                    var writeSuccess = false
                    var entriesWritten = 0

                    for textEntry in uniqueEntries {
                        let jsonData = try JSONEncoder().encode(textEntry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            let jsonLine = jsonString + "\n"
                            if let data = jsonLine.data(using: .utf8) {
                                tempFileHandle?.write(data)
                                entriesWritten += 1
                                writeSuccess = true
                            }
                        }
                    }

                    tempFileHandle?.closeFile()

                    if writeSuccess && entriesWritten > 0 {
                        try FileManager.default.removeItem(at: fileURL)
                        try FileManager.default.moveItem(at: tempFileURL, to: fileURL)
                        try? FileManager.default.removeItem(at: backupFileURL)
                        print("File purify completed. Removed \(duplicateCount) duplicated entries. Wrote \(entriesWritten) entries. Backup file deleted.")
                        
                        DispatchQueue.main.async {
                            self.lastPurifyDate = Date()
                        }
                    } else {
                        print("⚠️ Write was not successful or no entries were written - keeping original file")
                        try? FileManager.default.removeItem(at: tempFileURL)
                    }
                } catch {
                    print("Failed to clean and update file: \(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: tempFileURL)
                }

                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // 古いpurifyTextEntries関数 (MinHashを使わない方式) - 念のために残しておく
    func purifyTextEntriesSimple(_ entries: [TextEntry], avoidApps: [String], minTextLength: Int) -> ([TextEntry], Int) {
        print("purity start... \(entries.count)")
        var textEntries: [TextEntry] = []
        var uniqueEntries: Set<String> = []
        var duplicatedCount = 0
        
        for entry in entries {
            // 記号のみのエントリは削除
            if entry.text.utf16.isSymbolOrNumber {
                continue
            }
            
            // 除外アプリの場合はスキップ
            if avoidApps.contains(entry.appName) || minTextLength > entry.text.utf8.count {
                continue
            }
            
            // 重複チェックのためのキー生成
            let uniqueKey = "\(entry.appName)-\(entry.text)"
            if uniqueEntries.contains(uniqueKey) {
                duplicatedCount += 1
                continue
            }
            
            uniqueEntries.insert(uniqueKey)
            textEntries.append(entry)
        }
        
        // 前後の要素のテキストが前方一致している場合、短い方を削除
        var index = 0
        while index < textEntries.count - 1 {
            // アプリ名が異なる場合はスキップ
            if textEntries[index].appName != textEntries[index + 1].appName {
                index += 1
                continue
            }
            
            let currentText = textEntries[index].text.utf16
            let nextText = textEntries[index + 1].text.utf16
            
            if currentText.starts(with: nextText) || nextText.starts(with: currentText) {
                textEntries.remove(at: index + 1)
            } else {
                index += 1
            }
        }
        
        print("purity end... \(textEntries.count)")
        return (textEntries, duplicatedCount)
    }
    
    /// 新規エントリを使用してN-gramモデルを追加学習
    /// - Parameters:
    ///   - newEntries: 新規テキストエントリの配列
    ///   - n: N-gramのサイズ
    ///   - baseFilename: ベースとなるファイル名
    func trainNGramOnNewEntries(newEntries: [TextEntry], n: Int, baseFilePattern: String) async {
        let lines = newEntries.map { $0.text }
        if lines.isEmpty {
            return
        }
        let fileManager = FileManager.default
        let outputDirURL = getLMDirectory() // Use the LM directory function
        let outputDir = outputDirURL.path
        
        do {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return
        }
        
        // WIPファイルの作成（コピー処理は削除）
        let wipFileURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(baseFilePattern).wip")
        do {
            try "Training in progress".write(to: wipFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to create WIP file: \(error)")
        }
        
        // trainNGram 呼び出しを do-catch で囲む
        do {
             // --- テスト用変更を元に戻す ---
             let resumePattern = baseFilePattern // lm の場合は lm を resumePattern として渡す
             print("    Calling trainNGram with resumeFilePattern = \\(resumePattern)") // ログ追加
             let resumeFileURL = outputDirURL.appendingPathComponent(resumePattern) // フルパスを生成
             try await trainNGram( // try を追加 (もし trainNGram が throws する場合)
                 lines: lines,
                 n: n,
                 baseFilePattern: baseFilePattern,
                 outputDir: outputDir,
                 resumeFilePattern: resumeFileURL.path // フルパスを渡すように変更
             )
             // --- テスト用変更ここまで ---
             print("  trainNGram call finished successfully.")
        } catch {
            print("❌ Failed to train N-gram model: \(error)")
        }

        // WIP ファイルを削除
        do {
            try fileManager.removeItem(at: wipFileURL)
        } catch {
            print("❌ Failed to remove WIP file: \(error)")
        }

        // lm モデルのコピー処理は trainNGramFromTextEntries で行うため、ここからは削除
    }
    
    
    /// 保存されたテキストエントリからN-gramモデルを学習
    /// - Parameters:
    ///   - n: N-gramのサイズ
    ///   - baseFilename: ベースとなるファイル名
    ///   - maxEntryCount: 最大エントリ数
    func trainNGramFromTextEntries(n: Int = 5, baseFilePattern: String = "original", maxEntryCount: Int = 100_000) async {
        let fileManager = FileManager.default
        
        let savedTexts = await loadFromFileAsync()
        
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
        var importEntries: [TextEntry] = []
        if fileManager.fileExists(atPath: importFileURL.path) {
            if let fileContents = try? String(contentsOf: importFileURL, encoding: .utf8) {
                let lines = fileContents.split(separator: "\n")
                for line in lines {
                    guard !line.isEmpty else { continue }
                    if let jsonData = line.data(using: .utf8),
                       let entry = try? JSONDecoder().decode(TextEntry.self, from: jsonData) {
                        importEntries.append(entry)
                    }
                }
            }
        }
        
        let combinedEntries = savedTexts + importEntries
        let trainingEntries = combinedEntries.suffix(maxEntryCount)
        let lines = trainingEntries.map { $0.text }
        
        let outputDirURL = getLMDirectory() // Use the LM directory function
        let outputDir = outputDirURL.path
        
        do {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return
        }
        
        if baseFilePattern == "original" {
            let lmFiles = [
                "lm_c_abc.marisa",
                "lm_u_abx.marisa",
                "lm_u_xbc.marisa",
                "lm_r_xbx.marisa",
                "lm_c_bc.marisa",
            ]
            for lmFile in lmFiles {
                let lmFilePath = URL(fileURLWithPath: outputDir).appendingPathComponent(lmFile).path
                if fileManager.fileExists(atPath: lmFilePath) {
                    do {
                        try fileManager.removeItem(atPath: lmFilePath)
                    } catch {
                        print("❌ Failed to remove lm file \(lmFile): \(error)")
                    }
                }
            }
        }
        
        await trainNGram(lines: lines, n: n, baseFilePattern: baseFilePattern, outputDir: outputDir)

        // オリジナルモデル生成後、追加学習用のlmモデルをコピーして準備 (baseFilePattern == "original" の場合のみ)
        if baseFilePattern == "original" {
            let originalFiles = [
                "original_c_abc.marisa",
                "original_u_abx.marisa",
                "original_u_xbc.marisa",
                "original_r_xbx.marisa",
                "original_c_bc.marisa",
            ]
            let lmFiles = [
                "lm_c_abc.marisa",
                "lm_u_abx.marisa",
                "lm_u_xbc.marisa",
                "lm_r_xbx.marisa",
                "lm_c_bc.marisa",
            ]

            print("Copying original models to lm models after training...")
            for (origFile, lmFile) in zip(originalFiles, lmFiles) {
                let origPath = URL(fileURLWithPath: outputDir).appendingPathComponent(origFile).path
                let lmPath = URL(fileURLWithPath: outputDir).appendingPathComponent(lmFile).path
                
                // 既存の lm ファイルがあれば削除
                if fileManager.fileExists(atPath: lmPath) {
                    do {
                        try fileManager.removeItem(atPath: lmPath)
                        print("  Removed existing lm file: \(lmFile)")
                    } catch {
                        print("❌ Failed to remove existing lm file \(lmFile): \(error)")
                    }
                }
                
                // original ファイルが存在すればコピー
                if fileManager.fileExists(atPath: origPath) {
                    do {
                        try fileManager.copyItem(atPath: origPath, toPath: lmPath)
                        print("  Copied \(origFile) to \(lmFile)")
                    } catch {
                        print("❌ Error duplicating \(origFile) to \(lmFile): \(error)")
                    }
                } else {
                    print("⚠️ Original file \(origFile) not found, cannot copy to \(lmFile).")
                }
            }
        }

        await MainActor.run {
            self.lastNGramTrainingDate = Date()
        }
    }
}

// MARK: - テキストファイルからのインポート処理
extension TextModel {
    /// テキストファイルからインポートを実行
    /// - Parameters:
    ///   - shareData: 共有データオブジェクト (インポートパスとブックマークを含む)
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    func importTextFiles(shareData: ShareData, avoidApps: [String], minTextLength: Int) async {
        let fileManager = FileManager.default
        
        // 1. ブックマークデータが存在するか確認
        guard let bookmarkData = shareData.importBookmarkData else {
            print("インポートフォルダが設定されていません。Settings -> データ管理でフォルダを選択してください。")
            return
        }
        
        var isStale = false
        var importFolderURL: URL?
        
        do {
            // 2. ブックマークデータからURLを解決し、アクセス権を取得
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: [.withSecurityScope],
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("インポートフォルダのブックマークが古くなっています。Settings -> データ管理で再選択してください。")
                return
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("インポートフォルダへのアクセス権を取得できませんでした: \(url.path)")
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            print("インポートフォルダへのアクセス権を取得: \(url.path)")
            importFolderURL = url

        } catch {
            print("インポートフォルダのブックマーク解決またはアクセス権取得に失敗しました: \(error.localizedDescription)")
            return
        }
        
        guard let importFolder = importFolderURL else {
            print("エラー: アクセス可能なインポートフォルダURLがありません。")
            return
        }
        
        var importedFileCount = 0
        let fileURLs: [URL]
        
        do {
            fileURLs = try fileManager.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil, options: [])
        } catch {
            print("❌ Failed to list import folder contents: \(error.localizedDescription)")
            return
        }
            
        if fileURLs.isEmpty {
            print("インポートフォルダに処理対象のファイル(.txt)が見つかりません: \(importFolder.path)")
        } else {
            print("インポートフォルダから \(fileURLs.count) 個のアイテムを検出: \(importFolder.path)")
        }
            
        do {
            let existingEntries = await loadFromFileAsync()
            var existingKeys = Set(existingEntries.map { "\($0.appName)-\($0.text)" })
            
            var newEntries: [TextEntry] = []
            
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                print("[DEBUG] Processing file: \(fileName)")
                
                // インポート状態を確認
                if isFileImported(fileName) {
                    print("[DEBUG] Skipping already imported file: \(fileName)")
                    continue
                }
                
                if fileURL.pathExtension.lowercased() != "txt" {
                    continue
                }
                
                do {
                    let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                    let lines = fileContent.components(separatedBy: .newlines)
                    let fileAppName = fileURL.deletingPathExtension().lastPathComponent
                    
                    var localKeys = existingKeys
                    
                    for line in lines {
                        let cleanedLine = removeExtraNewlines(from: line)
                        
                        if cleanedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cleanedLine.count < minTextLength {
                            continue
                        }
                        
                        let key = "\(fileAppName)-\(cleanedLine)"
                        if localKeys.contains(key) {
                            continue
                        }
                        
                        localKeys.insert(key)
                        existingKeys.insert(key)
                        
                        let newEntry = TextEntry(appName: fileAppName, text: cleanedLine, timestamp: Date())
                        newEntries.append(newEntry)
                    }
                    
                    // ファイルをインポート済みとしてマーク
                    markFileAsImported(fileName, jsonlFileName: generateJsonlFileName(for: fileName), lastModifiedDate: Date())
                    importedFileCount += 1
                    print("[DEBUG] Successfully imported: \(fileName)")
                    
                } catch {
                    print("❌ Error processing file \(fileName): \(error.localizedDescription)")
                }
            }
            
            if !newEntries.isEmpty {
                let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
                
                do {
                    var currentContent = ""
                    if fileManager.fileExists(atPath: importFileURL.path) {
                        currentContent = try String(contentsOf: importFileURL, encoding: .utf8)
                        if !currentContent.isEmpty && !currentContent.hasSuffix("\n") {
                             currentContent += "\n"
                        }
                    }
                    
                    var newContent = ""
                    for entry in newEntries {
                        let jsonData = try JSONEncoder().encode(entry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            newContent.append(jsonString + "\n")
                        }
                    }
                    try (currentContent + newContent).write(to: importFileURL, atomically: true, encoding: .utf8)
                    print("\(newEntries.count) 件の新規エントリを import.jsonl に追記しました。")
                } catch {
                    print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
                }
            }
            
        } catch {
            print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
        }
        
        print("[DEBUG] Finished file processing loop.")
        await MainActor.run {
            print("[DEBUG] Updating ShareData. Imported count: \(importedFileCount)")
            if importedFileCount > 0 {
                shareData.lastImportedFileCount = importedFileCount
                shareData.lastImportDate = Date().timeIntervalSince1970
                print("[DEBUG] Import record updated: \(importedFileCount) files, Date: \(shareData.lastImportDateAsDate?.description ?? "nil")")
            } else if !fileURLs.isEmpty {
                print("[DEBUG] No new files were imported, but folder was checked. Updating check date.")
                shareData.lastImportDate = Date().timeIntervalSince1970
            } else {
                print("[DEBUG] No files found in import folder. Import record not updated.")
            }
        }
    }
}

// MARK: - インポート履歴のリセット
extension TextModel {
    /// import.jsonl ファイルを削除し、ShareDataのインポート履歴をリセットする
    func resetImportHistory(shareData: ShareData) async {
        let fileManager = FileManager.default
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
        
        do {
            // import.jsonlを削除
            if fileManager.fileExists(atPath: importFileURL.path) {
                try fileManager.removeItem(at: importFileURL)
                print("Deleted import.jsonl successfully.")
            } else {
                print("import.jsonl does not exist, skipping deletion.")
            }
            
            // インポート状態をリセット
            resetImportStatus()
            
            // ShareDataの値をリセット
            await MainActor.run {
                shareData.lastImportDate = nil
                shareData.lastImportedFileCount = -1
                print("Import history in ShareData reset.")
            }
        } catch {
            print("❌ Failed to reset import history: \(error.localizedDescription)")
        }
    }
}

// TextModel.swift に追加する拡張
extension TextModel {
    // import.jsonlからテキストエントリを読み込む関数
    func loadFromImportFileAsync() async -> [TextEntry] {
        return await withCheckedContinuation { continuation in
            self.loadFromImportFile { loadedTexts in
                continuation.resume(returning: loadedTexts)
            }
        }
    }
    
    // import.jsonlファイルから読み込むメソッド
    func loadFromImportFile(completion: @escaping ([TextEntry]) -> Void) {
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
        fileAccessQueue.async {
            var loadedTexts: [TextEntry] = []
            
            if !FileManager.default.fileExists(atPath: importFileURL.path) {
                DispatchQueue.main.async {
                    completion(loadedTexts)
                }
                return
            }
            
            var fileContents = ""
            do {
                fileContents = try String(contentsOf: importFileURL, encoding: .utf8)
            } catch {
                print("❌ Failed to load from import file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            let lines = fileContents.split(separator: "\n")
            for line in lines {
                if line.isEmpty {
                    continue
                }
                do {
                    if let jsonData = line.data(using: .utf8) {
                        let textEntry = try JSONDecoder().decode(TextEntry.self, from: jsonData)
                        loadedTexts.append(textEntry)
                    }
                } catch {
                    print("❌ Failed to load from import file: \(error.localizedDescription)")
                    continue
                }
            }
            
            DispatchQueue.main.async {
                completion(loadedTexts)
            }
        }
    }
    
    /// 統計情報を個別に生成
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - progressCallback: 進捗状況を通知するコールバック
    ///   - statusCallback: ステータス情報を通知するコールバック
    /// - Returns: 結合データ、savedTexts、importTextsの統計情報
    func generateSeparatedStatisticsAsync(
        avoidApps: [String],
        minTextLength: Int,
        progressCallback: @escaping (Double) -> Void,
        statusCallback: @escaping (String, String) -> Void = { _, _ in }
    ) async -> (
        combined: ([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String, [(key: String, value: Int)]),
        savedTexts: ([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String, [(key: String, value: Int)]),
        importTexts: ([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String, [(key: String, value: Int)])
    ) {
        // 進捗状況の初期化
        progressCallback(0.0)
        statusCallback("処理を開始しています...", "データを読み込み中...")
        
        // savedTexts.jsonl からテキストを非同期で読み込む
        statusCallback("データを読み込み中...", "savedTexts.jsonlを解析しています")
        let savedTexts = await loadFromFileAsync()
        progressCallback(0.1)
        
        // import.jsonl からテキストを非同期で読み込む
        statusCallback("データを読み込み中...", "import.jsonlを解析しています")
        let importTexts = await loadFromImportFileAsync()
        progressCallback(0.2)
        
        // 両方のデータを結合
        let combinedTexts = savedTexts + importTexts
        statusCallback("データを処理中...", "全テキスト \(combinedTexts.count) 件の統計処理を開始します")
        
        // savedTexts.jsonlの統計処理
        statusCallback("savedTexts.jsonlの処理中...", "\(savedTexts.count) 件を分析しています")
        let savedTextStats = await processStatistics(
            entries: savedTexts,
            avoidApps: avoidApps,
            minTextLength: minTextLength,
            source: "savedTexts.jsonl",
            progressRange: (0.2, 0.4),
            progressCallback: progressCallback,
            statusCallback: statusCallback
        )
        
        // import.jsonlの統計処理
        statusCallback("import.jsonlの処理中...", "\(importTexts.count) 件を分析しています")
        let importTextStats = await processStatistics(
            entries: importTexts,
            avoidApps: avoidApps,
            minTextLength: minTextLength,
            source: "import.jsonl",
            progressRange: (0.4, 0.6),
            progressCallback: progressCallback,
            statusCallback: statusCallback
        )
        
        // 結合データの統計処理
        statusCallback("結合データの処理中...", "両ファイルの統合データ \(combinedTexts.count) 件を分析しています")
        let combinedStats = await processStatistics(
            entries: combinedTexts,
            avoidApps: avoidApps,
            minTextLength: minTextLength,
            source: "Combined Data",
            progressRange: (0.6, 0.9),
            progressCallback: progressCallback,
            statusCallback: statusCallback
        )
        
        // 完了の通知
        progressCallback(1.0)
        statusCallback("処理完了!", "統計情報の生成が完了しました")
        
        return (combinedStats, savedTextStats, importTextStats)
    }
    
    /// 統計情報を処理するヘルパーメソッド
    /// - Parameters:
    ///   - entries: 処理対象のテキストエントリ
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - source: データソース名
    ///   - progressRange: 進捗状況の範囲
    ///   - progressCallback: 進捗状況を通知するコールバック
    ///   - statusCallback: ステータス情報を通知するコールバック
    /// - Returns: 統計情報のタプル
    private func processStatistics(
        entries: [TextEntry],
        avoidApps: [String],
        minTextLength: Int,
        source: String,
        progressRange: (Double, Double),
        progressCallback: @escaping (Double) -> Void,
        statusCallback: @escaping (String, String) -> Void
    ) async -> ([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String, [(key: String, value: Int)]) {
        let (startProgress, endProgress) = progressRange
        let avoidAppsSet = Set(avoidApps)
        
        var textEntries: [TextEntry] = []
        var appNameCounts: [String: Int] = [:]
        var appNameTextCounts: [String: Int] = [:]
        var totalTextLength = 0
        var totalEntries = 0
        var uniqueEntries: Set<String> = []
        
        var duplicatedCount = 0
        
        // 言語のカウント
        var langText: [String: Int] = ["JA": 0, "EN": 0, "Num": 0]
        var langOther: Int = 0
        
        // バッチ処理で進捗状況を更新しながら処理
        let batchSize = max(1, entries.count / 10)
        
        for (index, entry) in entries.enumerated() {
            let uniqueKey = "\(entry.appName)-\(entry.text)"
            
            // 重複をスキップ
            if uniqueEntries.contains(uniqueKey) {
                duplicatedCount += 1
                continue
            }
            uniqueEntries.insert(uniqueKey)
            textEntries.append(entry)
            
            if avoidAppsSet.contains(entry.appName) {
                continue
            }
            
            appNameCounts[entry.appName, default: 0] += 1
            appNameTextCounts[entry.appName, default: 0] += entry.text.count
            totalTextLength += entry.text.count
            totalEntries += 1
            
            // 言語ごとのテキスト長を計算
            for char in entry.text {
                if char.isJapanese {
                    langText["JA"]! += 1
                } else if char.isEnglish {
                    langText["EN"]! += 1
                } else if char.isNumber {
                    langText["Num"]! += 1
                } else {
                    langOther += 1
                }
            }
            
            // バッチごとに進捗状況を更新
            if index % batchSize == 0 && entries.count > 0 {
                let progress = startProgress + (endProgress - startProgress) * Double(index) / Double(entries.count)
                progressCallback(progress)
                
                let processedPercentage = Int(Double(index) / Double(entries.count) * 100)
                let processedCount = index
                let totalCount = entries.count
                
                statusCallback(
                    "\(source)の処理中... \(processedPercentage)%",
                    "\(processedCount)/\(totalCount) 件のテキストを分析中"
                )
                
                // 少しの遅延を入れてUIの更新を可能にする
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ミリ秒
            }
        }
        
        // 統計情報の作成
        var stats = ""
        stats += "ソース: \(source)\n"
        stats += "テキストエントリ総数: \(totalEntries)\n"
        stats += "テキスト総文字数: \(totalTextLength)\n"
        
        // 平均文字数の計算
        let averageLength = totalEntries > 0 ? totalTextLength / totalEntries : 0
        stats += "エントリあたりの平均文字数: \(averageLength)\n"
        
        // 言語別の文字数の割合
        if totalTextLength > 0 {
            let jaPercentage = Int(Double(langText["JA"] ?? 0) / Double(totalTextLength) * 100)
            let enPercentage = Int(Double(langText["EN"] ?? 0) / Double(totalTextLength) * 100)
            let numPercentage = Int(Double(langText["Num"] ?? 0) / Double(totalTextLength) * 100)
            let otherPercentage = Int(Double(langOther) / Double(totalTextLength) * 100)
            
            stats += "言語別文字数割合:\n"
            stats += "  日本語: \(langText["JA"] ?? 0) 文字 (\(jaPercentage)%)\n"
            stats += "  英語: \(langText["EN"] ?? 0) 文字 (\(enPercentage)%)\n"
            stats += "  数字: \(langText["Num"] ?? 0) 文字 (\(numPercentage)%)\n"
            stats += "  その他: \(langOther) 文字 (\(otherPercentage)%)\n"
        }
        
        stats += "重複除去数: \(duplicatedCount)\n"
        
        // グラフ用にソートされたデータを作成
        let sortedAppNameCounts = appNameCounts.sorted { $0.value > $1.value }
        let sortedAppNameTextCounts = appNameTextCounts.sorted { $0.value > $1.value }
        let sortedLangTextCounts = langText.sorted { $0.value > $1.value } + [("Other", langOther)]
        
        return (sortedAppNameCounts, sortedAppNameTextCounts, totalEntries, totalTextLength, stats, sortedLangTextCounts)
    }
}

// MARK: - インポート状態管理
extension TextModel {
    /// インポート状態を管理する構造体
    private struct ImportStatus: Codable {
        struct FileInfo: Codable {
            var importDate: Date
            var jsonlFileName: String
            var lastModifiedDate: Date
        }
        var importedFiles: [String: FileInfo] // ファイル名: ファイル情報
    }
    
    /// インポート状態ファイルのURLを取得
    private func getImportStatusFileURL() -> URL {
        return getTextEntryDirectory().appendingPathComponent("import_status.json") // Use TextEntry directory
    }
    
    /// インポート状態を読み込む
    private func loadImportStatus() -> ImportStatus {
        let fileURL = getImportStatusFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let status = try? JSONDecoder().decode(ImportStatus.self, from: data) else {
            return ImportStatus(importedFiles: [:])
        }
        return status
    }
    
    /// インポート状態を保存する
    private func saveImportStatus(_ status: ImportStatus) {
        let fileURL = getImportStatusFileURL()
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: fileURL)
        }
    }
    
    /// インポート状態をリセットする
    private func resetImportStatus() {
        let fileURL = getImportStatusFileURL()
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// ファイルがインポート済みかどうかを確認
    private func isFileImported(_ fileName: String) -> Bool {
        let status = loadImportStatus()
        return status.importedFiles[fileName] != nil
    }
    
    /// ファイルのJSONLファイル名を生成
    private func generateJsonlFileName(for fileName: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "imported_\(fileName)_\(timestamp).jsonl"
    }
    
    /// ファイルをインポート済みとしてマーク
    private func markFileAsImported(_ fileName: String, jsonlFileName: String, lastModifiedDate: Date) {
        var status = loadImportStatus()
        status.importedFiles[fileName] = ImportStatus.FileInfo(
            importDate: Date(),
            jsonlFileName: jsonlFileName,
            lastModifiedDate: lastModifiedDate
        )
        saveImportStatus(status)
    }
    
    /// ファイルの最終更新日時を取得
    private func getFileLastModifiedDate(_ fileURL: URL) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            return attributes[.modificationDate] as? Date
        } catch {
            print("❌ Failed to get file modification date: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// ファイルが更新されているかどうかを確認
    private func isFileUpdated(_ fileName: String, currentModifiedDate: Date) -> Bool {
        let status = loadImportStatus()
        guard let fileInfo = status.importedFiles[fileName] else {
            return false
        }
        return currentModifiedDate > fileInfo.lastModifiedDate
    }
}

// MARK: - 手動での追加学習
extension TextModel {
    /// 手動でN-gramモデルの追加学習 (lm) を実行する
    func trainIncrementalNGramManually() async {
        print("Starting manual incremental N-gram training (lm)...")
        
        // --- 事前チェック: 必要な lm ファイルが存在するか確認 ---
        let fileManager = FileManager.default
        let lmDirURL = getLMDirectory()
        let expectedLmFiles = [
            "lm_c_abc.marisa",
            "lm_u_abx.marisa",
            "lm_u_xbc.marisa",
            "lm_r_xbx.marisa",
            "lm_c_bc.marisa"
        ]
        var allLmFilesExist = true
        print("  Checking for existing LM files in: \(lmDirURL.path)")
        for lmFile in expectedLmFiles {
            let lmPath = lmDirURL.appendingPathComponent(lmFile).path
            if fileManager.fileExists(atPath: lmPath) {
                print("    Found: \(lmFile)")
            } else {
                print("    ❌ MISSING: \(lmFile)")
                allLmFilesExist = false
            }
        }
        
        guard allLmFilesExist else {
            print("  Required LM files are missing. Aborting incremental training.")
            print("  Please run 'N-gram再構築 (全データ)' first to create the initial LM models.")
            // ここでユーザーにアラートを表示するなどの処理を追加することも可能
            return
        }
        print("  All required LM files found.")
        // --- 事前チェック完了 ---
        
        // savedTexts.jsonl から読み込み
        let savedTexts = await loadFromFileAsync()
        print("  Loaded \(savedTexts.count) entries from savedTexts.jsonl")
        
        // import.jsonl から読み込み
        let importTexts = await loadFromImportFileAsync()
        print("  Loaded \(importTexts.count) entries from import.jsonl")
        
        // 両方を結合
        let combinedEntries = savedTexts + importTexts
        print("  Total entries for training: \(combinedEntries.count)")
        
        guard !combinedEntries.isEmpty else {
            print("No entries found to train. Aborting incremental training.")
            // 必要であればユーザーに通知する処理を追加
            return
        }
        
        // trainNGramOnNewEntries を lm モードで呼び出す
        // trainNGramOnNewEntries は内部で trainNGram を呼び出し、
        // resumeFilePattern="lm" により既存の lm モデルに追記学習する
        await trainNGramOnNewEntries(newEntries: combinedEntries, n: self.ngramSize, baseFilePattern: "lm")
        
        // 最終訓練日時を更新
        await MainActor.run {
            self.lastNGramTrainingDate = Date()
            print("Manual incremental N-gram training (lm) finished at \(self.lastNGramTrainingDate!)")
        }
    }
}
