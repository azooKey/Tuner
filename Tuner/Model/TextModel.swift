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
    
    private func getAppDirectory() -> URL {
        let fileManager = FileManager.default
        
        // `Containers` 内の `Application Support` に保存
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ensan.inputmethod.azooKeyMac") else {
            fatalError("❌ Failed to get container URL.")
        }
        
        let appDirectory = containerURL.appendingPathComponent("Library/Application Support/ContextDatabaseApp")
        
        do {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create app directory: \(error.localizedDescription)")
        }
        
        return appDirectory
    }
    
    func getFileURL() -> URL {
        return getAppDirectory().appendingPathComponent("savedTexts.jsonl")
    }
    
    private func createAppDirectory() {
        let appDirectory = getAppDirectory()
        do {
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create app directory: \(error.localizedDescription)")
        }
    }
    
    private func updateFile(avoidApps: [String], minTextLength: Int) {
        // ファイル更新中なら早期リターン
        guard !isUpdatingFile else {
            return
        }
        // ファイル書き込み対象のテキストを取得
        let textsToSave = self.texts
        // 書き込み対象がなければメモリをクリアして終了
        guard !textsToSave.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.texts.removeAll()
                self?.lastSavedDate = Date()
            }
            return
        }

        isUpdatingFile = true

        let fileURL = getFileURL()
        fileAccessQueue.async { [weak self] in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isUpdatingFile = false
                }
            }
            // ファイルの有無を確認し、なければ作成
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try "".write(to: fileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("❌ Failed to create file: \(error.localizedDescription)")
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

                // 最低限のフィルタリングのみ実施 (avoidApps, minTextLength, isSymbolOrNumber)
                let avoidAppsSet = Set(avoidApps)
                let filteredEntries = textsToSave.filter {
                    !avoidAppsSet.contains($0.appName) &&
                    $0.text.count >= minTextLength &&
                    !$0.text.utf16.isSymbolOrNumber
                }

                // 各エントリを jsonl 形式で追記
                var linesWritten = 0
                for textEntry in filteredEntries {
                    let jsonData = try JSONEncoder().encode(textEntry)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        let jsonLine = jsonString + "\n"
                        if let data = jsonLine.data(using: .utf8) {
                            fileHandle.write(data)
                            linesWritten += 1
                        }
                    }
                }

                // 定期的に追加されたエントリを使って学習 (lmモデルのみ)
                if !filteredEntries.isEmpty && saveCounter % (saveThreshold * 5) == 0 {
                    Task {
                        await self.trainNGramOnNewEntries(newEntries: filteredEntries, n: self.ngramSize, baseFilePattern: "lm")
                    }
                }

                DispatchQueue.main.async {
                    self.texts.removeAll()
                    self.lastSavedDate = Date()
                }
            } catch {
                print("❌ Failed to update file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.texts.removeAll()
                }
            }
        }
    }
    
    private func printFileURL() {
        let fileURL = getFileURL()
        print("File saved at: \(fileURL.path)")
    }
    
    private func removeExtraNewlines(from text: String) -> String {
        // 2連続以上の改行を1つの改行に置き換える正規表現
        let pattern =  "\n+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        let modifiedText = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        return modifiedText ?? text
    }
    
    /// テキストエントリを追加し、条件に応じてファイルに保存
    /// - Parameters:
    ///   - text: 追加するテキスト
    ///   - appName: アプリケーション名
    ///   - saveLineTh: 保存をトリガーする行数閾値
    ///   - saveIntervalSec: 保存をトリガーする時間間隔（秒）
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    func addText(_ text: String, appName: String, saveLineTh: Int = 10, saveIntervalSec: Int = 5, avoidApps: [String], minTextLength: Int) {
        if !isDataSaveEnabled {
            return
        }
        if !text.isEmpty {
            if text.count < minTextLength {
                return
            }
            let cleanedText = removeExtraNewlines(from: text)

            if texts.last?.text == cleanedText {
                return
            }

            if cleanedText.utf16.isSymbolOrNumber {
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

            if !texts.isEmpty && (texts.count >= saveLineTh || intervalFlag) {
                updateFile(avoidApps: avoidApps, minTextLength: minTextLength)
            }

            // 高頻度でMinHashによる重複削除処理を実行
            if saveCounter % 100 == 0 { // 100エントリごとに実行
                Task {
                    await purifyFile(avoidApps: avoidApps, minTextLength: minTextLength) {}
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
                let unreadableFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("unreadableLines.txt")
                let unreadableText = unreadableLines.joined(separator: "\n")
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
        // 仮の保存先
        let tempFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("tempSavedTexts.jsonl")

        loadFromFile { loadedTexts in
            // 空のファイルを防止: ロードしたテキストが空の場合は何もせずに終了
            if loadedTexts.isEmpty {
                print("No texts loaded from file - skipping purify to avoid empty file")
                completion()
                return
            }

            let reversedTexts = loadedTexts.reversed()

            // MinHashを使用した重複検出と削除
            let avoidAppsSet = Set(avoidApps)
            let purifiedResults = self.minHashOptimizer.purifyTextEntriesWithMinHash(
                Array(reversedTexts),
                avoidApps: avoidAppsSet,
                minTextLength: minTextLength,
                similarityThreshold: self.similarityThreshold
            )

            let textEntries = purifiedResults.0
            let duplicatedCount = purifiedResults.1

            // 重複がない、または浄化後のテキストが空になる場合は処理を行わない
            if duplicatedCount == 0 || textEntries.isEmpty {
                print("No duplicates found or purified entries would be empty - skipping file update")
                completion()
                return
            }

            self.fileAccessQueue.async {
                // バックアップファイルの作成 (問題特定用)
                let backupFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("backup_savedTexts_\(Int(Date().timeIntervalSince1970)).jsonl")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: backupFileURL)
                    print("Backup file created at: \(backupFileURL.path)")
                } catch {
                    print("Failed to create backup file: \(error.localizedDescription)")
                    // バックアップ失敗でもプロセスは継続
                }

                // 新規ファイルとして一時ファイルに保存
                do {
                    var tempFileHandle: FileHandle?

                    if !FileManager.default.fileExists(atPath: tempFileURL.path) {
                        FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
                    }

                    tempFileHandle = try FileHandle(forWritingTo: tempFileURL)
                    tempFileHandle?.seekToEndOfFile()

                    // 重要: 一度書き込みを確認してからファイルを置き換える
                    var writeSuccess = false
                    var entriesWritten = 0

                    for textEntry in textEntries {
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

                    // 書き込みが成功してエントリが少なくとも1つ以上の場合のみファイルを置換
                    if writeSuccess && entriesWritten > 0 {
                        // 正常に保存できたら既存ファイルを削除
                        try FileManager.default.removeItem(at: fileURL)
                        // 新規ファイルの名前を変更
                        try FileManager.default.moveItem(at: tempFileURL, to: fileURL)
                        print("File purify completed. Removed \(duplicatedCount) duplicated entries. Wrote \(entriesWritten) entries.")
                        
                        // purify完了時に日時を更新（メインスレッドで実行）
                        DispatchQueue.main.async {
                            self.lastPurifyDate = Date()
                        }
                    } else {
                        print("⚠️ Write was not successful or no entries were written - keeping original file")
                        // 一時ファイルを削除
                        try? FileManager.default.removeItem(at: tempFileURL)
                    }
                } catch {
                    print("Failed to clean and update file: \(error.localizedDescription)")
                    // エラーが発生した場合、一時ファイルを削除する
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
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ensan.inputmethod.azooKeyMac") else {
            print("❌ Failed to get container URL.")
            return
        }
        
        let outputDir = containerURL.appendingPathComponent("Library/Application Support/SwiftNGram").path
        
        do {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return
        }
        
        if baseFilePattern == "lm" {
            let lmCheckURL = URL(fileURLWithPath: outputDir).appendingPathComponent("lm_c_abc.marisa")
            if !fileManager.fileExists(atPath: lmCheckURL.path) {
                let originalFiles = [
                    "original_c_abc.marisa",
                    "original_u_abx.marisa",
                    "original_u_xbc.marisa",
                    "original_r_xbx.marisa",
                ]
                let lmFiles = [
                    "lm_c_abc.marisa",
                    "lm_u_abx.marisa",
                    "lm_u_xbc.marisa",
                    "lm_r_xbx.marisa",
                ]
                for (origFile, lmFile) in zip(originalFiles, lmFiles) {
                    let origPath = URL(fileURLWithPath: outputDir).appendingPathComponent(origFile).path
                    let lmPath = URL(fileURLWithPath: outputDir).appendingPathComponent(lmFile).path
                    if fileManager.fileExists(atPath: origPath) {
                        do {
                            try fileManager.copyItem(atPath: origPath, toPath: lmPath)
                        } catch {
                            print("❌ Error duplicating \(origFile) to \(lmFile): \(error)")
                        }
                    }
                }
            }
        }
        
        let wipFileURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(baseFilePattern).wip")
        do {
            try "Training in progress".write(to: wipFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to create WIP file: \(error)")
        }
        
        await trainNGram(lines: lines, n: ngramSize, baseFilePattern: baseFilePattern, outputDir: outputDir, resumeFilePattern: baseFilePattern)

        do {
            try fileManager.removeItem(at: wipFileURL)
        } catch {
            print("❌ Failed to remove WIP file: \(error)")
        }
    }
    
    
    /// 保存されたテキストエントリからN-gramモデルを学習
    /// - Parameters:
    ///   - n: N-gramのサイズ
    ///   - baseFilename: ベースとなるファイル名
    ///   - maxEntryCount: 最大エントリ数
    func trainNGramFromTextEntries(n: Int = 5, baseFilePattern: String = "original", maxEntryCount: Int = 100_000) async {
        let fileManager = FileManager.default
        
        let savedTexts = await loadFromFileAsync()
        
        let importFileURL = getAppDirectory().appendingPathComponent("import.jsonl")
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
        
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ensan.inputmethod.azooKeyMac") else {
            print("❌ Failed to get container URL.")
            return
        }
        
        let outputDir = containerURL.appendingPathComponent("Library/Application Support/SwiftNGram").path
        
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
            // 必要であればユーザーに通知する処理を追加
            return
        }
        
        var isStale = false
        var importFolderURL: URL?
        
        do {
            // 2. ブックマークデータからURLを解決し、アクセス権を取得
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: [.withSecurityScope], // セキュリティスコープ付きで解決
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("インポートフォルダのブックマークが古くなっています。Settings -> データ管理で再選択してください。")
                // 必要であればユーザーに通知 & ブックマークをクリアする処理
                // shareData.importBookmarkData = nil
                // shareData.importTextPath = ""
                return
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("インポートフォルダへのアクセス権を取得できませんでした: \(url.path)")
                // 必要であればユーザーに通知
                return
            }
            
            // アクセス権を確実に解放するためのdeferブロック
            defer { url.stopAccessingSecurityScopedResource() }
            
            print("インポートフォルダへのアクセス権を取得: \(url.path)")
            importFolderURL = url // アクセス可能なURLを保持

        } catch {
            print("インポートフォルダのブックマーク解決またはアクセス権取得に失敗しました: \(error.localizedDescription)")
            // 必要であればユーザーに通知 & ブックマークをクリアする処理
            // shareData.importBookmarkData = nil
            // shareData.importTextPath = ""
            return
        }
        
        // 3. アクセス可能なURLを使用してインポート処理を実行
        guard let importFolder = importFolderURL else {
             // ここに来ることは通常ないはずだが、念のため
             print("エラー: アクセス可能なインポートフォルダURLがありません。")
             return
        }
        
        // インポートしたファイル数をカウントする変数 (スコープを外に出す)
        var importedFileCount = 0
        // ファイルURLリスト (スコープを外に出す)
        let fileURLs: [URL]
        
        do {
            // importFolder (ブックマークから解決したURL) の内容を取得
            fileURLs = try fileManager.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil, options: [])
        } catch {
             print("❌ Failed to list import folder contents: \(error.localizedDescription)")
             // フォルダ内容の取得に失敗したらここで終了
             return
        }
            
        // フォルダ内容の取得に成功した場合のみ続行
        if fileURLs.isEmpty {
            print("インポートフォルダに処理対象のファイル(.txt)が見つかりません: \(importFolder.path)")
            // ファイルがない場合もShareData更新のために末尾まで進む (必要に応じて)
            // return // ここでreturnするとShareDataが更新されない
        } else {
            print("インポートフォルダから \(fileURLs.count) 個のアイテムを検出: \(importFolder.path)")
        }
            
        // --- ファイルごとの処理 --- 
        do { // エラーハンドリングのためdoブロックは残す
            let existingEntries = await loadFromFileAsync()
            var existingKeys = Set(existingEntries.map { "\($0.appName)-\($0.text)" })
            
            var newEntries: [TextEntry] = []
            // var importedFileCount = 0 // 宣言を上に移動
            
            print("[DEBUG] Starting file processing loop...")
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                print("[DEBUG] Processing file: \(fileName)")
                
                if fileName.hasPrefix("IMPORTED") {
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
                    
                    try markFileAsImported(fileURL: fileURL)
                    importedFileCount += 1 // インポート成功したらカウントアップ
                    print("[DEBUG] Successfully imported and marked: \(fileName)")
                    
                } catch {
                    print("❌ Error processing file \(fileName): \(error.localizedDescription)")
                }
            }
            
            if !newEntries.isEmpty {
                let appDirectory = getAppDirectory()
                let importFileURL = appDirectory.appendingPathComponent("import.jsonl")
                
                do {
                    // import.jsonlへの追記処理に変更
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
                    // 既存の内容と新しい内容を結合して書き込む
                    try (currentContent + newContent).write(to: importFileURL, atomically: true, encoding: .utf8)
                    print("\(newEntries.count) 件の新規エントリを import.jsonl に追記しました。")
                } catch {
                    print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
                }
            }
            
        } catch {
            // このcatchは主にJSONLへの書き込みエラーを捕捉する
            print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
        }
        
        print("[DEBUG] Finished file processing loop.")
        // インポート処理の最後にShareDataを更新
        await MainActor.run { // @Publishedプロパティへのアクセスはメインスレッドで
             print("[DEBUG] Updating ShareData. Imported count: \(importedFileCount)")
             if importedFileCount > 0 {
                 shareData.lastImportedFileCount = importedFileCount
                 shareData.lastImportDate = Date().timeIntervalSince1970
                 print("[DEBUG] Import record updated: \(importedFileCount) files, Date: \(shareData.lastImportDateAsDate?.description ?? "nil")")
             } else if !fileURLs.isEmpty {
                 print("[DEBUG] No new files were imported, but folder was checked. Updating check date.")
                 // ファイルは存在したがインポートされなかった場合 (例: 全てIMPORTED_済み)
                 // 最終チェック日時のみ更新する
                 shareData.lastImportDate = Date().timeIntervalSince1970
                 // lastImportedFileCount は変更しない
             } else {
                 print("[DEBUG] No files found in import folder. Import record not updated.")
             }
        }
    }
    
    /// 指定したファイルを、同じフォルダー内でファイル名の先頭に "IMPORTED_" を付けてリネームする
    private func markFileAsImported(fileURL: URL) throws {
        let fileManager = FileManager.default
        let fileName = fileURL.lastPathComponent
        let importedFileName = "IMPORTED_" + fileName
        let newURL = fileURL.deletingLastPathComponent().appendingPathComponent(importedFileName)
        try fileManager.moveItem(at: fileURL, to: newURL)
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
        let importFileURL = getAppDirectory().appendingPathComponent("import.jsonl")
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
