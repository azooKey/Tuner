import SwiftUI

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

        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }
}


class TextModel: ObservableObject {
    @Published var texts: [String] = []

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
        return getAppDirectory().appendingPathComponent("savedTexts.txt")
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
        do {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer {
                fileHandle.closeFile()
            }

            fileHandle.seekToEndOfFile()

            for text in texts {
                if let data = "\(text)\n".data(using: .utf8) {
                    fileHandle.write(data)
                }
            }

            texts.removeAll()
        } catch {
            print("Failed to save texts: \(error.localizedDescription)")
        }
    }

    private func printFileURL() {
        let fileURL = getFileURL()
        print("File saved at: \(fileURL.path)")
    }

    private func removeExtraNewlines(from text: String) -> String {
        // 2連続以上の改行を1つの改行に置き換える正規表現
        let pattern = "\n{2,}"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        let modifiedText = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\n")
        return modifiedText ?? text
    }

    func addText(_ text: String) {
        if !text.isEmpty {
            let cleanedText = removeExtraNewlines(from: text)
            texts.append(cleanedText)
            saveToFile()
        }
    }
}
