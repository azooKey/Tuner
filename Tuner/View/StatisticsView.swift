//
//  StatisticsView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/03.
//

import SwiftUI
import Charts

/// 統計情報を保持するデータ構造体
/// - アプリケーション別のテキスト量
/// - 言語別のテキスト比率
/// - 合計エントリ数と文字数
/// - 詳細情報
struct StatisticsData {
    /// アプリケーション別のエントリ数
    var appNameCounts: [(key: String, value: Int)] = []
    /// アプリケーション別のテキスト量
    var appTexts: [(key: String, value: Int)] = []
    /// 言語別のテキスト量
    var langTexts: [(key: String, value: Int)] = []
    /// 合計エントリ数
    var totalEntries: Int = 0
    /// 合計文字数
    var totalTextLength: Int = 0
    /// 詳細情報（フォーマット済みテキスト）
    var details: String = ""
}

/// 統計情報を表示するビュー
/// - データソースの選択（統合/保存済み/インポート）
/// - グラフ表示（円グラフ/棒グラフ/詳細リスト）
/// - 統計概要の表示
struct StatisticsView: View {
    /// テキストモデル（環境オブジェクト）
    @EnvironmentObject var textModel: TextModel
    /// 共有データ（環境オブジェクト）
    @EnvironmentObject var shareData: ShareData

    /// 統合された統計データ
    @State private var combinedStats = StatisticsData()
    /// 保存済みテキストの統計データ
    @State private var savedTextStats = StatisticsData()
    /// インポートテキストの統計データ
    @State private var importTextStats = StatisticsData()

    /// 選択されたグラフ表示スタイル
    @State private var selectedGraphStyle: GraphStyle = .pie
    /// データ読み込み中かどうか
    @State private var isLoading: Bool = false
    /// 処理の進捗率（0.0-1.0）
    @State private var progress: Double = 0.0
    /// 現在の状態メッセージ
    @State private var statusMessage: String = "処理中です..."
    /// 現在の処理ステップ
    @State private var processingStep: String = "データを読み込み中..."
    /// 選択されたデータソース
    @State private var selectedDataSource: DataSource = .combined

