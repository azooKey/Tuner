import Foundation

// MARK: - Statistics

/// 統計情報の計算結果を保持する構造体
struct StatisticsResult {
    let sortedAppNameCounts: [(key: String, value: Int)]
    let sortedAppNameTextCounts: [(key: String, value: Int)]
    let totalEntries: Int
    let totalTextLength: Int
    let summaryStats: String // 複数行の統計サマリー
    let sortedLangTextCounts: [(key: String, value: Int)]
}

/// 複数のデータソースからの統計情報を保持する構造体
struct SeparatedStatisticsResult {
    let combined: StatisticsResult
    let savedTexts: StatisticsResult
    let importTexts: StatisticsResult
}

extension TextModel {
    /// アプリケーション名ごとのエントリ数を集計
    /// - Parameter completion: 集計完了時に実行するコールバック
    func aggregateAppNames(completion: @escaping ([String: Int]) -> Void) {
        loadFromFile { loadedTexts in
            var appNameCounts: [String: Int] = [:]

            for entry in loadedTexts {
                appNameCounts[entry.appName, default: 0] += 1
            }

            completion(appNameCounts)
        }
    }

    /// 統計情報を生成する (単一データソース用)
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - completion: 生成完了時に実行するコールバック (StatisticsResult を返す)
    func generateStatisticsParameter(
        avoidApps: [String],
        minTextLength: Int,
        completion: @escaping (StatisticsResult) -> Void
    ) {
        // データのクリーンアップ
        purifyFile(avoidApps: avoidApps, minTextLength: minTextLength) {
            self.loadFromFile { loadedTexts in
                var textEntries: [TextEntry] = []
                var appNameCounts: [String: Int] = [:]
                var appNameTextCounts: [String: Int] = [:]
                var totalTextLength = 0
                var totalEntries = 0
                var uniqueEntries: Set<String> = []

                var duplicatedCount = 0

                // 言語のカウント
                var langText: [String: Int] = ["JA": 0, "EN": 0, "Num": 0]
                var langOther: Int = 0

                for entry in loadedTexts {
                    let uniqueKey = "\(entry.appName)-\(entry.text)"
                    // 重複をスキップ
                    if uniqueEntries.contains(uniqueKey) {
                        duplicatedCount += 1
                        continue
                    }
                    uniqueEntries.insert(uniqueKey)
                    textEntries.append(entry)

                    if avoidApps.contains(entry.appName) {
                        continue
                    }
                    appNameCounts[entry.appName, default: 0] += 1
                    appNameTextCounts[entry.appName, default: 0] += entry.text.count
                    totalTextLength += entry.text.count
                    totalEntries += 1

                    // 言語ごとのテキスト長を計算
                    for char in entry.text {
                        if char.isJapanese {
                            langText["JA"]! += 1
                        } else if char.isEnglish {
                            langText["EN"]! += 1
                        } else if char.isNumber {
                            langText["Num"]! += 1
                        } else {
                            langOther += 1
                        }
                    }
                }

                // 日本語・英語の割合計算
                var stats = ""
                stats += "Total Text Entries: \(totalEntries)\n"
                stats += "Total Text Length: \(totalTextLength) characters\n"
                // 必要に応じて他の統計情報も stats に追加

                let sortedAppNameCounts = appNameCounts.sorted { $0.value > $1.value }
                let sortedAppNameTextCounts = appNameTextCounts.sorted { $0.value > $1.value }
                let sortedLangTextCounts = langText.sorted { $0.value > $1.value } + [("Other", langOther)]

                let result = StatisticsResult(
                    sortedAppNameCounts: sortedAppNameCounts,
                    sortedAppNameTextCounts: sortedAppNameTextCounts,
                    totalEntries: totalEntries,
                    totalTextLength: totalTextLength,
                    summaryStats: stats,
                    sortedLangTextCounts: sortedLangTextCounts
                )
                completion(result)
            }
        }
    }

