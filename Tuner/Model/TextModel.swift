//
//  TextModel.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/06/30.
//

import Foundation
import EfficientNGram

enum SimpleHasher {
    static func customHash(_ input: some Collection<Unicode.Scalar>, seed: Int) -> Int {
        var hash = seed
        for char in input {
            hash = (hash &* 31) &+ Int(char.value)
        }
        return hash
    }
}

struct MinHashOptimized {
    private let numHashFunctions: Int
    private let seeds: [Int]

    init(numHashFunctions: Int = 20) {
        self.numHashFunctions = numHashFunctions
        self.seeds = (0..<numHashFunctions).map { _ in Int.random(in: Int.min...Int.max) }
    }

    func computeMinHashSignature(for text: String) -> [Int] {
        let words = text.unicodeScalars.split(separator: " ")
        return self.seeds.map { seed in
            var minHash = Int.max
            for word in words {
                let hash = SimpleHasher.customHash(word, seed: seed)
                if hash < minHash {
                    minHash = hash
                }
            }
            return minHash
        }
    }

    func computeJaccardSimilarity(signature1: [Int], signature2: [Int]) -> Double {
        assert(signature1.count == signature2.count, "signature1 and signature2 must have the same length")
        let equalCount = zip(signature1, signature2).reduce(into: 0) {
            if $1.0 == $1.1 {
                $0 += 1
            }
        }
        return Double(equalCount) / Double(signature1.count)
    }
}

struct TextModelOptimizedWithLRU {
    private let minHash = MinHashOptimized()
    private var signatureCache: [String: [Int]]
    private var seenEntries: Set<String> = []

    init() {
        self.signatureCache = .init(minimumCapacity: 100)
    }

    mutating func purifyTextEntriesWithMinHash(
        _ entries: [TextEntry], avoidApps: Set<String>, minTextLength: Int,
        similarityThreshold: Double = 0.8
    ) -> ([TextEntry], Int) {
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0

        for (index, entry) in entries.enumerated() {
            guard !avoidApps.contains(entry.appName), entry.text.utf8.count >= minTextLength else { continue }

            if signatureCache.keys.contains(entry.text) || seenEntries.contains(entry.text) {
                duplicateCount += 1
                continue
            }

            let newEntrySignature: [Int]
            if let cachedSignature = self.signatureCache[entry.text] {
                newEntrySignature = cachedSignature
            } else {
                newEntrySignature = minHash.computeMinHashSignature(for: entry.text)
                signatureCache[entry.text] = newEntrySignature
            }

            var isDuplicate = false
            for uniqueEntry in uniqueEntries {
                let existingSignature: [Int]
                if let cachedSignature = signatureCache[uniqueEntry.text] {
                    existingSignature = cachedSignature
                } else {
                    existingSignature = minHash.computeMinHashSignature(for: uniqueEntry.text)
                    signatureCache[uniqueEntry.text] = existingSignature
                }

                if minHash.computeJaccardSimilarity(signature1: newEntrySignature, signature2: existingSignature) >= similarityThreshold {
                    isDuplicate = true
                    duplicateCount += 1
                    break
                }
            }

            if !isDuplicate {
                uniqueEntries.append(entry)
            }

            if index % 100 == 0 {
                self.seenEntries.formUnion(self.signatureCache.keys)
                self.signatureCache.removeAll(keepingCapacity: true)
            }
        }

        return (uniqueEntries, duplicateCount)
    }
}

class TextModel: ObservableObject {
    @Published var texts: [TextEntry] = []
    @Published var lastSavedDate: Date? = nil
    @Published var isDataSaveEnabled: Bool = true

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

        isUpdatingFile = true

