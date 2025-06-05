import Foundation
@testable import Tuner // Access protocols and TextModel

// MARK: - Mock File Manager

/// FileManaging プロトコルのモック実装
class MockFileManager: FileManaging {

    // MARK: - State Properties

    private var files: [String: Data] = [:]
    private(set) var createdDirectories: Set<String> = []
    var mockContainerURL: URL?
    var shouldThrowOnFileHandleCreation = false
    var shouldThrowOnWrite = false
    var shouldThrowOnRead = false
    var shouldThrowOnDirectoryCreation = false

    // MARK: - Call Tracking Properties

    private(set) var fileExistsCalledPaths: [String] = []
    private(set) var containerURLCalledIdentifiers: [String] = []
    private(set) var createDirectoryCalledURLs: [URL] = []
    private(set) var contentsOfFileCalledURLs: [URL] = []
    private(set) var writeStringCalledURLs: [URL] = []
    private(set) var writeDataCalledURLs: [URL] = []
    private(set) var fileHandleForUpdatingCalledURLs: [URL] = []
    // Track created MockFileHandles to inspect their state
    private(set) var createdMockFileHandles: [URL: MockFileHandle] = [:]
    // Track removed item paths
    private(set) var removeItemCalledPaths: [String] = []

    // MARK: - Initialization

    init(mockContainerURL: URL? = nil) {
        self.mockContainerURL = mockContainerURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MockAppGroupContainer")
        try? FileManager.default.createDirectory(at: self.mockContainerURL!, withIntermediateDirectories: true)
    }

    // MARK: - FileManaging Conformance

