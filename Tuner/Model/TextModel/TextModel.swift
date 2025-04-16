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
    
    let ngramSize: Int = 5
    private var saveCounter = 0
    private let saveThreshold = 100  // 100エントリごとに学習
    private var textHashes: Set<TextEntry> = []
    let fileAccessQueue = DispatchQueue(label: "com.contextdatabaseapp.fileAccessQueue")
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
    func getLMDirectory() -> URL {
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
    func getTextEntryDirectory() -> URL {
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
                        await self.trainNGramOnNewEntries(newEntries: filteredEntries, ngramSize: self.ngramSize, baseFilePattern: "lm")
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
    
    func removeExtraNewlines(from text: String) -> String {
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
}
