import SwiftUI

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(textModel.texts, id: \.self) { text in
                    Text(text)
                        .padding()
                }
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
            // Open file handle
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer {
                fileHandle.closeFile()
            }

            // Move to end of file
            fileHandle.seekToEndOfFile()

            for text in texts {
                if let data = "\(text)\n".data(using: .utf8) {
                    fileHandle.write(data)
                }
            }

            // Clear texts array after saving
            texts.removeAll()
        } catch {
            print("Failed to save texts: \(error.localizedDescription)")
        }
    }

    private func printFileURL() {
        let fileURL = getFileURL()
        print("File saved at: \(fileURL.path)")
    }

    // 空文字列を除外してテキストを追加するメソッド
    func addText(_ text: String) {
        if !text.isEmpty {
            texts.append(text)
            saveToFile()
        }
    }
}
