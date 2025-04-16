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
        let tempFileURL = getTextEntryDirectory().appendingPathComponent("tempSavedTexts.jsonl")

        loadFromFile { loadedTexts in
            if loadedTexts.isEmpty {
                print("No texts loaded from file - skipping purify to avoid empty file")
                completion()
                return
            }

            // MinHashを使用した重複検出と削除
            let minHash = MinHashOptimized(numHashFunctions: 20)
            let avoidAppsSet = Set(avoidApps)
            
            // バケットベースの重複検出
            var buckets: [Int: [TextEntry]] = [:]
            var uniqueEntries: [TextEntry] = []
            var duplicateCount = 0
            var potentialDuplicates: [(TextEntry, TextEntry, Double)] = [] // デバッグ用
            
            // バケットを計算する関数
            func getBucket(signature: [Int]) -> Int {
                var hasher = Hasher()
                signature[0..<3].forEach { hasher.combine($0) }
                return hasher.finalize()
            }
            
            for entry in loadedTexts {
                // 除外アプリの場合はスキップ
                if avoidAppsSet.contains(entry.appName) || entry.text.count < minTextLength {
                    continue
                }
                
                let signature = minHash.computeMinHashSignature(for: entry.text)
                let bucket = getBucket(signature: signature)
                
                var isDuplicate = false
                
                // 同じバケット内のエントリとのみ比較
                if let existingEntries = buckets[bucket] {
                    for existingEntry in existingEntries {
                        // 完全一致の場合は必ず重複と判定
                        if entry.text == existingEntry.text {
                            isDuplicate = true
                            duplicateCount += 1
                            print("🔍 完全一致による重複を検出: [\(entry.appName)] \(entry.text)")
                            break
                        }
                        
                        // テキストの長さの差が大きい場合は重複と判定しない
                        let lengthDiff = abs(entry.text.count - existingEntry.text.count)
                        let maxLength = max(entry.text.count, existingEntry.text.count)
                        if Double(lengthDiff) / Double(maxLength) > 0.1 { // 0.2から0.1に変更
                            continue
                        }
                        
                        // 類似度が0.98以上の場合のみ重複とみなす（0.95から0.98に変更）
                        let existingSignature = minHash.computeMinHashSignature(for: existingEntry.text)
                        let similarity = minHash.computeJaccardSimilarity(signature1: signature, signature2: existingSignature)
                        
                        // デバッグ用に類似度が高いペアを記録
                        if similarity >= 0.95 { // 0.98未満でも0.95以上の場合は記録
                            potentialDuplicates.append((entry, existingEntry, similarity))
                        }
                        
                        if similarity >= 0.98 { // 0.95から0.98に変更
                            isDuplicate = true
                            duplicateCount += 1
                            print("🔍 類似度による重複を検出: [\(entry.appName)] \(entry.text)")
                            print("  類似度: \(similarity), 既存テキスト: \(existingEntry.text)")
                            break
                        }
                    }
                }
                
                if !isDuplicate {
                    uniqueEntries.append(entry)
                    buckets[bucket, default: []].append(entry)
                }
            }
            
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

            self.fileAccessQueue.async {
                // バックアップファイルの作成
                let backupFileURL = self.getTextEntryDirectory().appendingPathComponent("backup_savedTexts_\(Int(Date().timeIntervalSince1970)).jsonl")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: backupFileURL)
                    print("Backup file created at: \(backupFileURL.path)")
                } catch {
                    print("Failed to create backup file: \(error.localizedDescription)")
                }

                // 新規ファイルとして一時ファイルに保存
                do {
                    var tempFileHandle: FileHandle?

                    if !FileManager.default.fileExists(atPath: tempFileURL.path) {
                        FileManager.default.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
                    }

                    tempFileHandle = try FileHandle(forWritingTo: tempFileURL)
                    tempFileHandle?.seekToEndOfFile()

                    var writeSuccess = false
                    var entriesWritten = 0

                    for textEntry in uniqueEntries {
                        let jsonData = try JSONEncoder().encode(textEntry)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            let jsonLine = jsonString + "\n"
                            if let data = jsonLine.data(using: .utf8) {
                                tempFileHandle?.write(data)
                                entriesWritten += 1
                                writeSuccess = true
                            }
                        }
                    }

                    tempFileHandle?.closeFile()

                    if writeSuccess && entriesWritten > 0 {
                        try FileManager.default.removeItem(at: fileURL)
                        try FileManager.default.moveItem(at: tempFileURL, to: fileURL)
                        try? FileManager.default.removeItem(at: backupFileURL)
                        print("File purify completed. Removed \(duplicateCount) duplicated entries. Wrote \(entriesWritten) entries. Backup file deleted.")
                        
                        DispatchQueue.main.async {
                            self.lastPurifyDate = Date()
                        }
                    } else {
                        print("⚠️ Write was not successful or no entries were written - keeping original file")
                        try? FileManager.default.removeItem(at: tempFileURL)
                    }
                } catch {
                    print("Failed to clean and update file: \(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: tempFileURL)
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