    /// 統計情報を個別に生成 (複数データソース用)
    /// - Parameters:
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - progressCallback: 進捗状況を通知するコールバック
    ///   - statusCallback: ステータス情報を通知するコールバック
    /// - Returns: SeparatedStatisticsResult
    func generateSeparatedStatisticsAsync(
        avoidApps: [String],
        minTextLength: Int,
        progressCallback: @escaping (Double) -> Void,
        statusCallback: @escaping (String, String) -> Void = { _, _ in }
    ) async -> SeparatedStatisticsResult { // 戻り値の型を変更
        // 進捗状況の初期化
        progressCallback(0.0)
        statusCallback("処理を開始しています...", "データを読み込み中...")

        // savedTexts.jsonl からテキストを非同期で読み込む
        statusCallback("データを読み込み中...", "savedTexts.jsonlを解析しています")
        let savedTexts = await loadFromFileAsync()
        progressCallback(0.1)

        // import.jsonl からテキストを非同期で読み込む
        statusCallback("データを読み込み中...", "import.jsonlを解析しています")
        let importTexts = await loadFromImportFileAsync()
        progressCallback(0.2)

        // 両方のデータを結合
        let combinedTexts = savedTexts + importTexts
        statusCallback("データを処理中...", "全テキスト \(combinedTexts.count) 件の統計処理を開始します")

        // savedTexts.jsonlの統計処理
        statusCallback("savedTexts.jsonlの処理中...", "\(savedTexts.count) 件を分析しています")
        let savedTextStats = await processStatistics(
            entries: savedTexts,
            avoidApps: avoidApps,
            minTextLength: minTextLength,
            source: "savedTexts.jsonl",
            progressRange: (0.2, 0.4),
            progressCallback: progressCallback,
            statusCallback: statusCallback
        )

        // import.jsonlの統計処理
        statusCallback("import.jsonlの処理中...", "\(importTexts.count) 件を分析しています")
        let importTextStats = await processStatistics(
            entries: importTexts,
            avoidApps: avoidApps,
            minTextLength: minTextLength,
            source: "import.jsonl",
            progressRange: (0.4, 0.6),
            progressCallback: progressCallback,
            statusCallback: statusCallback
        )

        // 結合データの統計処理
        statusCallback("結合データの処理中...", "両ファイルの統合データ \(combinedTexts.count) 件を分析しています")
        let combinedStats = await processStatistics(
            entries: combinedTexts,
            avoidApps: avoidApps,
            minTextLength: minTextLength,
            source: "Combined Data",
            progressRange: (0.6, 0.9),
            progressCallback: progressCallback,
            statusCallback: statusCallback
        )

        // 完了の通知
        progressCallback(1.0)
        statusCallback("処理完了!", "統計情報の生成が完了しました")

        // SeparatedStatisticsResult を返す
        return SeparatedStatisticsResult(
            combined: combinedStats,
            savedTexts: savedTextStats,
            importTexts: importTextStats
        )
    }

