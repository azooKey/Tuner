import Foundation
import PDFKit

// MARK: - Import Error Types
enum ImportError: LocalizedError {
    case invalidPDFFile(url: URL)
    case passwordProtectedPDF(url: URL)
    case pdfTooLarge(url: URL, size: Int)
    case memoryPressure(url: URL)
    case pdfCorrupted(url: URL)
    
    var errorDescription: String? {
        switch self {
        case .invalidPDFFile(let url):
            return "PDFファイルを開くことができませんでした: \(url.lastPathComponent)"
        case .passwordProtectedPDF(let url):
            return "パスワード保護されたPDFファイルはサポートされていません: \(url.lastPathComponent)"
        case .pdfTooLarge(let url, let size):
            return "PDFファイルが大きすぎます (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))): \(url.lastPathComponent)"
        case .memoryPressure(let url):
            return "メモリ不足のためPDFファイルを処理できませんでした: \(url.lastPathComponent)"
        case .pdfCorrupted(let url):
            return "PDFファイルが破損している可能性があります: \(url.lastPathComponent)"
        }
    }
}

// MARK: - テキストファイルからのインポート処理
extension TextModel {
    // サポートされているファイル拡張子
    private static let supportedFileExtensions = ["txt", "md", "pdf"]
    /// テキストファイルからインポートを実行
    /// - Parameters:
    ///   - shareData: 共有データオブジェクト (インポートパスとブックマークを含む)
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    func importTextFiles(shareData: ShareData, avoidApps: [String], minTextLength: Int) async {
        
        // 1. インポートフォルダURLの解決とアクセス権取得
        guard let importFolderURL = await resolveImportFolderURL(shareData: shareData) else {
            return // エラーメッセージは resolveImportFolderURL 内で表示
        }
        defer { importFolderURL.stopAccessingSecurityScopedResource() }
        
        // 2. フォルダ内のファイルを処理
        await processFilesInFolder(importFolderURL, shareData: shareData, avoidApps: avoidApps, minTextLength: minTextLength)
        
        print("[DEBUG] Finished import process.")
    }
    
