import Foundation

/// FileManager を使用する FileManaging プロトコルのデフォルト実装
class DefaultFileManager: FileManaging {
    private let fileManager = FileManager.default

    func fileExists(atPath path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }

    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }
    
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
        return try fileManager.attributesOfItem(atPath: path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }

    func contentsOfFile(at url: URL, encoding enc: String.Encoding) throws -> String {
        // リトライ機構付きファイル読み込み
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let content = try String(contentsOf: url, encoding: enc)
                if attempt > 1 {
                    print("✅ Successfully read file at \(url.path) on attempt \(attempt)")
                }
                return content
            } catch {
                lastError = error
                print("❌ Attempt \(attempt) failed to read file at \(url.path): \(error)")
                
                if attempt == 1 {
                    // 最初の試行で失敗した場合、詳細情報を表示
                    print("   File exists: \(fileManager.fileExists(atPath: url.path))")
                    if fileManager.fileExists(atPath: url.path) {
                        do {
                            let attributes = try fileManager.attributesOfItem(atPath: url.path)
                            print("   File size: \(attributes[.size] ?? "unknown")")
                            print("   File permissions: \(attributes[.posixPermissions] ?? "unknown")")
                        } catch {
                            print("   Could not get file attributes: \(error)")
                        }
                    }
                }
                
                if attempt < 3 {
                    // 少し待ってからリトライ
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        throw lastError ?? FileManagingError.unableToCreateFileHandle(url: url, underlyingError: nil)
    }

    func write(_ string: String, to url: URL, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding) throws {
        try string.write(to: url, atomically: useAuxiliaryFile, encoding: enc)
    }

    func write(_ data: Data, to url: URL, atomically useAuxiliaryFile: Bool) throws {
        // Use .atomic write option for Data
        try data.write(to: url, options: useAuxiliaryFile ? .atomic : [])
    }

    func fileHandleForUpdating(from url: URL) throws -> FileHandleProtocol {
        do {
            // FileHandle conforms to FileHandleProtocol
            let fileHandle = try FileHandle(forUpdating: url)
            return fileHandle
        } catch {
            throw FileManagingError.unableToCreateFileHandle(url: url, underlyingError: error)
        }
    }
    
    func removeItem(atPath path: String) throws {
        // リトライ機構付きファイル削除
        var lastError: Error?
        for attempt in 1...3 {
            do {
                try fileManager.removeItem(atPath: path)
                if attempt > 1 {
                    print("✅ Successfully removed file at \(path) on attempt \(attempt)")
                }
                return
            } catch {
                lastError = error
                print("❌ Attempt \(attempt) failed to remove file at \(path): \(error)")
                
                if attempt == 1 && fileManager.fileExists(atPath: path) {
                    // 最初の試行で失敗した場合、詳細情報を表示
                    do {
                        let attributes = try fileManager.attributesOfItem(atPath: path)
                        print("   File permissions: \(attributes[.posixPermissions] ?? "unknown")")
                        print("   File owner: \(attributes[.ownerAccountName] ?? "unknown")")
                    } catch {
                        print("   Could not get file attributes: \(error)")
                    }
                }
                
                if attempt < 3 {
                    // 少し待ってからリトライ
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        throw lastError ?? FileManagingError.unableToCreateFileHandle(url: URL(fileURLWithPath: path), underlyingError: nil)
    }
    
    func removeItem(at url: URL) throws {
        try removeItem(atPath: url.path)
    }
    
    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try fileManager.copyItem(at: srcURL, to: dstURL)
    }
    
    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try fileManager.moveItem(at: srcURL, to: dstURL)
    }
    
    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]?) -> Bool {
        return fileManager.createFile(atPath: path, contents: data, attributes: attr)
    }
} 