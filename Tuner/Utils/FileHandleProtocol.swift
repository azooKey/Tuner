import Foundation

/// FileHandle の機能を抽象化するプロトコル (macOS 13+/iOS 16+ API に準拠)
protocol FileHandleProtocol {
    var offsetInFile: UInt64 { get }
    func seekToEnd() throws -> UInt64
    func seek(toOffset offset: UInt64) throws
    func read(upToCount count: Int) throws -> Data?
    func write<T: DataProtocol>(contentsOf data: T) throws
    func close() throws
}

/// 既存の FileHandle を FileHandleProtocol に準拠させる
extension FileHandle: FileHandleProtocol {} 