    /// インポートフォルダのURLを解決し、アクセス権を取得する
    private func resolveImportFolderURL(shareData: ShareData) async -> URL? {
        guard let bookmarkData = shareData.importBookmarkData else {
            print("インポートフォルダが設定されていません。Settings -> データ管理でフォルダを選択してください。")
            return nil
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: [.withSecurityScope], // Security scope を要求
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("インポートフォルダのブックマークが古くなっています。Settings -> データ管理で再選択してください。")
                // 必要であれば shareData.importBookmarkData = nil などでリセット
                return nil
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("インポートフォルダへのアクセス権を取得できませんでした: \(url.path)")
                // ここでアクセス権が失われている可能性。ユーザーに再選択を促す。
                return nil
            }
            
            print("インポートフォルダへのアクセス権を取得: \(url.path)")
            return url
        } catch {
            print("インポートフォルダのブックマーク解決またはアクセス権取得に失敗しました: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 指定されたフォルダ内のテキストファイルを処理する
    private func processFilesInFolder(_ folderURL: URL, shareData: ShareData, avoidApps: [String], minTextLength: Int) async {
        let fileManager = self.fileManager
        var importedFileCount = 0
        var newEntries: [TextEntry] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [URLResourceKey](), options: [])
            
            if fileURLs.isEmpty {
                let extensions = Self.supportedFileExtensions.map { ".\($0)" }.joined(separator: ", ")
                print("インポートフォルダに処理対象のファイル(\(extensions))が見つかりません: \(folderURL.path)")
            } else {
                print("インポートフォルダから \(fileURLs.count) 個のアイテムを検出: \(folderURL.path)")
            }
            
            let existingEntries = await loadFromFileAsync()
            var existingKeys = Set(existingEntries.map { "\($0.appName)-\($0.text)" })
            
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                print("[DEBUG] Processing file: \(fileName)")
                
                let fileExtension = fileURL.pathExtension.lowercased()
                if !Self.supportedFileExtensions.contains(fileExtension) {
                    print("[DEBUG] Skipping unsupported file type: \(fileName)")
                    continue
                }
                
                // PDFファイルのサイズ制限チェック
                if fileExtension == "pdf" {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                        let fileSize = resourceValues.fileSize ?? 0
                        let maxPDFSize = 50 * 1024 * 1024 // 50MB制限
                        
                        if fileSize > maxPDFSize {
                            print("[WARNING] Skipping large PDF file: \(fileName) (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))")
                            continue
                        }
                    } catch {
                        print("[WARNING] Could not check file size for: \(fileName)")
                        continue
                    }
                }
                
                if isFileImported(fileName) {
                    print("[DEBUG] Skipping already imported file: \(fileName)")
                    continue
                }
                
                if let processedEntries = await processSingleFile(fileURL, existingKeys: &existingKeys, minTextLength: minTextLength) {
                    newEntries.append(contentsOf: processedEntries)
                    // ファイルをインポート済みとしてマーク (成功時のみ)
                    markFileAsImported(fileName, jsonlFileName: generateJsonlFileName(for: fileName), lastModifiedDate: Date()) // TODO: Use actual modification date?
                    importedFileCount += 1
                    print("[DEBUG] Successfully processed and marked as imported: \(fileName)")
                } else {
                     print("❌ Error or no new entries found in file \(fileName)")
                }
            }
            
        } catch {
            print("❌ Failed to list import folder contents: \(error.localizedDescription)")
            // フォルダ内容取得失敗時は ShareData を更新しない
            return
        }
        
        // 新規エントリがあれば import.jsonl に追記
        if !newEntries.isEmpty {
            await appendNewEntriesToJsonl(newEntries)
        }
        
        // ShareData を更新
        await updateImportShareData(shareData: shareData, importedCount: importedFileCount, folderWasChecked: true)
    }
    
    /// 単一のファイルを処理し、新規エントリを返す（TXT、MD、PDFをサポート）
    private func processSingleFile(_ fileURL: URL, existingKeys: inout Set<String>, minTextLength: Int) async -> [TextEntry]? {
        var newEntriesForFile: [TextEntry] = []
        let fileAppName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension.lowercased()
        
        do {
            let fileContent: String
            
            // ファイル種類に応じてコンテンツを抽出
            switch fileExtension {
            case "txt", "md":
                fileContent = try String(contentsOf: fileURL, encoding: .utf8)
            case "pdf":
                fileContent = try extractTextFromPDF(fileURL)
            default:
                print("❌ Unsupported file type: \(fileExtension)")
                return nil
            }
            
            let lines = fileContent.components(separatedBy: .newlines)
            
            for line in lines {
                let cleanedLine = removeExtraNewlines(from: line)
                
                if cleanedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cleanedLine.count < minTextLength {
                    continue
                }
                
                let key = "\(fileAppName)-\(cleanedLine)"
                if !existingKeys.contains(key) {
                    existingKeys.insert(key)
                    let newEntry = TextEntry(appName: fileAppName, text: cleanedLine, timestamp: Date())
                    newEntriesForFile.append(newEntry)
                }
            }
            return newEntriesForFile // 成功時はエントリ配列を返す (空の場合も含む)
        } catch {
            print("❌ Error processing file content for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            return nil // エラー時は nil を返す
        }
    }
    
    /// PDFファイルからテキストを抽出する
    private func extractTextFromPDF(_ fileURL: URL) throws -> String {
        // PDF文書を開く
        guard let pdfDocument = PDFDocument(url: fileURL) else {
            throw ImportError.invalidPDFFile(url: fileURL)
        }
        
        // パスワード保護の確認
        if pdfDocument.isLocked {
            throw ImportError.passwordProtectedPDF(url: fileURL)
        }
        
        // ページ数の確認
        let pageCount = pdfDocument.pageCount
        if pageCount == 0 {
            throw ImportError.pdfCorrupted(url: fileURL)
        }
        
        // メモリ使用量の監視開始
        let initialMemory = getMemoryUsage()
        let maxMemoryIncrease = 100 * 1024 * 1024 // 100MB増加まで許可
        
        var pageTexts: [String] = []
        
        // ページごとにテキストを抽出
        for pageIndex in 0..<pageCount {
            autoreleasepool {
                guard let page = pdfDocument.page(at: pageIndex) else { return }
                
                // メモリ使用量チェック
                if pageIndex % 10 == 0 { // 10ページごとにチェック
                    let currentMemory = getMemoryUsage()
                    if currentMemory - initialMemory > maxMemoryIncrease {
                        print("[WARNING] High memory usage detected while processing PDF: \(fileURL.lastPathComponent)")
                    }
                }
                
                if let pageText = page.string {
                    pageTexts.append(pageText)
                }
            }
        }
        
        // 配列を結合してフルテキストを作成
        let fullText = pageTexts.joined(separator: "\n")
        
        // 抽出されたテキストが空の場合
        if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[WARNING] No text extracted from PDF: \(fileURL.lastPathComponent)")
        }
        
        return fullText
    }
    
    /// 現在のメモリ使用量を取得する
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
    
    /// 新規エントリを import.jsonl に追記する
    private func appendNewEntriesToJsonl(_ newEntries: [TextEntry]) async {
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl")
        let fileManager = self.fileManager
        
        do {
            var currentContent = ""
            // 既存ファイルの内容を読み込み、末尾に改行がなければ追加
            if fileManager.fileExists(atPath: importFileURL.path) {
                currentContent = try String(contentsOf: importFileURL, encoding: .utf8)
                if !currentContent.isEmpty && !currentContent.hasSuffix("\n") {
                    currentContent += "\n"
                }
            }
            
            // 新規エントリをJSONL形式で文字列に追加
            var newContent = ""
            for entry in newEntries {
                if let jsonData = try? JSONEncoder().encode(entry),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    newContent.append(jsonString + "\n")
                }
            }
            
            // ファイルに書き込み
            if !newContent.isEmpty {
                try (currentContent + newContent).write(to: importFileURL, atomically: true, encoding: .utf8)
                print("\(newEntries.count) 件の新規エントリを import.jsonl に追記しました。")
            }
            
        } catch {
            print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
        }
    }
    
    /// ShareDataのインポート関連情報を更新する
    @MainActor // ShareDataのプロパティはMainActor上で更新する必要がある
    private func updateImportShareData(shareData: ShareData, importedCount: Int, folderWasChecked: Bool) {
        print("[DEBUG] Updating ShareData. Imported count: \(importedCount)")
        if importedCount > 0 {
            shareData.lastImportedFileCount = importedCount
            shareData.lastImportDate = Date().timeIntervalSince1970
            print("[DEBUG] Import record updated: \(importedCount) files, Date: \(shareData.lastImportDateAsDate?.description ?? "nil")")
        } else if folderWasChecked {
            // ファイルはチェックしたが新規インポートはなかった場合も、最終チェック日時を更新
            print("[DEBUG] No new files were imported, but folder was checked. Updating check date.")
            shareData.lastImportDate = Date().timeIntervalSince1970
        } else {
            // フォルダ自体が見つからない、アクセスできない等の場合は更新しない
            print("[DEBUG] Import folder could not be accessed or was empty. Import record not updated.")
        }
    }
}