    /// ビューの本体
    /// - ヘッダー：更新ボタンとデータソース選択
    /// - メインコンテンツ：統計情報またはローディング表示
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー：更新ボタンとデータソース選択
            headerView
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // メインコンテンツ：統計情報またはローディング表示
            if isLoading && combinedStats.totalEntries == 0 {
                loadingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    statisticsView(for: currentStats)
                        .padding(8)
                }
            }
        }
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .onAppear {
            if combinedStats.totalEntries == 0 {
                Task {
                    await loadStatisticsAsync()
                }
            }
        }
    }

    /// ヘッダービュー（更新ボタンとデータソース選択）
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()

                Button(action: {
                    Task {
                        await loadStatisticsAsync()
                    }
                }) {
                    Label("統計更新", systemImage: "arrow.clockwise")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
            }

            Picker("データソース", selection: $selectedDataSource) {
                Text("統合").tag(DataSource.combined)
                Text("保存済み").tag(DataSource.savedTexts)
                Text("インポート").tag(DataSource.importTexts)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    /// 現在選択されているデータソースに対応する統計データを返す
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

    /// ローディングオーバーレイ
    /// - 進捗状況の表示
    /// - 状態メッセージの表示
    /// - プログレスバーの表示
    private var loadingOverlay: some View {
        VStack {
            ProgressView {
                VStack(spacing: 4) {
                    Text(statusMessage)
                        .font(.footnote)
                    Text("(\(processingStep))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 150)
                        .padding(.vertical, 4)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .progressViewStyle(CircularProgressViewStyle())
            .scaleEffect(1.0)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.1))
        .edgesIgnoringSafeArea(.all)
    }

    /// ローディング中のビュー（シンプル版）
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("統計情報を読み込み中...")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    /// 統計情報の表示
    /// - Parameters:
    ///   - data: 表示する統計データ
    /// - Returns: 統計情報を表示するビュー
    private func statisticsView(for data: StatisticsData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 統計概要セクション
            GroupBox(label: Label("統計概要", systemImage: "info.circle").font(.subheadline)) {
                if data.details.isEmpty {
                    Text("データがありません。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    Text(data.details)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)

            // グラフ表示セクション
            if data.totalEntries > 0 {
                GroupBox(label: Label("グラフ表示", systemImage: "chart.bar.xaxis").font(.subheadline)) {
                    VStack(spacing: 10) {
                        if selectedGraphStyle == .bar {
                            Text("アプリごとのテキスト量")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BarChartView(data: data.appTexts, total: data.totalTextLength)
                                .frame(height: 250)
                        } else if selectedGraphStyle == .pie {
                            HStack(alignment: .top) {
                                VStack {
                                    Text("アプリ別テキスト量")
                                        .font(.caption)
                                    PieChartView(data: data.appTexts, total: data.totalTextLength)
                                        .frame(height: 200)
                                }
                                VStack {
                                    Text("言語別テキスト比率")
                                        .font(.caption)
                                    PieChartView(data: data.langTexts, total: data.totalTextLength)
                                        .frame(height: 200)
                                }
                            }
                        } else if selectedGraphStyle == .detail {
                            Text("詳細データ")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            DetailView(data: data.appTexts)
                                .frame(height: 250)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .padding(.vertical, 4)

                // グラフ設定セクション
                GroupBox(label: Label("グラフ設定", systemImage: "gearshape").font(.subheadline)) {
                    Picker("", selection: $selectedGraphStyle) {
                        Label("Pie", systemImage: "chart.pie").tag(GraphStyle.pie)
                        Label("Bar", systemImage: "chart.bar").tag(GraphStyle.bar)
                        Label("Detail", systemImage: "list.bullet").tag(GraphStyle.detail)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .padding(.vertical, 2)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// データソースの種類を定義する列挙型
enum DataSource {
    /// 統合データ（保存済みとインポートの合計）
    case combined
    /// 保存済みテキストのデータ
    case savedTexts
    /// インポートテキストのデータ
    case importTexts
}

// StatisticsView の拡張
extension StatisticsView {
    /// 非同期で統計情報を読み込む
    /// - 進捗状況の更新
    /// - データの集計
    /// - グラフの更新
    func loadStatisticsAsync() async {
        await MainActor.run {
            withAnimation(.easeIn(duration: 0.2)) {
                isLoading = true
                progress = 0.0
                statusMessage = "準備中..."
                processingStep = "統計処理を開始します"
            }
        }

        let result = await textModel.generateSeparatedStatisticsAsync(
            avoidApps: shareData.avoidApps,
            minTextLength: shareData.minTextLength,
            progressCallback: { newProgress in
                Task { @MainActor in
                    withAnimation(.linear(duration: 0.1)) {
                        self.progress = newProgress
                    }
                }
            },
            statusCallback: { status, step in
                Task { @MainActor in
                    self.statusMessage = status
                    self.processingStep = step
                }
            }
        )

        await MainActor.run {
            self.combinedStats.appNameCounts = result.combined.0
            self.combinedStats.appTexts = result.combined.1
            self.combinedStats.totalEntries = result.combined.2
            self.combinedStats.totalTextLength = result.combined.3
            self.combinedStats.details = result.combined.4
            self.combinedStats.langTexts = result.combined.5

            self.savedTextStats.appNameCounts = result.savedTexts.0
            self.savedTextStats.appTexts = result.savedTexts.1
            self.savedTextStats.totalEntries = result.savedTexts.2
            self.savedTextStats.totalTextLength = result.savedTexts.3
            self.savedTextStats.details = result.savedTexts.4
            self.savedTextStats.langTexts = result.savedTexts.5

            self.importTextStats.appNameCounts = result.importTexts.0
            self.importTextStats.appTexts = result.importTexts.1
            self.importTextStats.totalEntries = result.importTexts.2
            self.importTextStats.totalTextLength = result.importTexts.3
            self.importTextStats.details = result.importTexts.4
            self.importTextStats.langTexts = result.importTexts.5

            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }
        }
    }
}
