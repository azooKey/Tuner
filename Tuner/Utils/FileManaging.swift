import Foundation

/// ファイル操作を抽象化するプロトコル
protocol FileManaging {
    // MARK: - File Existence and Properties
    func fileExists(atPath path: String) -> Bool
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any]

    // MARK: - Directory Operations
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL]

    // MARK: - File Reading
    func contentsOfFile(at url: URL, encoding enc: String.Encoding) throws -> String

    // MARK: - File Writing
    func write(_ string: String, to url: URL, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding) throws
    func write(_ data: Data, to url: URL, atomically useAuxiliaryFile: Bool) throws

    // MARK: - File Handle Operations
    func fileHandleForUpdating(from url: URL) throws -> FileHandleProtocol // Returns the protocol type
    
    // MARK: - File Deletion
    func removeItem(atPath path: String) throws
    func removeItem(at url: URL) throws
    
    // MARK: - File Operations
    func copyItem(at srcURL: URL, to dstURL: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]?) -> Bool
}

// エラー定義（必要に応じて）
enum FileManagingError: Error {
    case unableToCreateFileHandle(url: URL, underlyingError: Error?)
    // 他のエラーケースを追加可能
} 