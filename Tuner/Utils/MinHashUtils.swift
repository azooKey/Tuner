//
//  MinHashUtils.swift
//  Tuner
//
//  Created by 高橋直希 on 2025/03/08.
//

import Foundation

/// シンプルなハッシュ関数を提供する列挙型（高速化版）
/// - 文字列のハッシュ値を計算
/// - シード値を使用して異なるハッシュ値を生成
enum SimpleHasher {
    /// 文字列のハッシュ値を計算（高速化版）
    /// - Parameters:
    ///   - input: ハッシュ計算対象の文字列
    ///   - seed: ハッシュ計算に使用するシード値
    /// - Returns: 計算されたハッシュ値
    static func customHash(_ input: String, seed: Int) -> Int {
        var hash = seed
        for char in input.utf16 {
            hash = (hash &* 31) &+ Int(char)
        }
        return hash
    }
}

/// MinHashアルゴリズムの最適化実装
/// - テキストの類似度を効率的に計算
/// - 複数のハッシュ関数を使用して精度を向上
struct MinHashOptimized {
    /// 使用するハッシュ関数の数
    private let numHashFunctions: Int
    /// 各ハッシュ関数で使用するシード値
    private let seeds: [Int]
    private let similarityThreshold: Double
    private let sequenceLength: Int

    init(numHashFunctions: Int = 20, similarityThreshold: Double = 0.7, sequenceLength: Int = 3) {
        // CPU使用率を抑えるためハッシュ関数数とシーケンス長を削減
        self.numHashFunctions = min(numHashFunctions, 20) // 最大20に制限
        self.seeds = (0..<self.numHashFunctions).map { $0 * 31 + 17 } // 乱数より高速な固定値
        self.similarityThreshold = similarityThreshold
        self.sequenceLength = max(sequenceLength, 2) // 最小2文字
    }

    // テキストの前処理を行う
    internal func preprocessText(_ text: String) -> String {
        // 空白を除去
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 全角スペースを半角に変換
        let normalizedSpace = trimmed.replacingOccurrences(of: "　", with: " ")
        // 連続するスペースを1つに
        let singleSpace = normalizedSpace.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return singleSpace
    }

    // テキストを文字列のシーケンスに分割（高速化版）
    internal func splitText(_ text: String) -> [String] {
        let processedText = preprocessText(text)
        let length = self.sequenceLength
        
        guard processedText.count >= length else {
            return processedText.isEmpty ? [] : [processedText]
        }
        
        var sequences: [String] = []
        sequences.reserveCapacity(processedText.count - length + 1)
        
        let startIndex = processedText.startIndex
        for i in 0...(processedText.count - length) {
            let start = processedText.index(startIndex, offsetBy: i)
            let end = processedText.index(start, offsetBy: length)
            sequences.append(String(processedText[start..<end]))
        }
        
        return sequences
    }

    func computeMinHashSignature(for text: String) -> [Int] {
        // 空文字列や短すぎるテキストの早期処理
        guard text.count >= sequenceLength else {
            return seeds.map { _ in text.hashValue }
        }
        
        let sequences = splitText(text)
        guard !sequences.isEmpty else {
            return seeds.map { _ in 0 }
        }
        
        // ハッシュ計算の最適化：事前にシーケンスのハッシュ値を計算
        var sequenceHashes: [Int] = []
        sequenceHashes.reserveCapacity(sequences.count)
        
        for sequence in sequences {
            sequenceHashes.append(sequence.hashValue)
        }
        
        return self.seeds.map { seed in
            var minHash = Int.max
            for sequenceHash in sequenceHashes {
                let hash = sequenceHash &* seed // ビット演算で高速化
                if hash < minHash {
                    minHash = hash
                }
            }
            return minHash == Int.max ? 0 : minHash
        }
    }

    /// 2つのシグネチャ間のJaccard類似度を計算（高速化版）
    /// - Parameters:
    ///   - signature1: 1つ目のシグネチャ
    ///   - signature2: 2つ目のシグネチャ
    /// - Returns: 計算された類似度（0.0-1.0）
    func computeJaccardSimilarity(signature1: [Int], signature2: [Int]) -> Double {
        let count = min(signature1.count, signature2.count)
        guard count > 0 else { return 0.0 }
        
        var equalCount = 0
        for i in 0..<count {
            if signature1[i] == signature2[i] {
                equalCount += 1
            }
        }
        return Double(equalCount) / Double(count)
    }