        let fileURL = getFileURL()
        fileAccessQueue.async { [weak self] in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isUpdatingFile = false
                }
            }
            // ファイルの有無を確認
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                print("File does not exist")
                self.fileAccessQueue.async {
                    do {
                        // ファイルが存在しない場合、新しく作成
                        let jsonData = try JSONEncoder().encode(TextEntry(appName: "App", text: "Sample", timestamp: Date()))
                        try jsonData.write(to: fileURL, options: .atomic)
                        self.updateFile(avoidApps: avoidApps, minTextLength: minTextLength)
                    } catch {
                        print("Failed to create file: \(error.localizedDescription)")
                    }
                }
            }

            do {
                let fileHandle = try FileHandle(forUpdating: fileURL)
                defer {
                    fileHandle.closeFile()
                }

                // 末尾に移動して改行を追加
                fileHandle.seekToEndOfFile()
                fileHandle.write("\n".data(using: .utf8)!)

                // texts 配列内のエントリを前処理（重複排除等）して新規エントリ群を取得
                // MinHashを使用した重複除去
                let avoidAppsSet = Set(avoidApps)
                let (newEntries, duplicateCount) = self.minHashOptimizer.purifyTextEntriesWithMinHash(
                    self.texts,
                    avoidApps: avoidAppsSet,
                    minTextLength: minTextLength,
                    similarityThreshold: self.similarityThreshold
                )

                print("\(newEntries.count) new entries saved to file... \(Date())")
                print("Duplicates removed: \(duplicateCount)")

                // 各エントリを jsonl 形式で追記
                for textEntry in newEntries {
                    let jsonData = try JSONEncoder().encode(textEntry)
                    // JSON文字列に変換してファイルに書き込み
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        let jsonLine = jsonString + "\n"
                        if let data = jsonLine.data(using: .utf8) {
                            fileHandle.write(data)
                        } else {
                            print("Failed to encode data to write \(jsonLine)")
                        }
                    }
                }

                // newEntries を使い、追加学習を実施
                Task {
                    print("=== Incremental Training from New Text Entries ===")
                    await self.trainNGramOnNewEntries(newEntries: newEntries, n: self.ngramSize, baseFilename: "lm")
                }

                DispatchQueue.main.async {
                    self.texts.removeAll()
                    self.lastSavedDate = Date() // 保存日時を更新
                    self.clearMemory()
                }
            } catch {
                print("Failed to update file: \(error.localizedDescription)")
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

    func addText(_ text: String, appName: String, saveLineTh: Int = 50, saveIntervalSec: Int = 10, avoidApps: [String], minTextLength: Int) {
        // もしもテキスト保存がOFF
        if !isDataSaveEnabled {
            return
        }
        if !text.isEmpty {
            if text.count < minTextLength {
                return
            }
            let cleanedText = removeExtraNewlines(from: text)

            // 完全一致であればskip
            if texts.last?.text == cleanedText {
                return
            }

            // 記号か数字のみのテキストはスキップ
            if cleanedText.utf16.isSymbolOrNumber {
                return
            }

            // 最後のテキストの前方一致文字列であればやめる
            let lastText = texts.last?.text.utf16 ?? "".utf16
            if cleanedText.utf16.starts(with: lastText) && texts.count > 0 {
                texts.removeLast()
            } else if lastText.starts(with: cleanedText.utf16) {
                return
            }

            let timestamp = Date()
            let newTextEntry = TextEntry(appName: appName, text: cleanedText, timestamp: timestamp)

            texts.append(newTextEntry)
            saveCounter += 1

            // 最後の保存から10秒経過していたら
            let intervalFlag : Bool = {
                if let lastSavedDate = lastSavedDate {
                    let interval = Date().timeIntervalSince(lastSavedDate)
                    return Int(interval) > saveIntervalSec
                } else {
                    return true
                }
            }()

            if saveCounter % saveLineTh == 0 || intervalFlag {
                updateFile(avoidApps: avoidApps, minTextLength: minTextLength)
            }

            // 10回の保存ごとにファイルを浄化
            if saveCounter > saveLineTh * 10 {
                // 重複削除のためファイルを浄化
                purifyFile(avoidApps: avoidApps, minTextLength: minTextLength) { [weak self] in
                    self?.updateFile(avoidApps: avoidApps, minTextLength: minTextLength)
                }
                saveCounter = 0
            }
        }
    }

    private func clearMemory() {
        texts = []
    }

    func loadFromFile(completion: @escaping ([TextEntry]) -> Void) {
        let fileURL = getFileURL()
        fileAccessQueue.async {
            var loadedTexts: [TextEntry] = []
            var unreadableLines: [String] = []

            // ファイルの有無を確認
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                print("File does not exist")
                DispatchQueue.main.async {
                    completion(loadedTexts)
                }
                return
            }

            // ファイルを読み込む
            var fileContents = ""
            do {
                fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                print("Failed to load from file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            // ファイルを1行ずつ読み込む
            var skipCount = 0
            let lines = fileContents.split(separator: "\n")
            print("total lines: \(lines.count)")
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
                    print("Failed to load from file: \(error.localizedDescription)")
                    if error.localizedDescription.contains("The data couldn't be read because it isn't in the correct format.") {
                        print("line: \(line)")
                    }
                    // FIXME: 読めない行を一旦スキップ
                    skipCount += 1
                    unreadableLines.append(String(line))
                    continue
                }
            }
            print("skipCount: \(skipCount)")
            // 読めなかった行を追加で保存
            if unreadableLines.count > 0 {
                let unreadableFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("unreadableLines.txt")
                let unreadableText = unreadableLines.joined(separator: "\n")
                do {
                    try unreadableText.write(to: unreadableFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save unreadable lines: \(error.localizedDescription)")
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

    func aggregateAppNames(completion: @escaping ([String: Int]) -> Void) {
        loadFromFile { loadedTexts in
            var appNameCounts: [String: Int] = [:]

            for entry in loadedTexts {
                appNameCounts[entry.appName, default: 0] += 1
            }

            completion(appNameCounts)
        }
    }

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

    func purifyFile(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        let fileURL = getFileURL()
        // 仮の保存先
        let tempFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("tempSavedTexts.jsonl")

        loadFromFile { loadedTexts in
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

            if duplicatedCount == 0 {
                completion()
                return
            }

            self.fileAccessQueue.async {
                // 新規ファイルとして一時ファイルに保存
                do {
                    var tempFileHandle: FileHandle?

                    if !FileManager.default.fileExists(atPath: tempFileURL.path) {
                        FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
                    }

                    tempFileHandle = try FileHandle(forWritingTo: tempFileURL)
                    tempFileHandle?.seekToEndOfFile()

                    for textEntry in textEntries {
                        let jsonData = try JSONEncoder().encode(textEntry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            let jsonLine = jsonString + "\n"
                            if let data = jsonLine.data(using: .utf8) {
                                tempFileHandle?.write(data)
                            }
                        }
                    }

                    tempFileHandle?.closeFile()

                    // 正常に保存できたら既存ファイルを削除
                    try FileManager.default.removeItem(at: fileURL)
                    // 新規ファイルの名前を変更
                    try FileManager.default.moveItem(at: tempFileURL, to: fileURL)
                    print("File purify completed. Removed \(duplicatedCount) duplicated entries.")
                } catch {
                    print("Failed to clean and update file: \(error.localizedDescription)")
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

    /// 今回 updateFile で書き出した新規エントリ newEntries を使い、n-gram モデルを追加学習します
    /// 追加学習用のベースは、初回は「original」を複製した「lm」として用意し、以降はlmに学習を追加していきます。
    func trainNGramOnNewEntries(newEntries: [TextEntry], n: Int, baseFilename: String) async {
        let lines = newEntries.map { $0.text }
        print("追加学習 \(lines)")
        if lines.isEmpty {
            print("追加学習なし")
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

        // lmモードの場合、lm用ファイルが存在しなければ original から複製して lm を作成
        if baseFilename == "lm" {
            let lmCheckURL = URL(fileURLWithPath: outputDir).appendingPathComponent("lm_c_abc.marisa")
            if !fileManager.fileExists(atPath: lmCheckURL.path) {
                print("lmモデルが存在しないため、originalから複製を実施します。")
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
                            print("Duplicated \(origFile) to \(lmFile)")
                        } catch {
                            print("Error duplicating \(origFile) to \(lmFile): \(error)")
                        }
                    }
                }
            }
        }

        // WIP ファイルの作成
        let wipFileURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(baseFilename).wip")
        do {
            try "Training in progress".write(to: wipFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to create WIP file: \(error)")
        }

        // EfficientNGram パッケージ側の学習関数を呼び出す（async/await 版）
        await trainNGram(lines: lines, n: ngramSize, baseFilename: baseFilename, outputDir: outputDir)

        // WIP ファイルの削除
        do {
            try fileManager.removeItem(at: wipFileURL)
            print("✅ Training completed. WIP file removed.")
        } catch {
            print("❌ Failed to remove WIP file: \(error)")
        }

        print("✅ Training completed for new entries. Model saved as \(baseFilename) in \(outputDir)")
    }


    /// 保存された jsonl ファイルからテキスト部分のみのリストを抽出し、学習を行う
    func trainNGramFromTextEntries(n: Int = 5, baseFilename: String = "original", maxEntryCount: Int = 100_000) async {
        print("train ngram from jsonl")
        let fileManager = FileManager.default

        // savedTexts.jsonlからエントリを読み込み
        let savedTexts = await loadFromFileAsync()
        print("savedTexts.jsonl: \(savedTexts.count)")

        // import.jsonlのパスを取得
        let importFileURL = getAppDirectory().appendingPathComponent("import.jsonl")
        var importEntries: [TextEntry] = []
        if fileManager.fileExists(atPath: importFileURL.path) {
            // ファイルの内容を読み込み、各行ごとにJSONデコード
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
        print("importText: \(importEntries.count)")

        // 両方のエントリを結合し、最新のmaxEntryCount件を使用する
        let combinedEntries = savedTexts + importEntries
        let trainingEntries = combinedEntries.suffix(maxEntryCount)
        let lines = trainingEntries.map { $0.text }

        print("Training with \(lines.count) lines")

        // containerディレクトリの取得と出力先ディレクトリの作成
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.dev.ensan.inputmethod.azooKeyMac") else {
            print("❌ Failed to get container URL.")
            return
        }

        let outputDir = containerURL.appendingPathComponent("Library/Application Support/SwiftNGram").path

        // ディレクトリを作成
        do {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return
        }

        // baseFilenameが"original"の場合、既存のlmファイルを削除する
        if baseFilename == "original" {
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
                        print("Removed existing lm file: \(lmFile)")
                    } catch {
                        print("Failed to remove lm file \(lmFile): \(error)")
                    }
                }
            }
        }

        // n-gram学習の実行
        await trainNGram(lines: lines, n: n, baseFilename: baseFilename, outputDir: outputDir)

        print("✅ Training completed and model saved as \(baseFilename) in \(outputDir)")
    }
}

// MARK: - テキストファイルからのインポート処理
extension TextModel {
    /// Documents/ImportTexts フォルダ内の .txt ファイルを読み込み、
    /// 各行を個別のエントリーとしてimport.jsonlへ出力します。
    /// 読み込んだ（または条件に合わなかった）ファイルは、ファイル名の先頭に "IMPORTED_" を付けてリネームします。
    func importTextFiles(avoidApps: [String], minTextLength: Int) async {
        print("import files")
        let fileManager = FileManager.default
        // Documentsディレクトリ内の "ImportTexts" フォルダのURLを取得
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importFolder = documentsDirectory.appendingPathComponent("ImportTexts")

        // "ImportTexts" フォルダが存在しなければ作成
        if !fileManager.fileExists(atPath: importFolder.path) {
            print("ImportTexts Folder doesn't exist")
            do {
                try fileManager.createDirectory(at: importFolder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("❌ Failed to create import folder: \(error.localizedDescription)")
                return
            }
        }

        // "ImportTexts" フォルダ内のファイル一覧を取得
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil, options: [])
            if fileURLs.isEmpty {
                print("No files to import in \(importFolder.path)")
            }

            // すでに保存済みのエントリを取得してキー集合を作成（キー＝ "appName-テキスト"）
            let existingEntries = await loadFromFileAsync()
            var existingKeys = Set(existingEntries.map { "\($0.appName)-\($0.text)" })

            var newEntries: [TextEntry] = []

            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                // 既に "IMPORTED" で始まるファイルはスキップ
                if fileName.hasPrefix("IMPORTED") {
                    continue
                }

                // 拡張子が txt のファイルのみ対象
                if fileURL.pathExtension.lowercased() != "txt" {
                    continue
                }

                do {
                    let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                    // ファイル内の各行ごとに分割
                    let lines = fileContent.components(separatedBy: .newlines)
                    // ファイル名（拡張子除く）を appName として利用
                    let fileAppName = fileURL.deletingPathExtension().lastPathComponent

                    // 同じファイル内での重複も防ぐため、ローカルなキー集合を用意
                    var localKeys = existingKeys

                    for line in lines {
                        // 改行等を除去して整形
                        let cleanedLine = removeExtraNewlines(from: line)

                        // 空行や最小文字数未満の場合はスキップ
                        if cleanedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cleanedLine.count < minTextLength {
                            continue
                        }

                        let key = "\(fileAppName)-\(cleanedLine)"
                        // すでに同じ内容が取り込まれていればスキップ
                        if localKeys.contains(key) {
                            continue
                        }

                        localKeys.insert(key)
                        existingKeys.insert(key)

                        let newEntry = TextEntry(appName: fileAppName, text: cleanedLine, timestamp: Date())
                        newEntries.append(newEntry)
                    }

                    // 処理が完了したら、ファイル名の先頭に "IMPORTED_" を付けてリネーム
                    try markFileAsImported(fileURL: fileURL)

                } catch {
                    print("❌ Error processing file \(fileName): \(error.localizedDescription)")
                }
            }

            // 新規エントリがあればimport.jsonlに書き出し（既存のものは上書き）
            if !newEntries.isEmpty {
                let appDirectory = getAppDirectory()
                let importFileURL = appDirectory.appendingPathComponent("import.jsonl")

                do {
                    var fileContent = ""
                    for entry in newEntries {
                        let jsonData = try JSONEncoder().encode(entry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            fileContent.append(jsonString + "\n")
                        }
                    }
                    try fileContent.write(to: importFileURL, atomically: true, encoding: .utf8)
                    print("import.jsonl updated with \(newEntries.count) entries at \(importFileURL.path)")
                } catch {
                    print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
                }
            }

        } catch {
            print("❌ Failed to list import folder: \(error.localizedDescription)")
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
