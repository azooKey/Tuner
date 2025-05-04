import Foundation
@testable import Tuner // Access FileHandleProtocol

/// テスト用の FileHandleProtocol モック実装
class MockFileHandle: FileHandleProtocol {
    private(set) var url: URL
    private(set) var currentOffset: UInt64 = 0
    private(set) var internalData: Data
    private(set) var isClosed = false

    // コールバック用クロージャ
    var onWrite: ((Data) -> Void)?
    var onClose: ((Data) -> Void)?

    var offsetInFile: UInt64 { return currentOffset }

    // 書き込まれたデータを追跡（主にテストでの検証用）
    private(set) var writtenData: Data = Data()
    // エラーをスローするかどうかのフラグ
    var shouldThrowOnSeekToEnd = false
    var shouldThrowOnSeekToOffset = false
    var shouldThrowOnRead = false
    var shouldThrowOnWrite = false
    var shouldThrowOnClose = false

    init(url: URL, initialData: Data = Data()) {
        self.url = url
        self.internalData = initialData
    }

    // MARK: - FileHandleProtocol Conformance

    func seekToEnd() throws -> UInt64 {
        guard !isClosed else { throw MockError.fileHandleClosed(operation: "seekToEnd") }
        if shouldThrowOnSeekToEnd { throw MockError.operationFailed(operation: "seekToEnd") }
        currentOffset = UInt64(internalData.count)
        return currentOffset
    }

    func seek(toOffset offset: UInt64) throws {
        guard !isClosed else { throw MockError.fileHandleClosed(operation: "seekToOffset") }
        if shouldThrowOnSeekToOffset { throw MockError.operationFailed(operation: "seekToOffset") }
        // Allow seeking beyond the end (like FileHandle)
        currentOffset = offset
    }

    func read(upToCount count: Int) throws -> Data? {
        guard !isClosed else { throw MockError.fileHandleClosed(operation: "read") }
        if shouldThrowOnRead { throw MockError.operationFailed(operation: "read") }
        guard currentOffset < internalData.count else { return nil } // EOF

        let start = Int(currentOffset)
        let availableCount = internalData.count - start
        let bytesToRead = min(count, availableCount)
        guard bytesToRead > 0 else { return nil }

        let end = start + bytesToRead
        let subdata = internalData[start..<end]
        currentOffset += UInt64(bytesToRead)
        return subdata
    }

    func write<T: DataProtocol>(contentsOf data: T) throws {
        guard !isClosed else { throw MockError.fileHandleClosed(operation: "write") }
        if shouldThrowOnWrite { throw MockError.operationFailed(operation: "write") }

        let dataToWrite = Data(data)
        let dataLength = dataToWrite.count

        if currentOffset + UInt64(dataLength) > internalData.count {
            let neededSize = Int(currentOffset) + dataLength
            internalData.count = neededSize
        }

        let range = Int(currentOffset)..<(Int(currentOffset) + dataLength)
        internalData.replaceSubrange(range, with: dataToWrite)
        writtenData.append(dataToWrite)
        currentOffset += UInt64(dataLength)
        onWrite?(internalData)
    }

    func close() throws {
        if !isClosed {
            if shouldThrowOnClose { throw MockError.operationFailed(operation: "close") }
            isClosed = true
            onClose?(internalData)
        }
    }
}

// MARK: - MockError Extension for FileHandle Errors

// Ensure MockError exists (likely defined in MockFileManager.swift or another mock file)
// If not, define it here or import the file containing it.
// Adding specific cases for file handle operations.
enum MockError: Error, LocalizedError {
    case fileNotFound(path: String)
    case directoryCreationFailed(url: URL, error: Error?)
    case writeFailed(url: URL, error: Error?)
    case readFailed(url: URL, error: Error?)
    case unableToCreateMockFileHandle(url: URL)
    case fileHandleClosed(operation: String)
    case operationFailed(operation: String, error: Error? = nil)

    var errorDescription: String? {
        switch self {
        // ... (other cases) ...
        case .fileNotFound(let path):
            return "Mock file not found at path: \(path)"
        case .directoryCreationFailed(let url, let error):
            return "Mock directory creation failed for \(url.path). Error: \(error?.localizedDescription ?? "Unknown")"
        case .writeFailed(let url, let error):
             return "Mock write failed for \(url.path). Error: \(error?.localizedDescription ?? "Unknown")"
        case .readFailed(let url, let error):
            return "Mock read failed for \(url.path). Error: \(error?.localizedDescription ?? "Unknown")"
        case .unableToCreateMockFileHandle(let url):
            return "Mock unable to create file handle for \(url.path)"
        case .fileHandleClosed(let operation):
            return "MockFileHandle: Cannot perform '\(operation)' on a closed file."
        case .operationFailed(let operation, let error):
            return "MockFileHandle: Operation '\(operation)' failed. Error: \(error?.localizedDescription ?? "Simulated failure")"
        }
    }
} 