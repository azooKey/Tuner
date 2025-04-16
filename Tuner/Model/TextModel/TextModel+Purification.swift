import Foundation

// MARK: - Purification
extension TextModel {
    /// ファイルの重複エントリを除去し、クリーンアップを実行
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - completion: クリーンアップ完了時に実行するコールバック
    func purifyFile(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        let fileURL = getFileURL()
        
        loadFromFile { [weak self] loadedTexts in
            guard let self = self else { completion(); return }
            
            if loadedTexts.isEmpty {
                print("No texts loaded from file - skipping purify to avoid empty file")
                completion()
                return
            }
            
            let (uniqueEntries, duplicateCount, potentialDuplicates) = self.findDuplicateEntries(
                entries: loadedTexts,
                avoidApps: avoidApps,
                minTextLength: minTextLength
            )
            
            // デバッグ情報の出力
            if !potentialDuplicates.isEmpty {
                print("\n🔍 高類似度ペアの一覧:")
                for (entry1, entry2, similarity) in potentialDuplicates {
                    print("  類似度: \(similarity)")
                    print("  テキスト1: [\(entry1.appName)] \(entry1.text)")
                    print("  テキスト2: [\(entry2.appName)] \(entry2.text)")
                    print("  ---")
                }
            }
            
            if duplicateCount == 0 {
                print("No duplicates found - skipping file update")
                completion()
                return
            }
            
            print("Found \(duplicateCount) duplicates out of \(loadedTexts.count) entries")
            
            self.writeUniqueEntries(uniqueEntries: uniqueEntries, originalFileURL: fileURL, duplicateCount: duplicateCount) {
                completion()
            }
        }
    }
    
    /// MinHash を使用して重複エントリを検出する
    private func findDuplicateEntries(entries: [TextEntry], avoidApps: [String], minTextLength: Int) -> (unique: [TextEntry], duplicateCount: Int, potential: [(TextEntry, TextEntry, Double)]) {
        let minHash = MinHashOptimized(numHashFunctions: 20)
        let avoidAppsSet = Set(avoidApps)
        
        var buckets: [Int: [TextEntry]] = [:]
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        var potentialDuplicates: [(TextEntry, TextEntry, Double)] = []
        
        func getBucket(signature: [Int]) -> Int {
            var hasher = Hasher()
            signature[0..<min(3, signature.count)].forEach { hasher.combine($0) } // Ensure signature has at least 3 elements or handle gracefully
            return hasher.finalize()
        }
        
        for entry in entries {
            if avoidAppsSet.contains(entry.appName) || entry.text.count < minTextLength {
                continue
            }
            
            let signature = minHash.computeMinHashSignature(for: entry.text)
            let bucket = getBucket(signature: signature)
            
            var isDuplicate = false
            if let existingEntries = buckets[bucket] {
                for existingEntry in existingEntries {
                    if entry.text == existingEntry.text {
                        isDuplicate = true
                        print("🔍 完全一致による重複を検出: [\(entry.appName)] \(entry.text)")
                        break
                    }
                    
                    let lengthDiff = abs(entry.text.count - existingEntry.text.count)
                    let maxLength = max(entry.text.count, existingEntry.text.count)
                    if maxLength > 0 && Double(lengthDiff) / Double(maxLength) > 0.1 {
                        continue
                    }
                    
                    let existingSignature = minHash.computeMinHashSignature(for: existingEntry.text)
                    let similarity = minHash.computeJaccardSimilarity(signature1: signature, signature2: existingSignature)
                    
                    if similarity >= 0.95 {
                        potentialDuplicates.append((entry, existingEntry, similarity))
                    }
                    
                    if similarity >= 0.98 {
                        isDuplicate = true
                        print("🔍 類似度による重複を検出: [\(entry.appName)] \(entry.text)")
                        print("  類似度: \(similarity), 既存テキスト: \(existingEntry.text)")
                        break
                    }
                }
            }
            
            if !isDuplicate {
                uniqueEntries.append(entry)
                buckets[bucket, default: []].append(entry)
            } else {
                duplicateCount += 1
            }
        }
        
        return (uniqueEntries, duplicateCount, potentialDuplicates)
    }
    
