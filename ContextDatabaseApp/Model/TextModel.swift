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

    private func saveToFile() {
        let fileURL = getFileURL()
        DispatchQueue.global(qos: .background).async {
            do {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer {
                    fileHandle.closeFile()
                }

                fileHandle.seekToEndOfFile()

                for textEntry in self.texts {
                    let jsonData = try JSONEncoder().encode(textEntry)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        let jsonLine = jsonString + "\n"
                        if let data = jsonLine.data(using: .utf8) {
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
                        self.saveToFile()
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
                saveToFile()
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

        do {
            let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = fileContents.split(separator: "\n")
            for line in lines {
                if let jsonData = line.data(using: .utf8) {
                    let textEntry = try JSONDecoder().decode(TextEntry.self, from: jsonData)
                    loadedTexts.append(textEntry)
                }
            }
        } catch {
            print("Failed to load from file: \(error.localizedDescription)")
        }

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

    func generateStatistics() -> String {
        let loadedTexts = loadFromFile()
        var appNameCounts: [String: Int] = [:]
        var totalTextLength = 0
        var totalEntries = 0

        for entry in loadedTexts {
            appNameCounts[entry.appName, default: 0] += 1
            totalTextLength += entry.text.count
            totalEntries += 1
        }

        var stats = "App Name Counts:\n"
        for (appName, count) in appNameCounts {
            stats += "\(appName): \(count)\n"
        }
        stats += "\nTotal Text Entries: \(totalEntries)\n"
        stats += "Total Text Length: \(totalTextLength) characters\n"
        stats += "Average Text Length: \(totalEntries > 0 ? totalTextLength / totalEntries : 0) characters\n"

        return stats
    }
}
