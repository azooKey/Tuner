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
    private var lastAddedEntryText: String? = nil
    
    // MinHash関連のプロパティ
    private var minHashOptimizer = TextModelOptimizedWithLRU()
    private let similarityThreshold: Double = 0.8
    
    // ファイル管理のためのプロパティ (追加)
    private let fileManager: FileManaging
    private let appGroupIdentifier: String = "group.dev.ensan.inputmethod.azooKeyMac" // App Group ID (定数化)
    
    /// イニシャライザ (修正: FileManaging を注入)
    init(fileManager: FileManaging = DefaultFileManager()) {
        self.fileManager = fileManager // 注入されたインスタンスを保存
        createAppDirectory()
        printFileURL() // ファイルパスを表示
    }
    
    // LM (.marisa) ファイルの保存ディレクトリを取得 (修正: self.fileManager を使用)
    func getLMDirectory() -> URL {
        // App Group コンテナの URL を取得 (修正)
        guard let containerURL = self.fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
             fatalError("❌ Failed to get App Group container URL.")
        }

        let p13nDirectory = containerURL.appendingPathComponent("Library/Application Support/p13n_v1")

        // ディレクトリが存在しない場合は作成 (修正)
        do {
            try self.fileManager.createDirectory(at: p13nDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create LM directory: \(error.localizedDescription)")
        }

        return p13nDirectory
    }
    
    // TextEntry (.jsonl など) ファイルの保存ディレクトリを取得 (修正: self.fileManager を使用)
    func getTextEntryDirectory() -> URL {
        // App Group コンテナの URL を取得 (修正)
        guard let containerURL = self.fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
             fatalError("❌ Failed to get App Group container URL.")
        }

        let textEntryDirectory = containerURL.appendingPathComponent("Library/Application Support/p13n_v1/textEntry")

        // ディレクトリが存在しない場合は作成 (修正)
        do {
            try self.fileManager.createDirectory(at: textEntryDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create TextEntry directory: \(error.localizedDescription)")
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
    
    // Change access level from private to internal to allow testing
    internal func updateFile(avoidApps: [String], minTextLength: Int) {
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
            print("🐛 [TextModel] updateFile async block START") // Debug print
            guard let self = self else {
                print("⚠️ [TextModel] updateFile async block: self is nil") // Debug print
                return
            }

            // Defer the state reset, ensuring it runs even on errors
            defer {
                DispatchQueue.main.async {
                    self.isUpdatingFile = false
                    // print("🔓 isUpdatingFile を false に設定") // デバッグ用
                }
            }

            // Wrap the entire file operation logic in a do-catch block
            do {
                // ファイルの有無を確認し、なければ作成 (修正: self.fileManager を使用)
                if !self.fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        // write メソッドを使用 (修正)
                        try self.fileManager.write("", to: fileURL, atomically: true, encoding: .utf8)
                        print("📄 新規ファイルを作成: \(fileURL.path)")
                    } catch {
                        // Re-throw or handle specific file creation error if needed,
                        // but for now, let the outer catch handle it.
                        print("❌ ファイル作成に失敗 (will be caught by outer block): \(error.localizedDescription)")
                        throw error // Propagate the error to the outer catch
                    }
                }

                // 書き込む前に、TextEntry ディレクトリの存在を確認（念のため）(修正: self.fileManager を使用)
                let textEntryDir = self.getTextEntryDirectory() // これは内部で self.fileManager を使う
                if !self.fileManager.fileExists(atPath: textEntryDir.path) {
                    do {
                        // createDirectory を使用 (修正)
                        try self.fileManager.createDirectory(at: textEntryDir, withIntermediateDirectories: true, attributes: nil)
                        print("📁 TextEntryディレクトリを作成: \(textEntryDir.path)")
                    } catch {
                         print("❌ TextEntryディレクトリの作成に失敗 (will be caught by outer block): \(error.localizedDescription)")
                        throw error // Propagate the error to the outer catch
                    }
                } else {
                    print("🐛 [TextModel] updateFile: Directory already exists.") // Debug print
                }

                // Moved file handle operations inside the main do-catch
                let fileHandle = try self.fileManager.fileHandleForUpdating(from: fileURL)
                defer {
                    // close() is now throwing, handle potential error
                    do {
                        try fileHandle.close()
                    } catch {
                        // Log closing error, but don't let it mask the primary error
                        print("❌ Error closing file handle: \(error.localizedDescription)")
                    }
                }

                // seekToEnd is now throwing
                _ = try fileHandle.seekToEnd() // Ignore returned offset

                // offsetInFile access remains the same
                let currentOffset = fileHandle.offsetInFile
                if currentOffset > 0 {
                    // seek(toOffset:) is now throwing
                    try fileHandle.seek(toOffset: currentOffset - 1)
                    // read(upToCount:) is now throwing
                    if let lastByteData = try fileHandle.read(upToCount: 1),
                       lastByteData != "\n".data(using: .utf8) {
                        // seekToEnd is now throwing
                        _ = try fileHandle.seekToEnd()
                        // write(contentsOf:) remains throwing
                        try fileHandle.write(contentsOf: "\n".data(using: .utf8)!)
                    }
                } else {
                    print("🐛 [TextModel] updateFile: File is empty.") // Debug print
                }

                let avoidAppsSet = Set(avoidApps)
                let filteredEntries = entriesToSave.filter {
                    !avoidAppsSet.contains($0.appName) &&
                    $0.text.count >= minTextLength
                }
                print("🐛 [TextModel] updateFile: Filtered entries (\(filteredEntries.count) remaining). Attempting to write...") // Debug print

                var linesWritten = 0
                for (idx, textEntry) in filteredEntries.enumerated() {
                    do {
                        let jsonData = try JSONEncoder().encode(textEntry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            let jsonLine = jsonString + "\n"
                            if let data = jsonLine.data(using: .utf8) {
                                // Inner do-catch for individual line write error
                                do {
                                    try fileHandle.write(contentsOf: data)
                                    linesWritten += 1
                                } catch {
                                    print("❌ [TextModel] updateFile: Error writing entry \(idx+1) ('\(textEntry.text.prefix(20))...'): \(error.localizedDescription)") // Log specific write error
                                    // Optionally decide whether to continue or re-throw
                                }
                            } else {
                                print("❌ [TextModel] updateFile: Error encoding jsonLine to data for entry \(idx+1)")
                            }
                        } else {
                            print("❌ [TextModel] updateFile: Error encoding jsonData to string for entry \(idx+1)")
                        }
                    } catch {
                        print("❌ [TextModel] updateFile: Error JSONEncoding entry \(idx+1): \(error.localizedDescription)")
                    }
                }

                print("🐛 [TextModel] updateFile: Finished writing loop (\(linesWritten) lines written).") // Debug print

                if linesWritten > 0 {
                    print("💾 Saved \(linesWritten) entries to \(fileURL.lastPathComponent)")
                    // Only update lastSavedDate if writing was successful
                    DispatchQueue.main.async {
                        self.lastSavedDate = Date()
                        print("🐛 [TextModel] updateFile: Updated lastSavedDate.") // Debug print
                    }
                }

                // Trigger N-gram training only if writes were successful
                if !filteredEntries.isEmpty && linesWritten > 0 && saveCounter % (saveThreshold * 5) == 0 {
                    print("🔄 N-gramモデルの学習を開始") // Original log
                    Task {
                        await self.trainNGramOnNewEntries(newEntries: filteredEntries, ngramSize: self.ngramSize, baseFilePattern: "lm")
                    }
                }

            } catch {
                // Catch any error from the file operations within the main do block
                print("❌❌❌ [TextModel] updateFile: CRITICAL ERROR during file operations or writing: \(error.localizedDescription)")
                // Consider how to handle failed writes. Maybe re-queue entriesToSave?
                // For now, just log the error.
            }

            print("🐛 [TextModel] updateFile async block END") // Debug print
        }
    }
    
    private func printFileURL() {
        let fileURL = getFileURL()
        print("File saved at: \(fileURL.path)")
    }
    
    func removeExtraNewlines(from text: String) -> String {
        return text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "  ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        if text.isEmpty {
            return
        }
        
        if text.count < minTextLength {
            return
        }
        
        let cleanedText = removeExtraNewlines(from: text)
        
        // 直前の "正常に追加された" テキストとの重複チェック (修正)
        if let lastAdded = lastAddedEntryText, lastAdded == cleanedText {
            // print("🔍 SKIP(Duplicate): [\(appName)] Same as last successfully added. Text: \(cleanedText)")
            return
        }
        
        if cleanedText.utf16.isSymbolOrNumber {
            return
        }
        
        if avoidApps.contains(appName) {
            return
        }
        
        let timestamp = Date()
        let newTextEntry = TextEntry(appName: appName, text: cleanedText, timestamp: timestamp)
        
        texts.append(newTextEntry)
        lastAddedEntryText = cleanedText // 正常に追加されたので更新
        saveCounter += 1
        
        let intervalFlag : Bool = {
            if let lastSavedDate = lastSavedDate {
                let interval = Date().timeIntervalSince(lastSavedDate)
                return interval > Double(saveIntervalSec)
            } else {
                return true
            }
        }()
        
        if (texts.count >= saveLineTh || intervalFlag) && !isUpdatingFile {
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
        fileAccessQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            var loadedTexts: [TextEntry] = []
            var unreadableLines: [String] = []

            // Check file existence using fileManager (修正)
            if !self.fileManager.fileExists(atPath: fileURL.path) {
                DispatchQueue.main.async {
                    completion(loadedTexts)
                }
                return
            }

            var fileContents = ""
            do {
                // Read file contents using fileManager (修正)
                fileContents = try self.fileManager.contentsOfFile(at: fileURL, encoding: .utf8)
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
                    // write メソッドを使用 (修正)
                    try self.fileManager.write(unreadableText, to: unreadableFileURL, atomically: true, encoding: .utf8)
                    print("📝 Saved \(unreadableLines.count) unreadable lines to \(unreadableFileURL.lastPathComponent)")
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