    func fileExists(atPath path: String) -> Bool {
        fileExistsCalledPaths.append(path)
        // Check both files and explicitly created directories
        return files[path] != nil || createdDirectories.contains(path)
    }

    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        containerURLCalledIdentifiers.append(groupIdentifier)
        return mockContainerURL
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
        createDirectoryCalledURLs.append(url)
        if shouldThrowOnDirectoryCreation {
            throw MockError.directoryCreationFailed(url: url, error: nil)
        }
        // Add the directory path to our set
        createdDirectories.insert(url.path)
        // Simulate intermediate creation by adding parent directories if needed
        if createIntermediates {
            var parent = url.deletingLastPathComponent()
            while parent.path != "/" && parent.path != mockContainerURL?.path && !createdDirectories.contains(parent.path) {
                 createdDirectories.insert(parent.path)
                 parent.deleteLastPathComponent()
             }
        }
    }

    func contentsOfFile(at url: URL, encoding enc: String.Encoding) throws -> String {
        contentsOfFileCalledURLs.append(url)
        if shouldThrowOnRead {
            throw MockError.readFailed(url: url, error: nil)
        }
        guard let data = files[url.path] else {
            // Use a standard CocoaError for file not found
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: url.path])
        }
        guard let string = String(data: data, encoding: enc) else {
            throw MockError.readFailed(url: url, error: NSError(domain: "MockReadError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode data with specified encoding."]))
        }
        return string
    }

    func write(_ string: String, to url: URL, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding) throws {
        writeStringCalledURLs.append(url)
        if shouldThrowOnWrite {
            throw MockError.writeFailed(url: url, error: nil)
        }
        guard let data = string.data(using: enc) else {
            throw MockError.writeFailed(url: url, error: NSError(domain: "MockWriteError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode string."]))
        }
        // Ensure parent directory exists
        try createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        files[url.path] = data
    }

    func write(_ data: Data, to url: URL, atomically useAuxiliaryFile: Bool) throws {
        writeDataCalledURLs.append(url)
        if shouldThrowOnWrite {
            throw MockError.writeFailed(url: url, error: nil)
        }
        // Ensure parent directory exists
        try createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        files[url.path] = data
    }

    func fileHandleForUpdating(from url: URL) throws -> FileHandleProtocol {
        fileHandleForUpdatingCalledURLs.append(url)
        if shouldThrowOnFileHandleCreation {
            throw FileManagingError.unableToCreateFileHandle(url: url, underlyingError: MockError.operationFailed(operation: "createFileHandle"))
        }

        // Simulate file creation if it doesn't exist (like FileHandle(forUpdating:))
        if files[url.path] == nil {
             try createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
             files[url.path] = Data() // Create empty file
         }

        let initialData = files[url.path] ?? Data()
        let mockHandle = MockFileHandle(url: url, initialData: initialData)
        createdMockFileHandles[url] = mockHandle // Store the handle

        // Set up callbacks to update the MockFileManager's internal state
        mockHandle.onWrite = { [weak self] updatedFullData in
            self?.files[url.path] = updatedFullData
        }
        mockHandle.onClose = { [weak self] finalData in
            self?.files[url.path] = finalData
            // Optionally remove from created handles? Or keep for inspection.
            // print("MockFileHandle closed for \(url.path)")
        }

        return mockHandle
    }

    func removeItem(atPath path: String) throws {
        removeItemCalledPaths.append(path)
        if files.removeValue(forKey: path) == nil && !createdDirectories.contains(path) {
             // Mimic FileManager behavior: throw if item doesn't exist
             // Using CocoaError.fileNoSuchFileError is appropriate here.
             throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue, userInfo: [NSFilePathErrorKey: path])
        }
        // Also remove if it was tracked as a created directory
        createdDirectories.remove(path)
    }
    
    func removeItem(at url: URL) throws {
        try removeItem(atPath: url.path)
    }
    
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
        if files[path] != nil || createdDirectories.contains(path) {
            return [.size: files[path]?.count ?? 0]
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: path])
    }
    
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
        try createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        let dirPath = url.path
        if !createdDirectories.contains(dirPath) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: dirPath])
        }
        
        // Return files and directories that are children of this directory
        let childPaths = files.keys.filter { $0.hasPrefix(dirPath + "/") && !$0.dropFirst(dirPath.count + 1).contains("/") }
        let childDirs = createdDirectories.filter { $0.hasPrefix(dirPath + "/") && !$0.dropFirst(dirPath.count + 1).contains("/") }
        
        let allChildren = childPaths + childDirs
        return allChildren.map { URL(fileURLWithPath: $0) }
    }
    
    func copyItem(at srcURL: URL, to dstURL: URL) throws {
        guard let data = files[srcURL.path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: srcURL.path])
        }
        files[dstURL.path] = data
    }
    
    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try copyItem(at: srcURL, to: dstURL)
        try removeItem(at: srcURL)
    }
    
    func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]?) -> Bool {
        files[path] = data ?? Data()
        return true
    }

    // MARK: - Utility Methods for Tests

    func reset() {
        files.removeAll()
        createdDirectories.removeAll()
        fileExistsCalledPaths.removeAll()
        containerURLCalledIdentifiers.removeAll()
        createDirectoryCalledURLs.removeAll()
        contentsOfFileCalledURLs.removeAll()
        writeStringCalledURLs.removeAll()
        writeDataCalledURLs.removeAll()
        fileHandleForUpdatingCalledURLs.removeAll()
        createdMockFileHandles.removeAll()
        removeItemCalledPaths.removeAll() // Reset the new tracking array
        shouldThrowOnFileHandleCreation = false
        shouldThrowOnWrite = false
        shouldThrowOnRead = false
        shouldThrowOnDirectoryCreation = false
        // Don't delete/recreate the actual temp directory here, just clear internal state
    }

    func setFileContent(_ data: Data, for path: String) {
        let url = URL(fileURLWithPath: path)
        // Ensure parent directory is marked as created
        createdDirectories.insert(url.deletingLastPathComponent().path)
        files[path] = data
    }

    func setFileContent(_ string: String, for path: String, encoding: String.Encoding = .utf8) {
        if let data = string.data(using: encoding) {
            setFileContent(data, for: path)
        }
    }

    func getFileContent(for path: String) -> Data? {
        return files[path]
    }

    func getFileContentAsString(for path: String, encoding: String.Encoding = .utf8) -> String? {
        guard let data = files[path] else { return nil }
        return String(data: data, encoding: encoding)
    }
}

// MockError definition (assuming it's needed here if not defined elsewhere)
/*
enum MockError: Error, LocalizedError {
    // ... cases as defined in MockFileHandle ...
    case fileNotFound(path: String)
    case directoryCreationFailed(url: URL, error: Error?)
    case writeFailed(url: URL, error: Error?)
    case readFailed(url: URL, error: Error?)
    case unableToCreateMockFileHandle(url: URL)
    case fileHandleClosed(operation: String)
    case operationFailed(operation: String, error: Error? = nil)

    var errorDescription: String? {
        // ... descriptions ...
    }
}
*/ 