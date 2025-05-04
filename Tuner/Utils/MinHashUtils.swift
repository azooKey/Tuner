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
    private let similarityThreshold: Double
    private let sequenceLength: Int

    init(numHashFunctions: Int = 50, similarityThreshold: Double = 0.7, sequenceLength: Int = 5) {
        self.numHashFunctions = numHashFunctions
        self.seeds = (0..<numHashFunctions).map { _ in Int.random(in: Int.min...Int.max) }
        self.similarityThreshold = similarityThreshold
        self.sequenceLength = sequenceLength
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

    // テキストを文字列のシーケンスに分割
    internal func splitText(_ text: String) -> [[Unicode.Scalar]] {
        let processedText = preprocessText(text)
        // 文字列を指定された長さのシーケンスに分割
        var sequences: [[Unicode.Scalar]] = []
        let scalars = Array(processedText.unicodeScalars)

        // sequenceLength を使うように変更
        let length = self.sequenceLength
        guard scalars.count >= length else { // テキストがシーケンス長より短い場合は、テキスト全体を1つのシーケンスとする
            if !scalars.isEmpty {
                sequences.append(Array(scalars))
            }
            return sequences
        }

        for index in 0...(scalars.count - length) { // ループ範囲を修正
            let sequence = Array(scalars[index..<index + length]) // sequenceLength を使うように変更
            sequences.append(sequence)
        }
        // 注意: テキスト末尾のシーケンス長未満の部分は現在含まれていません。必要に応じて追加してください。

        return sequences
    }

    func computeMinHashSignature(for text: String) -> [Int] {
        let sequences = splitText(text)
        return self.seeds.map { seed in
            var minHash = Int.max
            for sequence in sequences {
                let hash = SimpleHasher.customHash(sequence, seed: seed)
                if hash < minHash {
                    minHash = hash
                }
            }
            // もしminHashがInt.maxのままなら（理論上はngramsが空でない限り起こらないはず）、
            // 0を返すなど、明確なデフォルト値を設定することも検討できる
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

    // テキストの類似性を判定
    func isSimilar(_ text1: String, _ text2: String) -> Bool {
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