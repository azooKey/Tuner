//
//  StatisticsView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/03.
//

import SwiftUI
import Charts

// 統計情報データ構造体
struct StatisticsData {
    var appNameCounts: [(key: String, value: Int)] = []
    var appTexts: [(key: String, value: Int)] = []
    var langTexts: [(key: String, value: Int)] = []
    var totalEntries: Int = 0
    var totalTextLength: Int = 0
    var details: String = ""
}

struct StatisticsView: View {
    @EnvironmentObject var textModel: TextModel
    @EnvironmentObject var shareData: ShareData

    // 統合データ
    @State private var combinedStats = StatisticsData()

    // 個別データ
    @State private var savedTextStats = StatisticsData()
    @State private var importTextStats = StatisticsData()

    @State private var selectedGraphStyle: GraphStyle = .pie
    @State private var isLoading: Bool = false
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = "処理中です..."
    @State private var processingStep: String = "データを読み込み中..."

    // 表示モード選択
    @State private var selectedDataSource: DataSource = .combined

    var body: some View {
        ZStack {
            VStack {
                // 更新ボタン
                HStack {
                    Button(action: {
                        Task {
                            await loadStatisticsAsync()
                        }
                    }) {
                        Label("Update Statistics", systemImage: "arrow.clockwise")
                            .font(.headline)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isLoading)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal)

                // データソース選択セグメント
                Picker("Data Source", selection: $selectedDataSource) {
                    Text("Combined").tag(DataSource.combined)
                    Text("savedTexts").tag(DataSource.savedTexts)
                    Text("importTexts").tag(DataSource.importTexts)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)

                if isLoading {
                    loadingView
                } else {
                    // 現在選択されているデータソースに基づいて表示
                    ScrollView {
                        statisticsView(for: currentStats)
                            .padding(.horizontal)
                    }
                }
            }

            // ローディングオーバーレイ
            if isLoading {
                Color.black.opacity(0.15)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
            }
        }
    }

    // 現在選択されているデータソースに対応する統計データを返す
    private var currentStats: StatisticsData {
        switch selectedDataSource {
        case .combined:
            return combinedStats
        case .savedTexts:
            return savedTextStats
        case .importTexts:
            return importTextStats
        }
    }

    // ローディング中のビュー
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView("Loading Statistics...")
                .padding()

            // プログレスバー
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(maxWidth: 300)
                .padding(.horizontal)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            // アニメーション付きローディングアイコン
            HStack(spacing: 15) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                    .imageScale(.large)
                    .rotationEffect(.degrees(progress * 360))
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: false), value: progress)

                Image(systemName: "chart.pie.fill")
                    .foregroundColor(.green)
                    .imageScale(.large)
                    .scaleEffect(1.0 + sin(progress * .pi * 2) * 0.2)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: progress)

                Image(systemName: "text.magnifyingglass")
                    .foregroundColor(.orange)
                    .imageScale(.large)
                    .opacity(0.5 + sin(progress * .pi) * 0.5)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: progress)
            }
            .padding(.top, 8)

            Text(statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Text(processingStep)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.top, 2)
        }
    }

    // 統計情報の表示
    private func statisticsView(for data: StatisticsData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 統計の詳細テキスト
            Text(data.details)
                .font(.system(.body, design: .monospaced))
                .padding()

            // グラフ表示
            if selectedGraphStyle == .bar {
                Text("アプリごとのテキスト量")
                    .font(.headline)
                    .padding(.top, 8)

                BarChartView(data: data.appTexts, total: data.totalTextLength)
                    .frame(height: 300)
                    .padding(.vertical, 8)
            } else if selectedGraphStyle == .pie {
                HStack() {
                    VStack {
                        Text("アプリごとのテキスト量")
                            .font(.headline)
                            .padding(.top, 8)

                        PieChartView(data: data.appTexts, total: data.totalTextLength)
                            .frame(height: 250)
                            .padding(.vertical, 8)
                    }

                    VStack{
                        Text("言語別テキスト比率")
                            .font(.headline)
                            .padding(.top, 8)

                        PieChartView(data: data.langTexts, total: data.totalTextLength)
                            .frame(height: 250)
                            .padding(.vertical, 8)
                    }
                }
            } else if selectedGraphStyle == .detail {
                Text("詳細データ")
                    .font(.headline)
                    .padding(.top, 8)

                DetailView(data: data.appTexts)
                    .frame(height: 300)
                    .padding(.vertical, 8)
            }

            // グラフスタイル選択
            Picker("", selection: $selectedGraphStyle) {
                Text("Pie").tag(GraphStyle.pie)
                Text("Bar").tag(GraphStyle.bar)
                Text("Detail").tag(GraphStyle.detail)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical)
        }
    }
}

// データソース選択用の列挙型
enum DataSource {
    case combined
    case savedTexts
    case importTexts
}

// StatisticsView の拡張
extension StatisticsView {
    // 非同期で統計情報を読み込む
    func loadStatisticsAsync() async {
        // UIを更新するため、メインスレッドで実行
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.3)) {
                isLoading = true
                progress = 0.0
                statusMessage = "準備中..."
                processingStep = "統計処理を開始します"
            }
        }

        // 非同期で統計処理を実行
        let result = await textModel.generateSeparatedStatisticsAsync(
            avoidApps: shareData.avoidApps,
            minTextLength: shareData.minTextLength,
            progressCallback: { newProgress in
                // プログレスの更新をメインスレッドで実行
                Task { @MainActor in
                    self.progress = newProgress
                }
            },
            statusCallback: { status, step in
                // ステータスメッセージの更新をメインスレッドで実行
                Task { @MainActor in
                    self.statusMessage = status
                    self.processingStep = step
                }
            }
        )

        // 少し遅延を入れて、完了アニメーションを表示
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        await MainActor.run {
            // 結合データ
            self.combinedStats.appNameCounts = result.combined.0
            self.combinedStats.appTexts = result.combined.1
            self.combinedStats.totalEntries = result.combined.2
            self.combinedStats.totalTextLength = result.combined.3
            self.combinedStats.details = result.combined.4
            self.combinedStats.langTexts = result.combined.5

            // savedTexts データ
            self.savedTextStats.appNameCounts = result.savedTexts.0
            self.savedTextStats.appTexts = result.savedTexts.1
            self.savedTextStats.totalEntries = result.savedTexts.2
            self.savedTextStats.totalTextLength = result.savedTexts.3
            self.savedTextStats.details = result.savedTexts.4
            self.savedTextStats.langTexts = result.savedTexts.5

            // importTexts データ
            self.importTextStats.appNameCounts = result.importTexts.0
            self.importTextStats.appTexts = result.importTexts.1
            self.importTextStats.totalEntries = result.importTexts.2
            self.importTextStats.totalTextLength = result.importTexts.3
            self.importTextStats.details = result.importTexts.4
            self.importTextStats.langTexts = result.importTexts.5

            // アプリ名リストを更新
            shareData.apps = self.combinedStats.appNameCounts.map { $0.key }

            // アニメーションでローディング表示を終了
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }
        }
    }
}
