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

    private func getFileURL() -> URL {
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

    private func UpdateFile() {
        let fileURL = getFileURL()
        DispatchQueue.global(qos: .background).async {
            do {
                let fileHandle = try FileHandle(forUpdating: fileURL)
                defer {
                    fileHandle.closeFile()
                }

                fileHandle.seekToEndOfFile()
                fileHandle.write("\n".data(using: .ascii)!)
                for textEntry in self.texts {
                    let jsonData = try JSONEncoder().encode(textEntry)
                    if let jsonString = String(data: jsonData, encoding: .ascii) {

                        let jsonLine = jsonString + "\n"
                        if let data = jsonLine.data(using: .ascii) {
                            fileHandle.write(data)
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.texts.removeAll()
                    self.lastSavedDate = Date() // 保存日時を更新
                    self.clearMemory()
                }
            } catch {
                DispatchQueue.main.async {
                    do {
                        // ファイルが存在しない場合、新しく作成
                        let jsonData = try JSONEncoder().encode(TextEntry(appName: "App", text: "Sample", timestamp: Date()))
                        try jsonData.write(to: fileURL, options: .atomic)
                        self.UpdateFile()
                    } catch {
                        print("Failed to create file: \(error.localizedDescription)")
                    }
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

    func addText(_ text: String, appName: String) {
        // もしもテキスト保存がOFF
        if !isDataSaveEnabled {
            return
        }
        if !text.isEmpty {
            let cleanedText = removeExtraNewlines(from: text)
            let timestamp = Date()
            let newTextEntry = TextEntry(appName: appName, text: cleanedText, timestamp: timestamp)

            // 重複がある場合は保存をしない
            if textHashes.contains(newTextEntry) {
                return
            } else {
                textHashes.insert(newTextEntry)
            }

            texts.append(newTextEntry)
            saveCounter += 1

            if saveCounter >= 50 {
                print("Saving to file... \(Date()))")
                UpdateFile()
                saveCounter = 0
            }
        }
    }

    private func clearMemory() {
        texts = []
    }

    func loadFromFile() -> [TextEntry] {
        let fileURL = getFileURL()
        var loadedTexts: [TextEntry] = []

        // ファイルの有無を確認
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            print("File does not exist")
            return loadedTexts
        }

        // ファイルを読み込む
        var fileContents = ""
        do {
            fileContents = try String(contentsOf: fileURL, encoding: .ascii)
        }catch{
            print("Failed to load from file: \(error.localizedDescription)")
            return []
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
                if let jsonData = line.data(using: .ascii) {
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
                continue
            }
        }
        print("skipCount: \(skipCount)")
        return loadedTexts
    }

    func aggregateAppNames() -> [String: Int] {
        let loadedTexts = loadFromFile()
        var appNameCounts: [String: Int] = [:]

        for entry in loadedTexts {
            appNameCounts[entry.appName, default: 0] += 1
        }

        return appNameCounts
    }

    func generateStatisticsParameter(avoidApps: [String] = []) async -> ([(key: String, value: Int)], [(key: String, value: Int)], Int, Int, String) {
        // データのクリーンアップ
        do{
            try await purifyFile()
        }catch{
            print("Failed to purify file: \(error.localizedDescription)")
        }

        // ファイルが存在するか確認し、ないなら空のデータを返す
        let fileURL = getFileURL()
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return ([], [], 0, 0, "")
        }
        
        var textEntries: [TextEntry] = []
        let loadedTexts = loadFromFile()
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
        stats += "Average Text Length: \(totalEntries > 0 ? totalTextLength / totalEntries : 0) characters\n"

        let sortedAppNameCounts = appNameCounts.sorted { $0.value > $1.value }
        let sortedAppNameTextCounts = appNameTextCounts.sorted { $0.value > $1.value }

        return (sortedAppNameCounts, sortedAppNameTextCounts, totalEntries, totalTextLength, stats)
    }

    func purifyFile() async {
        let fileURL = getFileURL()
        // 仮の保存先
        let tempFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("tempSavedTexts.jsonl")
        
        // 逆順にして重複があったときに最新のデータを残す
        let loadedTexts: [TextEntry] = loadFromFile().reversed()
        var textEntries: [TextEntry] = []
        var duplicatedCount = 0

        do{
             (textEntries, duplicatedCount) = try await purifyTextEntries(loadedTexts)
        }catch{
            print("Failed to purify file: \(error.localizedDescription)")
        }

        if duplicatedCount == 0 {
            return
        }

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
                if let jsonString = String(data: jsonData, encoding: .ascii) {
                    let jsonLine = jsonString + "\n"
                    if let data = jsonLine.data(using: .ascii) {
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
    }

    func purifyTextEntries(_ entries: [TextEntry]) async throws ->( [TextEntry], Int) {
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

        if duplicatedCount == 0 {
            print("No duplicated entries found.")
        } else {
            print("Removed \(duplicatedCount) duplicated entries.")
        }

        return (textEntries, duplicatedCount)
    }
}
