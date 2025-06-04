import Foundation

// MARK: - インポート状態管理
extension TextModel {
    /// インポート状態を管理する構造体
    struct ImportStatus: Codable {
        struct FileInfo: Codable {
            var importDate: Date
            var jsonlFileName: String
            var lastModifiedDate: Date
        }
        var importedFiles: [String: FileInfo] // ファイル名: ファイル情報
    }
    
    /// インポート状態ファイルのURLを取得
    func getImportStatusFileURL() -> URL {
        return getTextEntryDirectory().appendingPathComponent("import_status.json") // Use TextEntry directory
    }
    
    /// インポート状態を読み込む
    func loadImportStatus() -> ImportStatus {
        let fileURL = getImportStatusFileURL()
        guard self.fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let status = try? JSONDecoder().decode(ImportStatus.self, from: data) else {
            return ImportStatus(importedFiles: [:])
        }
        return status
    }
    
    /// インポート状態を保存する
    func saveImportStatus(_ status: ImportStatus) {
        let fileURL = getImportStatusFileURL()
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: fileURL)
        }
    }
    
    /// インポート状態をリセットする
    func resetImportStatus() {
        let fileURL = getImportStatusFileURL()
        try? self.fileManager.removeItem(at: fileURL)
    }
    
    /// ファイルがインポート済みかどうかを確認
    func isFileImported(_ fileName: String) -> Bool {
        let status = loadImportStatus()
        return status.importedFiles[fileName] != nil
    }
    
    /// ファイルのJSONLファイル名を生成
    func generateJsonlFileName(for fileName: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "imported_\(fileName)_\(timestamp).jsonl"
    }
    
    /// ファイルをインポート済みとしてマーク
    func markFileAsImported(_ fileName: String, jsonlFileName: String, lastModifiedDate: Date) {
        var status = loadImportStatus()
        status.importedFiles[fileName] = ImportStatus.FileInfo(
            importDate: Date(),
            jsonlFileName: jsonlFileName,
            lastModifiedDate: lastModifiedDate
        )
        saveImportStatus(status)
    }
    
    /// ファイルの最終更新日時を取得
    func getFileLastModifiedDate(_ fileURL: URL) -> Date? {
        do {
            let attributes = try self.fileManager.attributesOfItem(atPath: fileURL.path)
            return attributes[FileAttributeKey.modificationDate] as? Date
        } catch {
            print("❌ Failed to get file modification date: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// ファイルが更新されているかどうかを確認
    func isFileUpdated(_ fileName: String, currentModifiedDate: Date) -> Bool {
        let status = loadImportStatus()
        guard let fileInfo = status.importedFiles[fileName] else {
            return false
        }
        return currentModifiedDate > fileInfo.lastModifiedDate
    }
} 