// MARK: - インポート履歴のリセット
extension TextModel {
    /// import.jsonl ファイルを削除し、ShareDataのインポート履歴をリセットする
    func resetImportHistory(shareData: ShareData) async {
        let fileManager = self.fileManager
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
        
        do {
            // import.jsonlを削除
            if fileManager.fileExists(atPath: importFileURL.path) {
                try fileManager.removeItem(at: importFileURL)
                print("Deleted import.jsonl successfully.")
            } else {
                print("import.jsonl does not exist, skipping deletion.")
            }
            
            // インポート状態をリセット
            resetImportStatus()
            
            // ShareDataの値をリセット
            await MainActor.run {
                shareData.lastImportDate = nil
                shareData.lastImportedFileCount = -1
                print("Import history in ShareData reset.")
            }
        } catch {
            print("❌ Failed to reset import history: \(error.localizedDescription)")
        }
    }
    
    // import.jsonlファイルから読み込むメソッド
    func loadFromImportFile(completion: @escaping ([TextEntry]) -> Void) {
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
        fileAccessQueue.async {
            var loadedTexts: [TextEntry] = []
            
            if !self.fileManager.fileExists(atPath: importFileURL.path) {
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
    
    // loadFromImportFile を async/await でラップした関数
    func loadFromImportFileAsync() async -> [TextEntry] {
        await withCheckedContinuation { continuation in
            self.loadFromImportFile { loadedTexts in
                continuation.resume(returning: loadedTexts)
            }
        }
    }
} 