    /// ユニークなエントリをファイルに書き込む
    private func writeUniqueEntries(uniqueEntries: [TextEntry], originalFileURL: URL, duplicateCount: Int, completion: @escaping () -> Void) {
        let tempFileURL = getTextEntryDirectory().appendingPathComponent("tempSavedTexts.jsonl")
        let backupFileURL = getTextEntryDirectory().appendingPathComponent("backup_savedTexts_\(Int(Date().timeIntervalSince1970)).jsonl")
        
        fileAccessQueue.async {
            // バックアップ作成
            do {
                try FileManager.default.copyItem(at: originalFileURL, to: backupFileURL)
                print("Backup file created at: \(backupFileURL.path)")
            } catch {
                print("Failed to create backup file: \(error.localizedDescription)")
                // バックアップ失敗しても続行するが、リスクあり
            }
            
            // 一時ファイルへの書き込み
            do {
                var tempFileHandle: FileHandle?
                if !FileManager.default.fileExists(atPath: tempFileURL.path) {
                    FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
                }
                tempFileHandle = try FileHandle(forWritingTo: tempFileURL)
                defer { tempFileHandle?.closeFile() }
                
                var entriesWritten = 0
                for textEntry in uniqueEntries {
                    if let jsonData = try? JSONEncoder().encode(textEntry),
                       let jsonString = String(data: jsonData, encoding: .utf8),
                       let data = (jsonString + "\n").data(using: .utf8) {
                        tempFileHandle?.write(data)
                        entriesWritten += 1
                    }
                }
                
                tempFileHandle?.closeFile() // Ensure file is closed before moving
                
                // ファイルの置き換え
                if entriesWritten > 0 {
                    try FileManager.default.removeItem(at: originalFileURL)
                    try FileManager.default.moveItem(at: tempFileURL, to: originalFileURL)
                    try? FileManager.default.removeItem(at: backupFileURL) // 成功したらバックアップ削除
                    print("File purify completed. Removed \(duplicateCount) duplicated entries. Wrote \(entriesWritten) entries. Backup file deleted.")
                    
                    DispatchQueue.main.async {
                        self.lastPurifyDate = Date()
                        completion()
                    }
                } else {
                    print("⚠️ No entries were written - keeping original file")
                    try? FileManager.default.removeItem(at: tempFileURL) // 不要な一時ファイルを削除
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            } catch {
                print("Failed to clean and update file: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempFileURL) // エラー時も一時ファイルを削除
                // 元のファイルを復元する試み (バックアップがあれば)
                if FileManager.default.fileExists(atPath: backupFileURL.path) {
                    do {
                        if FileManager.default.fileExists(atPath: originalFileURL.path) {
                             try FileManager.default.removeItem(at: originalFileURL)
                        }
                        try FileManager.default.copyItem(at: backupFileURL, to: originalFileURL)
                        print("Restored original file from backup.")
                    } catch { // 復元失敗
                        print("❌ Failed to restore original file from backup: \(error.localizedDescription)")
                    }
                }
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // 古いpurifyTextEntries関数 (MinHashを使わない方式) - 念のために残しておく
    func purifyTextEntriesSimple(_ entries: [TextEntry], avoidApps: [String], minTextLength: Int) -> ([TextEntry], Int) {
        print("purity start... \(entries.count)")
        var textEntries: [TextEntry] = []
        var uniqueEntries: Set<String> = []
        var duplicatedCount = 0
        
        for entry in entries {
            // 記号のみのエントリは削除
            if entry.text.utf16.isSymbolOrNumber {
                continue
            }
            
            // 除外アプリの場合はスキップ
            if avoidApps.contains(entry.appName) || minTextLength > entry.text.utf8.count {
                continue
            }
            
            // 重複チェックのためのキー生成
            let uniqueKey = "\(entry.appName)-\(entry.text)"
            if uniqueEntries.contains(uniqueKey) {
                duplicatedCount += 1
                continue
            }
            
            uniqueEntries.insert(uniqueKey)
            textEntries.append(entry)
        }
        
        // 前後の要素のテキストが前方一致している場合、短い方を削除
        var index = 0
        while index < textEntries.count - 1 {
            // アプリ名が異なる場合はスキップ
            if textEntries[index].appName != textEntries[index + 1].appName {
                index += 1
                continue
            }
            
            let currentText = textEntries[index].text.utf16
            let nextText = textEntries[index + 1].text.utf16
            
            if currentText.starts(with: nextText) || nextText.starts(with: currentText) {
                textEntries.remove(at: index + 1)
            } else {
                index += 1
            }
        }
        
        print("purity end... \(textEntries.count)")
        return (textEntries, duplicatedCount)
    }
} 