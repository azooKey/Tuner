//
//  MinHashUtils.swift
//  Tuner
//
//  Created by 高橋直希 on 2025/03/08.
//

import Foundation

/// シンプルなハッシュ関数を提供する列挙型
/// - 文字列のハッシュ値を計算
/// - シード値を使用して異なるハッシュ値を生成
enum SimpleHasher {
    /// 文字列のハッシュ値を計算
    /// - Parameters:
    ///   - input: ハッシュ計算対象の文字列
    ///   - seed: ハッシュ計算に使用するシード値
    /// - Returns: 計算されたハッシュ値
    static func customHash(_ input: some Collection<Unicode.Scalar>, seed: Int) -> Int {
        var hash = seed
        for char in input {
            hash = (hash &* 31) &+ Int(char.value)
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

    /// 初期化
    /// - Parameters:
    ///   - numHashFunctions: 使用するハッシュ関数の数（デフォルト: 20）
    init(numHashFunctions: Int = 20) {
        self.numHashFunctions = numHashFunctions
        self.seeds = (0..<numHashFunctions).map { _ in Int.random(in: Int.min...Int.max) }
    }

    /// テキストのMinHashシグネチャを計算
    /// - Parameters:
    ///   - text: シグネチャを計算するテキスト
    /// - Returns: 計算されたMinHashシグネチャ
    func computeMinHashSignature(for text: String) -> [Int] {
        let words = text.unicodeScalars.split(separator: " ")
        return self.seeds.map { seed in
            var minHash = Int.max
            for word in words {
                let hash = SimpleHasher.customHash(word, seed: seed)
                if hash < minHash {
                    minHash = hash
                }
            }
            return minHash
        }
    }

    /// 2つのシグネチャ間のJaccard類似度を計算
    /// - Parameters:
    ///   - signature1: 1つ目のシグネチャ
    ///   - signature2: 2つ目のシグネチャ
    /// - Returns: 計算された類似度（0.0-1.0）
    func computeJaccardSimilarity(signature1: [Int], signature2: [Int]) -> Double {
        assert(signature1.count == signature2.count, "signature1 and signature2 must have the same length")
        let equalCount = zip(signature1, signature2).reduce(into: 0) {
            if $1.0 == $1.1 {
                $0 += 1
            }
        }
        return Double(equalCount) / Double(signature1.count)
    }
}

/// LRUキャッシュを使用した最適化されたテキストモデル
/// - MinHashを使用したテキストの重複検出
/// - メモリ使用量を最適化
struct TextModelOptimizedWithLRU {
    /// MinHash計算用のインスタンス
    private let minHash = MinHashOptimized()
    /// シグネチャのキャッシュ（LRU方式）
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
    ///   - similarityThreshold: 類似度の閾値（デフォルト: 0.8）
    /// - Returns: 重複を除去したエントリと重複数
    mutating func purifyTextEntriesWithMinHash(
        _ entries: [TextEntry], avoidApps: Set<String>, minTextLength: Int,
        similarityThreshold: Double = 0.8
    ) -> ([TextEntry], Int) {
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0

        for (index, entry) in entries.enumerated() {
            // 除外アプリと最小テキスト長のチェック
            guard !avoidApps.contains(entry.appName), entry.text.utf8.count >= minTextLength else { continue }

            // キャッシュと既処理エントリのチェック
            if signatureCache.keys.contains(entry.text) || seenEntries.contains(entry.text) {
                duplicateCount += 1
                continue
            }

            // 新しいエントリのシグネチャを計算
            let newEntrySignature: [Int]
            if let cachedSignature = self.signatureCache[entry.text] {
                newEntrySignature = cachedSignature
            } else {
                newEntrySignature = minHash.computeMinHashSignature(for: entry.text)
                signatureCache[entry.text] = newEntrySignature
            }

            // 既存エントリとの類似度チェック
            var isDuplicate = false
            for uniqueEntry in uniqueEntries {
                let existingSignature: [Int]
                if let cachedSignature = signatureCache[uniqueEntry.text] {
                    existingSignature = cachedSignature
                } else {
                    existingSignature = minHash.computeMinHashSignature(for: uniqueEntry.text)
                    signatureCache[uniqueEntry.text] = existingSignature
                }

                if minHash.computeJaccardSimilarity(signature1: newEntrySignature, signature2: existingSignature) >= similarityThreshold {
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
