import Foundation

// MARK: - Purification
extension TextModel {
    /// セクション分割による重複エントリ除去（大量データ対応版）
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - isFullClean: 完全クリーニング（original_marisa更新前など）
    ///   - completion: クリーンアップ完了時に実行するコールバック
    func purifyFile(avoidApps: [String], minTextLength: Int, isFullClean: Bool = false, completion: @escaping () -> Void) {
        if isFullClean {
            purifyFileInSections(avoidApps: avoidApps, minTextLength: minTextLength, completion: completion)
        } else {
            purifyFileLightweight(avoidApps: avoidApps, minTextLength: minTextLength, completion: completion)
        }
    }
    
    /// 軽量版purify（通常時用）
    private func purifyFileLightweight(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        let fileURL = getFileURL()
        let startTime = Date()
        
        // 頻度制限: 前回実行から30秒以内は実行しない
        if let lastPurify = lastPurifyDate, Date().timeIntervalSince(lastPurify) < 30 {
            print("⏰ Purify頻度制限: 前回から30秒未満のためスキップ")
            completion()
            return
        }
        
        // さらに低プライオリティでバックグラウンド実行
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { 
                DispatchQueue.main.async { completion() }
                return 
            }
            
            self.loadFromFile { [weak self] loadedTexts in
                guard let self = self else { 
                    DispatchQueue.main.async { completion() }
                    return 
                }
                
                if loadedTexts.isEmpty {
                    print("No texts loaded from file - skipping purify to avoid empty file")
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                let originalCount = loadedTexts.count
                print("🎯 Purify開始: \(originalCount) 件のエントリを処理します")
                
                // 量制限: 最大1000件のみ処理（最新のものを保持）
                let maxProcessingCount = 1000
                let textsToProcess: [TextEntry]
                if originalCount > maxProcessingCount {
                    // 最新1000件のみ処理
                    textsToProcess = Array(loadedTexts.suffix(maxProcessingCount))
                    print("📊 量制限: 最新\(maxProcessingCount)件のみ処理します（\(originalCount - maxProcessingCount)件スキップ）")
                } else {
                    textsToProcess = loadedTexts
                }
                
                // 適応的処理レベル調整
                let adaptiveLevel = self.determineAdaptiveProcessingLevel(dataCount: textsToProcess.count)
                if adaptiveLevel == .disabled {
                    print("⚠️ データ量が多すぎるため重複削除をスキップ（超軽量化優先）")
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                // 時間制限付きで処理実行
                let timeoutDate = Date().addingTimeInterval(5.0) // 5秒でタイムアウト
                let (uniqueEntries, duplicateCount, potentialDuplicates) = self.findDuplicateEntriesWithTimeout(
                    entries: textsToProcess,
                    avoidApps: avoidApps,
                    minTextLength: minTextLength,
                    timeoutDate: timeoutDate
                )
                
                let processingTime = Date().timeIntervalSince(startTime)
                print("⏱️ 処理時間: \(String(format: "%.2f", processingTime))秒")
                
                // 結果サマリー（簡略版）
                let processedCount = textsToProcess.count
                let reductionRate = processedCount > 0 ? Double(duplicateCount) / Double(processedCount) * 100 : 0
                print("📈 処理結果: \(processedCount)件処理、\(duplicateCount)件除去（\(String(format: "%.1f", reductionRate))%削減）")
                
                if duplicateCount == 0 {
                    print("✅ 重複なし - ファイル更新をスキップします")
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                // 処理した範囲のみ更新（最新1000件の場合は古いデータと結合）
                let finalUniqueEntries: [TextEntry]
                if originalCount > maxProcessingCount {
                    // 古いデータ（未処理部分）と新しいデータ（処理済み）を結合
                    let oldEntries = Array(loadedTexts.prefix(originalCount - maxProcessingCount))
                    finalUniqueEntries = oldEntries + uniqueEntries
                } else {
                    finalUniqueEntries = uniqueEntries
                }
                
                self.writeUniqueEntries(uniqueEntries: finalUniqueEntries, originalFileURL: fileURL, duplicateCount: duplicateCount) {
                    let totalTime = Date().timeIntervalSince(startTime)
                    print("🎉 Purify完了: 総処理時間 \(String(format: "%.2f", totalTime))秒")
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }
    
    /// セクション分割によるpurify（大量データ対応・完全クリーニング版）
    private func purifyFileInSections(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        let startTime = Date()
        print("🧹 セクション分割purify開始")
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { 
                DispatchQueue.main.async { completion() }
                return 
            }
            
            self.loadFromFile { [weak self] loadedTexts in
                guard let self = self else { 
                    DispatchQueue.main.async { completion() }
                    return 
                }
                
                if loadedTexts.isEmpty {
                    print("📂 ファイルが空のためスキップ")
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                let originalCount = loadedTexts.count
                print("📊 セクション分割purify: \(originalCount)件を処理開始")
                
                // セクションサイズを動的調整
                let sectionSize = self.calculateOptimalSectionSize(totalCount: originalCount)
                let sections = self.divideIntoSections(entries: loadedTexts, sectionSize: sectionSize)
                
                print("🔧 \(sections.count)セクション（各\(sectionSize)件）に分割")
                
                // セクション間で重複除去状態を維持
                var globalSeenTexts = Set<String>()
                var allUniqueEntries: [TextEntry] = []
                var totalDuplicateCount = 0
                
                // 各セクションを順次処理
                for (sectionIndex, section) in sections.enumerated() {
                    let sectionStartTime = Date()
                    print("🔄 セクション\(sectionIndex + 1)/\(sections.count)処理中...")
                    
                    // セクション内で重複除去（グローバル状態も考慮）
                    let (sectionUniqueEntries, sectionDuplicates) = self.processSectionWithGlobalState(
                        section: section,
                        globalSeenTexts: &globalSeenTexts,
                        avoidApps: avoidApps,
                        minTextLength: minTextLength
                    )
                    
                    allUniqueEntries.append(contentsOf: sectionUniqueEntries)
                    totalDuplicateCount += sectionDuplicates
                    
                    let sectionTime = Date().timeIntervalSince(sectionStartTime)
                    print("✅ セクション\(sectionIndex + 1)完了: \(sectionDuplicates)件除去、\(String(format: "%.2f", sectionTime))秒")
                    
                    // セクション間で適度な待機（CPU負荷分散）
                    if sectionIndex < sections.count - 1 {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
                
                let processingTime = Date().timeIntervalSince(startTime)
                print("📈 セクション分割処理完了:")
                print("  - 処理時間: \(String(format: "%.2f", processingTime))秒")
                print("  - 除去件数: \(totalDuplicateCount)件")
                print("  - 残存件数: \(allUniqueEntries.count)件")
                print("  - 削減率: \(String(format: "%.1f", Double(totalDuplicateCount) / Double(originalCount) * 100))%")
                
                if totalDuplicateCount == 0 {
                    print("✅ 重複なし - ファイル更新をスキップ")
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                // 結果をファイルに書き込み
                let fileURL = self.getFileURL()
                self.writeUniqueEntries(uniqueEntries: allUniqueEntries, originalFileURL: fileURL, duplicateCount: totalDuplicateCount) {
                    let totalTime = Date().timeIntervalSince(startTime)
                    print("🎉 セクション分割purify完了: 総時間\(String(format: "%.2f", totalTime))秒")
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }
    
    /// 最適なセクションサイズを計算
    private func calculateOptimalSectionSize(totalCount: Int) -> Int {
        let availableMemoryMB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        
        // メモリ量とデータ量に基づいて動的調整
        switch totalCount {
        case 0...1000:
            return 500  // 小量データは大きなセクション
        case 1001...5000:
            return 300  // 中量データは中程度のセクション
        case 5001...20000:
            return 200  // 大量データは小さなセクション
        default:
            // 超大量データは利用可能メモリに基づいて調整
            return availableMemoryMB > 8192 ? 200 : 100
        }
    }
    
    /// エントリをセクションに分割
    private func divideIntoSections(entries: [TextEntry], sectionSize: Int) -> [[TextEntry]] {
        var sections: [[TextEntry]] = []
        
        for i in stride(from: 0, to: entries.count, by: sectionSize) {
            let endIndex = min(i + sectionSize, entries.count)
            let section = Array(entries[i..<endIndex])
            sections.append(section)
        }
        
        return sections
    }
    
    /// セクションをグローバル状態を考慮して処理
    private func processSectionWithGlobalState(
        section: [TextEntry],
        globalSeenTexts: inout Set<String>,
        avoidApps: [String],
        minTextLength: Int
    ) -> ([TextEntry], Int) {
        let avoidAppsSet = Set(avoidApps)
        var sectionUniqueEntries: [TextEntry] = []
        var sectionDuplicateCount = 0
        
        for entry in section {
            // フィルタリング
            if avoidAppsSet.contains(entry.appName) || entry.text.count < minTextLength {
                continue
            }
            
            // グローバル重複チェック
            if globalSeenTexts.contains(entry.text) {
                sectionDuplicateCount += 1
                continue
            }
            
            // ユニークエントリとして追加
            globalSeenTexts.insert(entry.text)
            sectionUniqueEntries.append(entry)
        }
        
        return (sectionUniqueEntries, sectionDuplicateCount)
    }
    
    /// 進捗保存可能なセクション分割purify（超大量データ対応版）
    func purifyFileProgressively(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        let startTime = Date()
        print("📈 進捗保存型purify開始")
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { 
                DispatchQueue.main.async { completion() }
                return 
            }
            
            // 進捗状態の確認・復旧
            let progressFile = self.getProgressFileURL()
            var startSection = 0
            var globalSeenTexts = Set<String>()
            var allUniqueEntries: [TextEntry] = []
            
            if self.fileManager.fileExists(atPath: progressFile.path) {
                (startSection, globalSeenTexts, allUniqueEntries) = self.loadProgressState(from: progressFile)
                print("📋 進捗復旧: セクション\(startSection)から再開、既存ユニーク\(allUniqueEntries.count)件")
            }
            
            self.loadFromFile { [weak self] loadedTexts in
                guard let self = self else { 
                    DispatchQueue.main.async { completion() }
                    return 
                }
                
                if loadedTexts.isEmpty {
                    print("📂 ファイルが空のためスキップ")
                    self.cleanupProgressFile()
                    DispatchQueue.main.async { completion() }
                    return
                }
                
                let sectionSize = self.calculateOptimalSectionSize(totalCount: loadedTexts.count)
                let sections = self.divideIntoSections(entries: loadedTexts, sectionSize: sectionSize)
                
                print("🔄 セクション\(startSection + 1)から\(sections.count)まで処理継続")
                
                var totalDuplicateCount = 0
                
                // 指定セクションから処理再開
                for sectionIndex in startSection..<sections.count {
                    let section = sections[sectionIndex]
                    let sectionStartTime = Date()
                    
                    // セクション処理
                    let (sectionUniqueEntries, sectionDuplicates) = self.processSectionWithGlobalState(
                        section: section,
                        globalSeenTexts: &globalSeenTexts,
                        avoidApps: avoidApps,
                        minTextLength: minTextLength
                    )
                    
                    allUniqueEntries.append(contentsOf: sectionUniqueEntries)
                    totalDuplicateCount += sectionDuplicates
                    
                    let sectionTime = Date().timeIntervalSince(sectionStartTime)
                    print("✅ セクション\(sectionIndex + 1)/\(sections.count): \(sectionDuplicates)件除去 (\(String(format: "%.2f", sectionTime))秒)")
                    
                    // 進捗を定期的に保存（5セクションごと）
                    if (sectionIndex + 1) % 5 == 0 {
                        self.saveProgressState(
                            section: sectionIndex + 1,
                            globalSeenTexts: globalSeenTexts,
                            uniqueEntries: allUniqueEntries,
                            to: progressFile
                        )
                    }
                    
                    // CPU負荷分散
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                // 処理完了：進捗ファイル削除
                self.cleanupProgressFile()
                
                let processingTime = Date().timeIntervalSince(startTime)
                print("📊 進捗保存型purify完了:")
                print("  - 処理時間: \(String(format: "%.2f", processingTime))秒")
                print("  - 最終エントリ数: \(allUniqueEntries.count)件")
                
                // 結果をファイルに書き込み
                let fileURL = self.getFileURL()
                self.writeUniqueEntries(uniqueEntries: allUniqueEntries, originalFileURL: fileURL, duplicateCount: totalDuplicateCount) {
                    print("🎉 進捗保存型purify完全終了")
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }
    
    /// 進捗ファイルのURL取得
    private func getProgressFileURL() -> URL {
        return getTextEntryDirectory().appendingPathComponent("purify_progress.json")
    }
    
    /// 進捗状態を保存
    private func saveProgressState(section: Int, globalSeenTexts: Set<String>, uniqueEntries: [TextEntry], to url: URL) {
        let progressData: [String: Any] = [
            "section": section,
            "seenTexts": Array(globalSeenTexts),
            "uniqueEntries": uniqueEntries.map { entry in
                [
                    "appName": entry.appName,
                    "text": entry.text,
                    "timestamp": entry.timestamp.timeIntervalSince1970
                ]
            }
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: progressData)
            try fileManager.write(data, to: url, atomically: true)
        } catch {
            print("❌ 進捗保存エラー: \(error)")
        }
    }
    
    /// 進捗状態を読み込み
    private func loadProgressState(from url: URL) -> (Int, Set<String>, [TextEntry]) {
        do {
            let data = try Data(contentsOf: url)
            guard let progressData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let section = progressData["section"] as? Int,
                  let seenTextsArray = progressData["seenTexts"] as? [String],
                  let uniqueEntriesData = progressData["uniqueEntries"] as? [[String: Any]] else {
                print("❌ 進捗データが不正")
                return (0, Set<String>(), [])
            }
            
            let seenTexts = Set(seenTextsArray)
            let uniqueEntries = uniqueEntriesData.compactMap { entryData -> TextEntry? in
                guard let appName = entryData["appName"] as? String,
                      let text = entryData["text"] as? String,
                      let timestamp = entryData["timestamp"] as? TimeInterval else {
                    return nil
                }
                return TextEntry(appName: appName, text: text, timestamp: Date(timeIntervalSince1970: timestamp))
            }
            
            return (section, seenTexts, uniqueEntries)
        } catch {
            print("❌ 進捗読み込みエラー: \(error)")
            return (0, Set<String>(), [])
        }
    }
    
    /// 進捗ファイルのクリーンアップ
    private func cleanupProgressFile() {
        let progressFile = getProgressFileURL()
        if fileManager.fileExists(atPath: progressFile.path) {
            try? fileManager.removeItem(at: progressFile)
        }
    }
    
    /// タイムアウト付き重複エントリ検出（超軽量化版）
    private func findDuplicateEntriesWithTimeout(entries: [TextEntry], avoidApps: [String], minTextLength: Int, timeoutDate: Date) -> (unique: [TextEntry], duplicateCount: Int, potential: [(TextEntry, TextEntry, Double)]) {
        let avoidAppsSet = Set(avoidApps)
        let batchSize = 100 // さらに小さなバッチサイズ
        
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        var potentialDuplicates: [(TextEntry, TextEntry, Double)] = []
        
        // タイムアウトチェック関数
        func isTimedOut() -> Bool {
            return Date() > timeoutDate
        }
        
        // 段階1: 完全一致の高速除去（O(n)）
        print("🚀 段階1: 完全一致除去を開始...")
        let (exactUniqueEntries, exactDuplicates) = removeExactDuplicatesWithTimeout(
            entries: entries, 
            avoidApps: avoidAppsSet, 
            minTextLength: minTextLength,
            timeoutDate: timeoutDate
        )
        duplicateCount += exactDuplicates
        print("📊 完全一致で \(exactDuplicates) 件除去、残り \(exactUniqueEntries.count) 件")
        
        if isTimedOut() {
            print("⏰ タイムアウト: 段階1で処理終了")
            return (exactUniqueEntries, duplicateCount, potentialDuplicates)
        }
        
        // 段階2は完全にスキップ（さらなる軽量化）
        print("⚡ 超軽量化: 前方一致と類似度検出をスキップ")
        uniqueEntries = exactUniqueEntries
        
        return (uniqueEntries, duplicateCount, potentialDuplicates)
    }
    
    /// 高速化された重複エントリ検出（CPU使用率を最適化）- 従来版
    private func findDuplicateEntries(entries: [TextEntry], avoidApps: [String], minTextLength: Int) -> (unique: [TextEntry], duplicateCount: Int, potential: [(TextEntry, TextEntry, Double)]) {
        let avoidAppsSet = Set(avoidApps)
        let batchSize = 1000 // バッチサイズを制限してCPU使用率を制御
        
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        var potentialDuplicates: [(TextEntry, TextEntry, Double)] = []
        
        // 段階1: 完全一致の高速除去（O(n)）
        print("🚀 段階1: 完全一致除去を開始...")
        let (exactUniqueEntries, exactDuplicates) = removeExactDuplicates(entries: entries, avoidApps: avoidAppsSet, minTextLength: minTextLength)
        duplicateCount += exactDuplicates
        print("📊 完全一致で \(exactDuplicates) 件除去、残り \(exactUniqueEntries.count) 件")
        
        // 段階2: 前方一致の高速除去（O(n log n)）
        print("🚀 段階2: 前方一致除去を開始...")
        let (prefixUniqueEntries, prefixDuplicates) = removePrefixDuplicates(entries: exactUniqueEntries)
        duplicateCount += prefixDuplicates
        print("📊 前方一致で \(prefixDuplicates) 件除去、残り \(prefixUniqueEntries.count) 件")
        
        // 段階3: MinHash類似度検出（必要最小限）
        print("🚀 段階3: 類似度検出を開始...")
        if prefixUniqueEntries.count > 2000 {
            // 大量データの場合はMinHash処理をスキップして軽量化を優先
            print("⚠️ データ量が多いため類似度検出をスキップ（軽量化優先）")
            uniqueEntries = prefixUniqueEntries
        } else {
            let (similarityUniqueEntries, similarityDuplicates, similarities) = removeSimilarDuplicatesBatched(
                entries: prefixUniqueEntries, 
                batchSize: batchSize
            )
            duplicateCount += similarityDuplicates
            potentialDuplicates = similarities
            uniqueEntries = similarityUniqueEntries
            print("📊 類似度で \(similarityDuplicates) 件除去、最終 \(uniqueEntries.count) 件")
        }
        
        return (uniqueEntries, duplicateCount, potentialDuplicates)
    }
    
    /// タイムアウト付き完全一致除去（O(n)）
    private func removeExactDuplicatesWithTimeout(entries: [TextEntry], avoidApps: Set<String>, minTextLength: Int, timeoutDate: Date) -> ([TextEntry], Int) {
        var seen = Set<String>()
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        let checkInterval = 50 // 50件ごとにタイムアウトチェック
        
        for (index, entry) in entries.enumerated() {
            // 定期的にタイムアウトチェック
            if index % checkInterval == 0 && Date() > timeoutDate {
                print("⏰ 完全一致除去でタイムアウト: \(index)/\(entries.count)件処理済み")
                break
            }
            
            // フィルタリング
            if avoidApps.contains(entry.appName) || entry.text.count < minTextLength {
                continue
            }
            
            // 完全一致チェック（O(1)）
            if seen.contains(entry.text) {
                duplicateCount += 1
                continue
            }
            
            seen.insert(entry.text)
            uniqueEntries.append(entry)
        }
        
        return (uniqueEntries, duplicateCount)
    }
    
    /// 完全一致の高速除去（O(n)）- 従来版
    private func removeExactDuplicates(entries: [TextEntry], avoidApps: Set<String>, minTextLength: Int) -> ([TextEntry], Int) {
        var seen = Set<String>()
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        
        for entry in entries {
            // フィルタリング
            if avoidApps.contains(entry.appName) || entry.text.count < minTextLength {
                continue
            }
            
            // 完全一致チェック（O(1)）
            if seen.contains(entry.text) {
                duplicateCount += 1
                continue
            }
            
            seen.insert(entry.text)
            uniqueEntries.append(entry)
        }
        
        return (uniqueEntries, duplicateCount)
    }
    
    /// 前方一致の効率的な除去（O(n²)）- 長い文字列を優先
    private func removePrefixDuplicates(entries: [TextEntry]) -> ([TextEntry], Int) {
        let groupedByApp = Dictionary(grouping: entries) { $0.appName }
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        
        for (_, appEntries) in groupedByApp {
            // 長い順にソートしてから処理
            let sortedEntries = appEntries.sorted { $0.text.count > $1.text.count }
            var appUniqueEntries: [TextEntry] = []
            
            for entry in sortedEntries {
                let text = entry.text
                
                // 空文字列をフィルタリング
                if text.isEmpty {
                    duplicateCount += 1
                    continue
                }
                
                var shouldKeep = true
                
                // 既に保持されているエントリと比較
                for existingEntry in appUniqueEntries {
                    let existingText = existingEntry.text
                    
                    // 前方一致チェック
                    if existingText.hasPrefix(text) {
                        let matchRatio = Double(text.count) / Double(existingText.count)
                        if matchRatio >= 0.7 {
                            // 短い方（現在のテキスト）を削除
                            shouldKeep = false
                            duplicateCount += 1
                            break
                        }
                    }
                    // 部分的な類似性チェック（前方一致でない場合の補完入力対応）
                    else if isSimilarPartialInput(shorter: text, longer: existingText) {
                        let matchRatio = Double(text.count) / Double(existingText.count)
                        if matchRatio >= 0.7 {
                            shouldKeep = false
                            duplicateCount += 1
                            break
                        }
                    }
                }
                
                // 現在のエントリを追加
                if shouldKeep {
                    appUniqueEntries.append(entry)
                }
            }
            
            uniqueEntries.append(contentsOf: appUniqueEntries)
        }
        
        return (uniqueEntries, duplicateCount)
    }
    
    /// 部分的な入力の類似性をチェック（ローマ字入力途中などを考慮）
    private func isSimilarPartialInput(shorter: String, longer: String) -> Bool {
        // 最小長チェック
        guard shorter.count >= 2 && longer.count > shorter.count else { return false }
        
        let shorterChars = Array(shorter)
        let longerChars = Array(longer)
        
        // 共通する文字数をカウント
        var matchingCount = 0
        let maxCheckLength = min(shorterChars.count, longerChars.count)
        
        for i in 0..<maxCheckLength {
            if shorterChars[i] == longerChars[i] {
                matchingCount += 1
            } else {
                // 連続する不一致が見つかったら早期終了
                break
            }
        }
        
        // 最初の部分が60%以上一致していて、かつ少なくとも2文字一致している場合（入力途中の可能性）
        // This allows "おはy" (2/3 = 0.67) to match "おはよう" since it has 2 matching chars
        let prefixMatchRatio = Double(matchingCount) / Double(shorter.count)
        return prefixMatchRatio >= 0.6 && matchingCount >= 2
    }
    
    /// テスト用の前方一致削除メソッド
    public func testRemovePrefixDuplicates(entries: [TextEntry]) -> ([TextEntry], Int) {
        print("🔍 Input entries: \(entries.map { $0.text })")
        let result = removePrefixDuplicates(entries: entries)
        print("🔍 Output: unique=\(result.0.map { $0.text }), duplicates=\(result.1)")
        return result
    }
    
    /// 前方一致検出用のTrie構造
    private class PrefixTrie {
        class TrieNode {
            var children: [Character: TrieNode] = [:]
            var isEndOfWord: Bool = false
        }
        
        private let root = TrieNode()
        
        func insert(_ word: String) {
            var current = root
            for char in word {
                if current.children[char] == nil {
                    current.children[char] = TrieNode()
                }
                current = current.children[char]!
            }
            current.isEndOfWord = true
        }
        
        /// 与えられた文字列の最長の前方一致を見つける
        func findLongestPrefix(of word: String) -> String? {
            var current = root
            var longestPrefix = ""
            var lastValidPrefix: String? = nil
            
            for char in word {
                guard let next = current.children[char] else {
                    break
                }
                longestPrefix.append(char)
                current = next
                
                if current.isEndOfWord {
                    lastValidPrefix = longestPrefix
                }
            }
            
            return lastValidPrefix
        }
    }
    
    /// バッチ処理による類似度検出（CPU使用率制御）
    private func removeSimilarDuplicatesBatched(entries: [TextEntry], batchSize: Int) -> ([TextEntry], Int, [(TextEntry, TextEntry, Double)]) {
        let minHash = MinHashOptimized(numHashFunctions: 20)
        var uniqueEntries: [TextEntry] = []
        var duplicateCount = 0
        var potentialDuplicates: [(TextEntry, TextEntry, Double)] = []
        var signatureCache: [String: [Int]] = [:]
        
        // バッチ単位で処理
        for startIndex in stride(from: 0, to: entries.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, entries.count)
            let batch = Array(entries[startIndex..<endIndex])
            
            for entry in batch {
                var isDuplicate = false
                
                // キャッシュからシグネチャを取得またはキャッシュに保存
                let signature: [Int]
                if let cachedSignature = signatureCache[entry.text] {
                    signature = cachedSignature
                } else {
                    signature = minHash.computeMinHashSignature(for: entry.text)
                    signatureCache[entry.text] = signature
                }
                
                // 類似度チェック（既存のuniqueEntriesとのみ比較）
                for uniqueEntry in uniqueEntries {
                    let uniqueSignature: [Int]
                    if let cachedSignature = signatureCache[uniqueEntry.text] {
                        uniqueSignature = cachedSignature
                    } else {
                        uniqueSignature = minHash.computeMinHashSignature(for: uniqueEntry.text)
                        signatureCache[uniqueEntry.text] = uniqueSignature
                    }
                    
                    let similarity = minHash.computeJaccardSimilarity(signature1: signature, signature2: uniqueSignature)
                    
                    if similarity >= 0.95 {
                        potentialDuplicates.append((entry, uniqueEntry, similarity))
                    }
                    
                    if similarity >= 0.98 {
                        isDuplicate = true
                        break
                    }
                }
                
                if !isDuplicate {
                    uniqueEntries.append(entry)
                } else {
                    duplicateCount += 1
                }
            }
            
            // メモリ使用量制御：キャッシュが大きくなりすぎた場合はクリア
            if signatureCache.count > 2000 {
                signatureCache.removeAll(keepingCapacity: true)
            }
            
            // CPU使用率制御：より頻繁な待機
            if startIndex > 0 && startIndex % (batchSize * 2) == 0 {
                Thread.sleep(forTimeInterval: 0.02) // 20ms待機でCPU負荷軽減
            }
        }
        
        return (uniqueEntries, duplicateCount, potentialDuplicates)
    }
    
    /// データサイズに応じた適応的処理レベル決定
    private func determineAdaptiveProcessingLevel(dataCount: Int) -> ProcessingLevel {
        // システム負荷を考慮した動的調整
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory
        let availableMemory = physicalMemory / (1024 * 1024) // MB単位
        
        print("📊 適応的処理レベル判定: データ\(dataCount)件、利用可能メモリ\(availableMemory)MB")
        
        // データ件数による基本判定
        switch dataCount {
        case 0...50:
            return .normal  // 少量なら通常処理
        case 51...200:
            return .minimal // 中量なら最小処理
        case 201...500:
            // メモリが豊富なら最小処理、少なければ無効
            return availableMemory > 8192 ? .minimal : .disabled
        default:
            return .disabled // 大量なら無効
        }
    }
    
    /// ユニークなエントリをファイルに書き込む
    private func writeUniqueEntries(uniqueEntries: [TextEntry], originalFileURL: URL, duplicateCount: Int, completion: @escaping () -> Void) {
        let tempFileURL = getTextEntryDirectory().appendingPathComponent("tempSavedTexts.jsonl")
        let backupFileURL = getTextEntryDirectory().appendingPathComponent("backup_savedTexts_\(Int(Date().timeIntervalSince1970)).jsonl")
        
        fileAccessQueue.async {
            // バックアップ作成
            do {
                try self.fileManager.copyItem(at: originalFileURL, to: backupFileURL)
                print("Backup file created at: \(backupFileURL.path)")
            } catch {
                print("Failed to create backup file: \(error.localizedDescription)")
                // バックアップ失敗しても続行するが、リスクあり
            }
            
            // 一時ファイルへの書き込み
            do {
                var tempFileHandle: FileHandle?
                if !self.fileManager.fileExists(atPath: tempFileURL.path) {
                    self.fileManager.createFile(atPath: tempFileURL.path, contents: nil, attributes: nil)
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
                    try self.fileManager.removeItem(at: originalFileURL)
                    try self.fileManager.moveItem(at: tempFileURL, to: originalFileURL)
                    try? self.fileManager.removeItem(at: backupFileURL) // 成功したらバックアップ削除
                    print("File purify completed. Removed \(duplicateCount) duplicated entries. Wrote \(entriesWritten) entries. Backup file deleted.")
                    
                    DispatchQueue.main.async {
                        self.lastPurifyDate = Date()
                        completion()
                    }
                } else {
                    print("⚠️ No entries were written - keeping original file")
                    try? self.fileManager.removeItem(at: tempFileURL) // 不要な一時ファイルを削除
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            } catch {
                print("Failed to clean and update file: \(error.localizedDescription)")
                try? self.fileManager.removeItem(at: tempFileURL) // エラー時も一時ファイルを削除
                // 元のファイルを復元する試み (バックアップがあれば)
                if self.fileManager.fileExists(atPath: backupFileURL.path) {
                    do {
                        if self.fileManager.fileExists(atPath: originalFileURL.path) {
                             try self.fileManager.removeItem(at: originalFileURL)
                        }
                        try self.fileManager.copyItem(at: backupFileURL, to: originalFileURL)
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
    
    /// インテリジェント purify スケジューラー
    func scheduleIntelligentPurify(avoidApps: [String], minTextLength: Int, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { 
                DispatchQueue.main.async { completion() }
                return 
            }
            
            self.loadFromFile { [weak self] loadedTexts in
                guard let self = self else { 
                    DispatchQueue.main.async { completion() }
                    return 
                }
                
                let entryCount = loadedTexts.count
                let strategy = self.determinePurifyStrategy(entryCount: entryCount)
                
                print("🧠 インテリジェント purify: \(entryCount)件 → \(strategy.description)")
                
                switch strategy {
                case .skip:
                    print("⏭️ Purify をスキップ")
                    DispatchQueue.main.async { completion() }
                    
                case .lightweight:
                    self.purifyFileLightweight(avoidApps: avoidApps, minTextLength: minTextLength, completion: completion)
                    
                case .sectioned:
                    self.purifyFileInSections(avoidApps: avoidApps, minTextLength: minTextLength, completion: completion)
                    
                case .progressive:
                    self.purifyFileProgressively(avoidApps: avoidApps, minTextLength: minTextLength, completion: completion)
                }
            }
        }
    }
    
    /// Purify戦略の決定
    private func determinePurifyStrategy(entryCount: Int) -> PurifyStrategy {
        let availableMemoryMB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        let isLowMemory = availableMemoryMB < 4096
        
        // 前回実行からの経過時間を考慮
        let timeSinceLastPurify: TimeInterval
        if let lastPurify = lastPurifyDate {
            timeSinceLastPurify = Date().timeIntervalSince(lastPurify)
        } else {
            timeSinceLastPurify = TimeInterval.infinity
        }
        
        // 戦略決定ロジック
        switch entryCount {
        case 0...500:
            return timeSinceLastPurify < 60 ? .skip : .lightweight
            
        case 501...2000:
            if isLowMemory {
                return timeSinceLastPurify < 300 ? .skip : .lightweight
            } else {
                return timeSinceLastPurify < 120 ? .skip : .sectioned
            }
            
        case 2001...10000:
            if isLowMemory {
                return timeSinceLastPurify < 600 ? .skip : .sectioned
            } else {
                return timeSinceLastPurify < 300 ? .skip : .sectioned
            }
            
        default: // 10000件以上
            return timeSinceLastPurify < 1800 ? .skip : .progressive // 30分間隔
        }
    }
    
    /// Purify戦略の列挙型
    enum PurifyStrategy {
        case skip           // スキップ
        case lightweight    // 軽量版
        case sectioned      // セクション分割版
        case progressive    // 進捗保存版
        
        var description: String {
            switch self {
            case .skip: return "スキップ"
            case .lightweight: return "軽量版"
            case .sectioned: return "セクション分割版"
            case .progressive: return "進捗保存版"
            }
        }
    }
} 