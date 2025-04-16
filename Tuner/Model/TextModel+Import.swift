import Foundation

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
            return
        }
        
        var isStale = false
        var importFolderURL: URL?
        
        do {
            // 2. ブックマークデータからURLを解決し、アクセス権を取得
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: [.withSecurityScope],
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("インポートフォルダのブックマークが古くなっています。Settings -> データ管理で再選択してください。")
                return
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                print("インポートフォルダへのアクセス権を取得できませんでした: \(url.path)")
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            print("インポートフォルダへのアクセス権を取得: \(url.path)")
            importFolderURL = url

        } catch {
            print("インポートフォルダのブックマーク解決またはアクセス権取得に失敗しました: \(error.localizedDescription)")
            return
        }
        
        guard let importFolder = importFolderURL else {
            print("エラー: アクセス可能なインポートフォルダURLがありません。")
            return
        }
        
        var importedFileCount = 0
        let fileURLs: [URL]
        
        do {
            fileURLs = try fileManager.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil, options: [])
        } catch {
            print("❌ Failed to list import folder contents: \(error.localizedDescription)")
            return
        }
            
        if fileURLs.isEmpty {
            print("インポートフォルダに処理対象のファイル(.txt)が見つかりません: \(importFolder.path)")
        } else {
            print("インポートフォルダから \(fileURLs.count) 個のアイテムを検出: \(importFolder.path)")
        }
            
        do {
            let existingEntries = await loadFromFileAsync()
            var existingKeys = Set(existingEntries.map { "\($0.appName)-\($0.text)" })
            
            var newEntries: [TextEntry] = []
            
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                print("[DEBUG] Processing file: \(fileName)")
                
                // インポート状態を確認
                if isFileImported(fileName) {
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
                    
                    // ファイルをインポート済みとしてマーク
                    markFileAsImported(fileName, jsonlFileName: generateJsonlFileName(for: fileName), lastModifiedDate: Date())
                    importedFileCount += 1
                    print("[DEBUG] Successfully imported: \(fileName)")
                    
                } catch {
                    print("❌ Error processing file \(fileName): \(error.localizedDescription)")
                }
            }
            
            if !newEntries.isEmpty {
                let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
                
                do {
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
                    try (currentContent + newContent).write(to: importFileURL, atomically: true, encoding: .utf8)
                    print("\(newEntries.count) 件の新規エントリを import.jsonl に追記しました。")
                } catch {
                    print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
                }
            }
            
        } catch {
            print("❌ Failed to write import.jsonl: \(error.localizedDescription)")
        }
        
        print("[DEBUG] Finished file processing loop.")
        await MainActor.run {
            print("[DEBUG] Updating ShareData. Imported count: \(importedFileCount)")
            if importedFileCount > 0 {
                shareData.lastImportedFileCount = importedFileCount
                shareData.lastImportDate = Date().timeIntervalSince1970
                print("[DEBUG] Import record updated: \(importedFileCount) files, Date: \(shareData.lastImportDateAsDate?.description ?? "nil")")
            } else if !fileURLs.isEmpty {
                print("[DEBUG] No new files were imported, but folder was checked. Updating check date.")
                shareData.lastImportDate = Date().timeIntervalSince1970
            } else {
                print("[DEBUG] No files found in import folder. Import record not updated.")
            }
        }
    }
}

// MARK: - インポート履歴のリセット
extension TextModel {
    /// import.jsonl ファイルを削除し、ShareDataのインポート履歴をリセットする
    func resetImportHistory(shareData: ShareData) async {
        let fileManager = FileManager.default
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
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
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
} 