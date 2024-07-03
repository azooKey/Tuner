//
//  TextModel.swift
//  ContextDatabaseApp
//
//  Created by 高橋直希 on 2024/06/30.
//

import Foundation

class TextModel: ObservableObject {
    @Published var texts: [TextEntry] = []
    @Published var lastSavedDate: Date? = nil
    @Published var isDataSaveEnabled: Bool = true
    private var saveCounter = 0
    private var textHashes: Set<TextEntry> = []
    private let fileAccessQueue = DispatchQueue(label: "com.contextdatabaseapp.fileAccessQueue")
    private var isUpdatingFile = false

    init() {
        createAppDirectory()
        printFileURL() // ファイルパスを表示
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private func getAppDirectory() -> URL {
        let appDirectory = getDocumentsDirectory().appendingPathComponent("ContextDatabaseApp")
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

    private func updateFile() {
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
                        self.updateFile()
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

                fileHandle.seekToEndOfFile()
                fileHandle.write("\n".data(using: .utf8)!)

                // 重複削除
                let uniqueText = self.purifyTextEntries(texts).0
                print("\(uniqueText.count) lines saved to file... \(Date()))")
                // 1行ずつ書き出し
                for textEntry in uniqueText{
                    // JSONエンコード
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

    func addText(_ text: String, appName: String, saveLineTh: Int = 50, saveIntervalSec: Int = 10) {
        // もしもテキスト保存がOFF
        if !isDataSaveEnabled {
            return
        }
        if !text.isEmpty {
            let cleanedText = removeExtraNewlines(from: text)
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

            if saveCounter % saveLineTh == 0 || intervalFlag{
                updateFile()
                saveCounter = 0
            }

            // TODO: ある程度保存したら重複削除
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
                    if error.localizedDescription.contains("The data couldn’t be read because it isn’t in the correct format.") {
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

    func aggregateAppNames(completion: @escaping ([String: Int]) -> Void) {
        loadFromFile { loadedTexts in
            var appNameCounts: [String: Int] = [:]

            for entry in loadedTexts {
                appNameCounts[entry.appName, default: 0] += 1
            }

            completion(appNameCounts)
        }
    }

    func generateStatisticsParameter(avoidApps: [String] = [], completion: @escaping (([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String)) -> Void) {
        // データのクリーンアップ
        purifyFile {
            self.loadFromFile { loadedTexts in
                var textEntries: [TextEntry] = []
                var appNameCounts: [String: Int] = [:]
                var appNameTextCounts: [String: Int] = [:]
                var totalTextLength = 0
                var totalEntries = 0
                var uniqueEntries: Set<String> = []

                var duplicatedCount = 0

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
                }

                var stats = ""
                stats += "Total Text Entries: \(totalEntries)\n"
                stats += "Total Text Length: \(totalTextLength) characters\n"
                let sortedAppNameCounts = appNameCounts.sorted { $0.value > $1.value }
                let sortedAppNameTextCounts = appNameTextCounts.sorted { $0.value > $1.value }

                completion((sortedAppNameCounts, sortedAppNameTextCounts, totalEntries, totalTextLength, stats))
            }
        }
    }

    func purifyFile(completion: @escaping () -> Void) {
        let fileURL = getFileURL()
        // 仮の保存先
        let tempFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("tempSavedTexts.jsonl")

        loadFromFile { loadedTexts in
            let reversedTexts = loadedTexts.reversed()
            let purifiedResults = self.purifyTextEntries(Array(reversedTexts))
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

    func purifyTextEntries(_ entries: [TextEntry]) -> ([TextEntry], Int) {
        var textEntries: [TextEntry] = []
        var uniqueEntries: Set<String> = []
        var duplicatedCount = 0

        for entry in entries {
            let uniqueKey = "\(entry.appName)-\(entry.text)"
            if uniqueEntries.contains(uniqueKey) {
                duplicatedCount += 1
                continue
            }
            uniqueEntries.insert(uniqueKey)
            textEntries.append(entry)
        }

        return (textEntries, duplicatedCount)
    }
}
