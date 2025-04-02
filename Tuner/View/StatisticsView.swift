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
        VStack(spacing: 0) { // spacing 0 に変更
            // ヘッダー：更新ボタンとデータソース選択
            headerView
                .padding(.horizontal, 8) // padding を追加
                .padding(.top, 8)       // padding を追加
                .padding(.bottom, 8)    // 下部にも padding 追加

            // メインコンテンツ：統計情報またはローディング表示
            if isLoading && combinedStats.totalEntries == 0 { // 初期ロード中はローディング表示
                loadingView // シンプルなローディング表示
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // 中央寄せ
            } else {
                ScrollView { // ScrollView を外側に
                    statisticsView(for: currentStats)
                        .padding(8) // 全体に padding
                }
            }
        }
        .overlay { // ローディング表示を overlay に変更
            if isLoading {
                loadingOverlay
            }
        }
        .onAppear { // 初回表示時に統計情報を読み込む (既にデータがあれば再読み込みしない)
             if combinedStats.totalEntries == 0 {
                 Task {
                     await loadStatisticsAsync()
                 }
             }
         }
    }

    // ヘッダービュー（更新ボタンとデータソース選択）
    private var headerView: some View {
        VStack(spacing: 8) { // spacing を追加
            HStack {
                Spacer() // ボタンを右寄せ

                Button(action: {
                    Task {
                        await loadStatisticsAsync()
                    }
                }) {
                    Label("統計更新", systemImage: "arrow.clockwise") // 日本語に変更
                        .font(.footnote) // フォントサイズ調整
                }
                .buttonStyle(.bordered) // スタイル変更
                .controlSize(.small) // サイズ変更
                .disabled(isLoading)
            }

            Picker("データソース", selection: $selectedDataSource) { // ラベル追加
                Text("統合").tag(DataSource.combined) // 日本語に変更
                Text("保存済み").tag(DataSource.savedTexts) // 日本語に変更
                Text("インポート").tag(DataSource.importTexts) // 日本語に変更
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 8)
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

    // ローディングオーバーレイ (SettingsView に似せる)
    private var loadingOverlay: some View {
        VStack {
            ProgressView {
                VStack(spacing: 4) { // spacing追加
                    Text(statusMessage)
                        .font(.footnote) // サイズ調整
                    Text("(\(processingStep))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 150) // 幅調整
                        .padding(.vertical, 4) // padding調整
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .progressViewStyle(CircularProgressViewStyle())
            .scaleEffect(1.0)
            .padding() // ProgressView自体のパディング
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) // 背景追加
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.1)) // 背景
        .edgesIgnoringSafeArea(.all) // 全画面を覆う
    }

    // ローディング中のビュー (シンプル版、overlay で詳細表示するため)
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("統計情報を読み込み中...")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // 統計情報の表示 (GroupBox を使用)
    private func statisticsView(for data: StatisticsData) -> some View {
        VStack(alignment: .leading, spacing: 12) { // spacing 調整
            // 統計概要セクション
            GroupBox(label: Label("統計概要", systemImage: "info.circle").font(.subheadline)) {
                // data.details が空の場合の表示を追加
                 if data.details.isEmpty {
                     Text("データがありません。")
                         .font(.footnote)
                         .foregroundColor(.secondary)
                         .padding(.vertical, 4)
                 } else {
                     Text(data.details)
                         .font(.system(.footnote, design: .monospaced)) // フォントサイズ調整
                         .lineLimit(nil) // 複数行表示を許可
                         .fixedSize(horizontal: false, vertical: true) // 縦に伸長
                         .padding(.vertical, 4) // 内側の padding
                         .frame(maxWidth: .infinity, alignment: .leading) // 左寄せ確保
                 }
            }
            .padding(.vertical, 4) // GroupBox 間の padding

            // グラフ表示セクション (データがない場合は非表示)
            if data.totalEntries > 0 {
                GroupBox(label: Label("グラフ表示", systemImage: "chart.bar.xaxis").font(.subheadline)) {
                    VStack(spacing: 10) { // グラフ間の spacing
                        if selectedGraphStyle == .bar {
                            Text("アプリごとのテキスト量")
                                .font(.caption) // フォントサイズ調整
                                .frame(maxWidth: .infinity, alignment: .leading)
                            BarChartView(data: data.appTexts, total: data.totalTextLength)
                                .frame(height: 250) // 高さを少し調整
                        } else if selectedGraphStyle == .pie {
                            HStack(alignment: .top) { // 上揃え
                                VStack {
                                    Text("アプリ別テキスト量") // タイトル変更
                                        .font(.caption) // フォントサイズ調整
                                    PieChartView(data: data.appTexts, total: data.totalTextLength)
                                        .frame(height: 200) // 高さを少し調整
                                }
                                VStack {
                                    Text("言語別テキスト比率")
                                        .font(.caption) // フォントサイズ調整
                                    PieChartView(data: data.langTexts, total: data.totalTextLength)
                                        .frame(height: 200) // 高さを少し調整
                                }
                            }
                        } else if selectedGraphStyle == .detail {
                            Text("詳細データ")
                                .font(.caption) // フォントサイズ調整
                                .frame(maxWidth: .infinity, alignment: .leading)
                            DetailView(data: data.appTexts)
                                .frame(height: 250) // 高さを少し調整
                        }
                    }
                    .padding(.vertical, 6) // 内側の padding
                }
                .padding(.vertical, 4)

                // グラフ設定セクション (データがない場合は非表示)
                GroupBox(label: Label("グラフ設定", systemImage: "gearshape").font(.subheadline)) {
                    Picker("", selection: $selectedGraphStyle) {
                        Label("Pie", systemImage: "chart.pie").tag(GraphStyle.pie) // Icon 追加
                        Label("Bar", systemImage: "chart.bar").tag(GraphStyle.bar) // Icon 追加
                        Label("Detail", systemImage: "list.bullet").tag(GraphStyle.detail) // Icon 追加
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden() // ラベルは非表示のまま
                    .controlSize(.small) // サイズ調整
                    .padding(.vertical, 2) // 内側の padding
                }
                .padding(.vertical, 4)
            }
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
            withAnimation(.easeIn(duration: 0.2)) { // アニメーション調整
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
                    // アニメーション付きでプログレスを更新
                    withAnimation(.linear(duration: 0.1)) {
                        self.progress = newProgress
                    }
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

        // 少し遅延を入れて、完了アニメーションを表示（オプション）
        // try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒

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

            // アプリ名リストを更新 (SettingsView との連携のため)
            // shareData.apps = self.combinedStats.appNameCounts.map { $0.key }

            // アニメーションでローディング表示を終了
            withAnimation(.easeOut(duration: 0.3)) { // アニメーション調整
                isLoading = false
            }
        }
    }
}