    // テキストの類似性を判定（高速化版）
    func isSimilar(_ text1: String, _ text2: String) -> Bool {
        // 長さの差が大きい場合は早期終了
        let lengthDiff = abs(text1.count - text2.count)
        let maxLength = max(text1.count, text2.count)
        if maxLength > 0 && Double(lengthDiff) / Double(maxLength) > 0.5 {
            return false
        }
        
        let signature1 = computeMinHashSignature(for: text1)
        let signature2 = computeMinHashSignature(for: text2)
        let similarity = computeJaccardSimilarity(signature1: signature1, signature2: signature2)
        return similarity >= similarityThreshold
    }
}

/// LRUキャッシュを使用した最適化されたテキストモデル
/// - MinHashを使用したテキストの重複検出
/// - メモリ使用量を最適化
struct TextModelOptimizedWithLRU {
    private let minHash = MinHashOptimized(similarityThreshold: 0.7)
    private var signatureCache: [String: [Int]]
    /// 既に処理済みのテキストエントリ
    private var seenEntries: Set<String> = []

    /// 初期化
    /// - キャッシュの初期容量を設定
    init() {
        self.signatureCache = .init(minimumCapacity: 100)
    }

    /// MinHashを使用してテキストエントリの重複を除去
    /// - Parameters:
    ///   - entries: 処理対象のテキストエントリ
    ///   - avoidApps: 除外するアプリケーション名のセット
    ///   - minTextLength: 最小テキスト長
    ///   - similarityThreshold: 類似度の閾値（デフォルト: 0.7）
    /// - Returns: 重複を除去したエントリと重複数
    mutating func purifyTextEntriesWithMinHash(
        _ entries: [TextEntry], avoidApps: Set<String>, minTextLength: Int,
        similarityThreshold: Double = 0.7
    ) -> ([TextEntry], Int) {
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0

        for (index, entry) in entries.enumerated() {
            // 除外アプリと最小テキスト長のチェック
            guard !avoidApps.contains(entry.appName), entry.text.utf8.count >= minTextLength else { continue }

            // 既存のエントリとの類似性チェック
            var isDuplicate = false
            for uniqueEntry in uniqueEntries {
                if minHash.isSimilar(entry.text, uniqueEntry.text) {
                    isDuplicate = true
                    duplicateCount += 1
                    break
                }
            }

            // 重複でない場合は追加
            if !isDuplicate {
                uniqueEntries.append(entry)
            }

            // 定期的にキャッシュをクリア
            if index % 100 == 0 {
                self.seenEntries.formUnion(self.signatureCache.keys)
                self.signatureCache.removeAll(keepingCapacity: true)
            }
        }

        return (uniqueEntries, duplicateCount)
    }
}

/// LRUキャッシュの実装
/// - 最も使用されていないアイテムを自動的に削除
/// - メモリ使用量を制限しながら高速アクセスを提供
class LRUCache<Key: Hashable, Value> {
    private class Node {
        var key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    private let capacity: Int
    private var cache: [Key: Node] = [:]
    private let head = Node(key: "" as! Key, value: "" as! Value) // ダミーヘッド
    private let tail = Node(key: "" as! Key, value: "" as! Value) // ダミーテール
    private let queue = DispatchQueue(label: "com.tuner.lrucache", attributes: .concurrent)
    
    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        head.next = tail
        tail.prev = head
    }
    
    /// キャッシュから値を取得
    func get(_ key: Key) -> Value? {
        return queue.sync {
            guard let node = cache[key] else { return nil }
            // ノードを最前面に移動
            moveToHead(node)
            return node.value
        }
    }
    
    /// キャッシュに値を設定
    func set(_ key: Key, value: Value) {
        queue.async(flags: .barrier) {
            if let node = self.cache[key] {
                // 既存のノードを更新
                node.value = value
                self.moveToHead(node)
            } else {
                // 新しいノードを追加
                let newNode = Node(key: key, value: value)
                self.cache[key] = newNode
                self.addToHead(newNode)
                
                // 容量を超えた場合は最も使用されていないノードを削除
                if self.cache.count > self.capacity {
                    if let tailNode = self.removeTail() {
                        self.cache.removeValue(forKey: tailNode.key)
                    }
                }
            }
        }
    }
    
    /// キャッシュをクリア
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
            self.head.next = self.tail
            self.tail.prev = self.head
        }
    }
    
    /// 現在のキャッシュサイズを取得
    var count: Int {
        return queue.sync { cache.count }
    }
    
    // MARK: - Private Methods
    
    private func addToHead(_ node: Node) {
        node.prev = head
        node.next = head.next
        head.next?.prev = node
        head.next = node
    }
    
    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
    }
    
    private func moveToHead(_ node: Node) {
        removeNode(node)
        addToHead(node)
    }
    
    private func removeTail() -> Node? {
        guard let tailNode = tail.prev, tailNode !== head else { return nil }
        removeNode(tailNode)
        return tailNode
    }
}