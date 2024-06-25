import SwiftUI

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // 何を表示しようかな
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }
}


class TextModel: ObservableObject {
    @Published var texts: [String] = [] {
        didSet {
            saveToFile()
        }
    }

    init() {
        createAppDirectory()
        loadFromFile()
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
        do {
            let data = try JSONEncoder().encode(texts)
            try data.write(to: getFileURL())
        } catch {
            print("Failed to save texts: \(error.localizedDescription)")
        }
    }

    private func loadFromFile() {
        let fileURL = getFileURL()
        do {
            let data = try Data(contentsOf: fileURL)
            texts = try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("Failed to load texts: \(error.localizedDescription)")
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
        }
    }
}
