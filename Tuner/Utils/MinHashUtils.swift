//
//  MinHashUtils.swift
//  Tuner
//
//  Created by 高橋直希 on 2025/03/08.
//

import Foundation

enum SimpleHasher {
    static func customHash(_ input: some Collection<Unicode.Scalar>, seed: Int) -> Int {
        var hash = seed
        for char in input {
            hash = (hash &* 31) &+ Int(char.value)
        }
        return hash
    }
}

struct MinHashOptimized {
    private let numHashFunctions: Int
    private let seeds: [Int]

    init(numHashFunctions: Int = 20) {
        self.numHashFunctions = numHashFunctions
        self.seeds = (0..<numHashFunctions).map { _ in Int.random(in: Int.min...Int.max) }
    }

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

struct TextModelOptimizedWithLRU {
    private let minHash = MinHashOptimized()
    private var signatureCache: [String: [Int]]
    private var seenEntries: Set<String> = []

    init() {
        self.signatureCache = .init(minimumCapacity: 100)
    }

    mutating func purifyTextEntriesWithMinHash(
        _ entries: [TextEntry], avoidApps: Set<String>, minTextLength: Int,
        similarityThreshold: Double = 0.8
    ) -> ([TextEntry], Int) {
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0

        for (index, entry) in entries.enumerated() {
            guard !avoidApps.contains(entry.appName), entry.text.utf8.count >= minTextLength else { continue }

            if signatureCache.keys.contains(entry.text) || seenEntries.contains(entry.text) {
                duplicateCount += 1
                continue
            }

            let newEntrySignature: [Int]
            if let cachedSignature = self.signatureCache[entry.text] {
                newEntrySignature = cachedSignature
            } else {
                newEntrySignature = minHash.computeMinHashSignature(for: entry.text)
                signatureCache[entry.text] = newEntrySignature
            }

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

            if !isDuplicate {
                uniqueEntries.append(entry)
            }

            if index % 100 == 0 {
                self.seenEntries.formUnion(self.signatureCache.keys)
                self.signatureCache.removeAll(keepingCapacity: true)
            }
        }

        return (uniqueEntries, duplicateCount)
    }
}
