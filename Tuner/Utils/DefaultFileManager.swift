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

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    func contentsOfFile(at url: URL, encoding enc: String.Encoding) throws -> String {
        return try String(contentsOf: url, encoding: enc)
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
} 