    /// 統計情報を処理するヘルパーメソッド
    /// - Parameters:
    ///   - entries: 処理対象のテキストエントリ
    ///   - avoidApps: 除外するアプリケーション名のリスト
    ///   - minTextLength: 最小テキスト長
    ///   - source: データソース名
    ///   - progressRange: 進捗状況の範囲
    ///   - progressCallback: 進捗状況を通知するコールバック
    ///   - statusCallback: ステータス情報を通知するコールバック
    /// - Returns: StatisticsResult
    private func processStatistics(
        entries: [TextEntry],
        avoidApps: [String],
        minTextLength: Int,
        source: String,
        progressRange: (Double, Double),
        progressCallback: @escaping (Double) -> Void,
        statusCallback: @escaping (String, String) -> Void
    ) async -> StatisticsResult { // 戻り値の型を変更
        let (startProgress, endProgress) = progressRange
        let avoidAppsSet = Set(avoidApps)

        var textEntries: [TextEntry] = []
        var appNameCounts: [String: Int] = [:]
        var appNameTextCounts: [String: Int] = [:]
        var totalTextLength = 0
        var totalEntries = 0
        var uniqueEntries: Set<String> = []

        var duplicatedCount = 0

        // 言語のカウント
        var langText: [String: Int] = ["JA": 0, "EN": 0, "Num": 0]
        var langOther: Int = 0

        // バッチ処理で進捗状況を更新しながら処理
        let batchSize = max(1, entries.count / 10)

        for (index, entry) in entries.enumerated() {
            let uniqueKey = "\(entry.appName)-\(entry.text)"

            // 重複をスキップ
            if uniqueEntries.contains(uniqueKey) {
                duplicatedCount += 1
                continue
            }
            uniqueEntries.insert(uniqueKey)
            textEntries.append(entry)

            if avoidAppsSet.contains(entry.appName) {
                continue
            }

            appNameCounts[entry.appName, default: 0] += 1
            appNameTextCounts[entry.appName, default: 0] += entry.text.count
            totalTextLength += entry.text.count
            totalEntries += 1

            // 言語ごとのテキスト長を計算
            for char in entry.text {
                if char.isJapanese {
                    langText["JA"]! += 1
                } else if char.isEnglish {
                    langText["EN"]! += 1
                } else if char.isNumber {
                    langText["Num"]! += 1
                } else {
                    langOther += 1
                }
            }

            // バッチごとに進捗状況を更新
            if index % batchSize == 0 && entries.count > 0 {
                let progress = startProgress + (endProgress - startProgress) * Double(index) / Double(entries.count)
                progressCallback(progress)

                let processedPercentage = Int(Double(index) / Double(entries.count) * 100)
                let processedCount = index
                let totalCount = entries.count

                statusCallback(
                    "\(source)の処理中... \(processedPercentage)%",
                    "\(processedCount)/\(totalCount) 件のテキストを分析中"
                )

                // 少しの遅延を入れてUIの更新を可能にする
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ミリ秒
            }
        }

        // 統計情報の作成
        var stats = ""
        stats += "ソース: \(source)\n"
        stats += "テキストエントリ総数: \(totalEntries)\n"
        stats += "テキスト総文字数: \(totalTextLength)\n"

        // 平均文字数の計算
        let averageLength = totalEntries > 0 ? totalTextLength / totalEntries : 0
        stats += "エントリあたりの平均文字数: \(averageLength)\n"

        // 言語別の文字数の割合
        if totalTextLength > 0 {
            let jaPercentage = Int(Double(langText["JA"] ?? 0) / Double(totalTextLength) * 100)
            let enPercentage = Int(Double(langText["EN"] ?? 0) / Double(totalTextLength) * 100)
            let numPercentage = Int(Double(langText["Num"] ?? 0) / Double(totalTextLength) * 100)
            let otherPercentage = Int(Double(langOther) / Double(totalTextLength) * 100)

            stats += "言語別文字数割合:\n"
            stats += "  日本語: \(langText["JA"] ?? 0) 文字 (\(jaPercentage)%)\n"
            stats += "  英語: \(langText["EN"] ?? 0) 文字 (\(enPercentage)%)\n"
            stats += "  数字: \(langText["Num"] ?? 0) 文字 (\(numPercentage)%)\n"
            stats += "  その他: \(langOther) 文字 (\(otherPercentage)%)\n"
        }

        stats += "重複除去数: \(duplicatedCount)\n"

        // グラフ用にソートされたデータを作成
        let sortedAppNameCounts = appNameCounts.sorted { $0.value > $1.value }
        let sortedAppNameTextCounts = appNameTextCounts.sorted { $0.value > $1.value }
        let sortedLangTextCounts = langText.sorted { $0.value > $1.value } + [("Other", langOther)]

        // StatisticsResult を返す
        return StatisticsResult(
            sortedAppNameCounts: sortedAppNameCounts,
            sortedAppNameTextCounts: sortedAppNameTextCounts,
            totalEntries: totalEntries,
            totalTextLength: totalTextLength,
            summaryStats: stats,
            sortedLangTextCounts: sortedLangTextCounts
        )
    }
} 