import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel

    var body: some View {
        VStack {
            Label("Saved Texts", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)

            // 統計ボタン
            Button("統計") {
                print("統計")
            }

            // 最後に保存した時間を表示
            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }

    // 日付フォーマットを定義
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .long
        return formatter
    }
}

struct TextEntry: Codable, Hashable {
    var appName: String
    var text: String
    var timestamp: Date

    // カスタムのハッシュ関数
    func hash(into hasher: inout Hasher) {
        hasher.combine(appName)
        hasher.combine(text)
    }

    // イコール関数のオーバーライド
    static func == (lhs: TextEntry, rhs: TextEntry) -> Bool {
        return lhs.appName == rhs.appName && lhs.text == rhs.text
    }
}

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

            if textHashes.contains(newTextEntry) {
                print("Duplicate text entry detected, not adding.")
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
}
