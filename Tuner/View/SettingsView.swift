//
//  SettingsView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/03.
//

import SwiftUI
import AppKit

/// アプリケーションの設定画面を表示するビュー
/// - 基本設定（アクセシビリティ、保存設定、ポーリング間隔）
/// - データ管理（ファイル保存場所、データ状態、アクション）
/// - アプリケーション除外設定
struct SettingsView: View {
    /// テキストモデル（環境オブジェクト）
    @EnvironmentObject var textModel: TextModel
    /// 共有データ（環境オブジェクト）
    @EnvironmentObject var shareData: ShareData
    /// 選択中の設定セクション
    @State private var selectedSection = 0
    /// アプリリスト更新中かどうか
    @State private var isRefreshing = false
    /// アプリケーションアイコンのキャッシュ
    @State private var appIcons: [String: NSImage] = [:]
    /// アプリケーション検索用のテキスト
    @State private var searchText = ""
    /// ローディング中のメッセージ
    @State private var loadingMessage = "アプリリスト更新中..."
    /// インポート履歴リセット確認アラートの表示状態
    @State private var showingResetAlert = false
    
    // 学習処理の実行状態
    @State private var isTrainingOriginal = false
    @State private var isTrainingLM = false
    @State private var isIncrementalTraining = false
    @State private var isPurifying = false
    @State private var isImporting = false

    /// 検索フィルター適用後のアプリケーションリスト
    private var filteredApps: [String] {
        if searchText.isEmpty {
            return shareData.apps
        } else {
            return shareData.apps.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    /// ビューの本体
    /// - セクション選択用のピッカー
    /// - 選択されたセクションの内容表示
    var body: some View {
        VStack(spacing: 0) {
            // セクション選択用のピッカー
            Picker("設定セクション", selection: $selectedSection) {
                Text("基本設定").tag(0)
                Text("データ管理").tag(1)
                Text("アプリ除外").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            
            // 現在のセクションに応じた内容を表示
            ScrollView {
                VStack {
                    switch selectedSection {
                    case 0:
                        basicSettingsSection
                    case 1:
                        dataManagementSection
                    case 2:
                        appExclusionSection
                    default:
                        basicSettingsSection
                    }
                }
                .padding(8)
            }
        }
        .onAppear {
            updateRunningApps()
        }
        .overlay {
            if isRefreshing {
                loadingOverlay
            }
        }
    }
    
    /// ローディングオーバーレイ
    /// - 進捗状況の表示
    /// - 半透明の背景
    private var loadingOverlay: some View {
        VStack {
            ProgressView(loadingMessage)
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.2))
        }
    }
    
    /// 日付フォーマッター
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }

    /// 指定されたURLのフォルダをFinderで開く
    /// - Parameters:
    ///   - url: 開くフォルダのURL
    private func openFolderInFinder(url: URL) {
        Task.detached(priority: .userInitiated) {
            let folderURL = url.deletingLastPathComponent()
            await MainActor.run {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
            }
        }
    }
}

// MARK: - SettingsView Sections
extension SettingsView {
    /// 基本設定セクション
    /// - アクセシビリティ設定
    /// - データ保存設定
    /// - ポーリング間隔設定
    /// - 最終保存日時表示
    var basicSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // アクセシビリティセクション
            GroupBox {
                Toggle("アクセシビリティを有効化", isOn: $shareData.activateAccessibility)
                    .toggleStyle(.switch)
                    .onChange(of: shareData.activateAccessibility) { _, newValue in
                        shareData.activateAccessibility = newValue
                        if newValue {
                            shareData.requestAccessibilityPermission()
                        }
                    }
            } label: {
                Label("アクセシビリティ", systemImage: "accessibility")
                    .font(.headline)
            }
            
            // データ収集設定セクション
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("データを保存する", isOn: $textModel.isDataSaveEnabled)
                        .toggleStyle(.switch)
                    
                    Divider()
                    
                    // テキスト長設定
                    VStack(alignment: .leading, spacing: 8) {
                        Text("テキスト長フィルター")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // 最小文字数
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("最小", systemImage: "textformat.size.smaller")
                                    .font(.caption)
                                    .frame(width: 60, alignment: .leading)
                                Slider(value: Binding(
                                    get: { Double(shareData.minTextLength) },
                                    set: { shareData.minTextLength = Int($0) }
                                ), in: 0...100, step: 5)
                                Text("\(shareData.minTextLength)文字")
                                    .font(.caption)
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                        
                        // 最大文字数
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("最大", systemImage: "textformat.size.larger")
                                    .font(.caption)
                                    .frame(width: 60, alignment: .leading)
                                Slider(value: Binding(
                                    get: { Double(shareData.maxTextLength) },
                                    set: { shareData.maxTextLength = Int($0) }
                                ), in: 100...10000, step: 100)
                                Text("\(shareData.maxTextLength)文字")
                                    .font(.caption)
                                    .frame(width: 50, alignment: .trailing)
                                    .monospacedDigit()
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 保存タイミング設定
                    VStack(alignment: .leading, spacing: 8) {
                        Text("保存タイミング")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // 行数閾値
                        HStack {
                            Label("行数", systemImage: "text.alignleft")
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: Binding(
                                get: { Double(shareData.saveLineTh) },
                                set: { shareData.saveLineTh = Int($0) }
                            ), in: 10...100, step: 10)
                            Text("\(shareData.saveLineTh)行")
                                .font(.caption)
                                .frame(width: 50, alignment: .trailing)
                                .monospacedDigit()
                        }
                        
                        // 保存間隔
                        HStack {
                            Label("間隔", systemImage: "timer")
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: Binding(
                                get: { Double(shareData.saveIntervalSec) },
                                set: { shareData.saveIntervalSec = Int($0) }
                            ), in: 10...600, step: 10)
                            Text("\(shareData.saveIntervalSec)秒")
                                .font(.caption)
                                .frame(width: 50, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                }
            } label: {
                Label("データ収集設定", systemImage: "square.and.arrow.down")
                    .font(.headline)
            }
            
            // ポーリング設定セクション
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("テキスト取得の間隔を設定します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $shareData.pollingInterval) {
                        Text("無効").tag(0)
                        Text("5秒").tag(5)
                        Text("10秒").tag(10)
                        Text("30秒").tag(30)
                        Text("60秒").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            } label: {
                Label("ポーリング間隔", systemImage: "timer")
                    .font(.headline)
            }
            
            // 自動学習設定セクション
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("毎日自動でoriginal_marisaを更新", isOn: $shareData.autoLearningEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: shareData.autoLearningEnabled) { _, _ in
                            textModel.updateAutoLearningSettings()
                        }
                    
                    if shareData.autoLearningEnabled {
                        Divider()
                        
                        HStack {
                            Text("実行時刻:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $shareData.autoLearningHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour)時").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 70)
                            .onChange(of: shareData.autoLearningHour) { _, _ in
                                textModel.updateAutoLearningSettings()
                            }
                            
                            Picker("", selection: $shareData.autoLearningMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)分").tag(minute)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 70)
                            .onChange(of: shareData.autoLearningMinute) { _, _ in
                                textModel.updateAutoLearningSettings()
                            }
                            
                            Spacer()
                            
                            Text("次回: 毎日 \(shareData.autoLearningHour):\(String(format: "%02d", shareData.autoLearningMinute))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 最終自動学習日時
                    if let lastDate = textModel.lastOriginalModelTrainingDate {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("最終実行: \(lastDate, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } label: {
                Label("自動学習", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
            }
            
            // メモリ管理設定セクション
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    // 現在のメモリ使用状況
                    HStack {
                        Image(systemName: "memorychip")
                            .foregroundColor(shareData.currentMemoryUsageMB > shareData.memoryLimitMB ? .red : .blue)
                        Text("現在のメモリ使用量:")
                            .font(.caption)
                        Text("\(shareData.currentMemoryUsageMB) MB")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(shareData.currentMemoryUsageMB > shareData.memoryLimitMB ? .red : .primary)
                        Text("(\(String(format: "%.1f", shareData.currentMemoryUsagePercent))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Divider()
                    
                    // メモリ上限設定 (MB)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("上限 (MB)", systemImage: "slider.horizontal.below.square.and.square.filled")
                                .font(.caption)
                                .frame(width: 100, alignment: .leading)
                            Slider(value: Binding(
                                get: { Double(shareData.memoryLimitMB) },
                                set: { shareData.memoryLimitMB = Int($0) }
                            ), in: 512...8192, step: 256)
                            Text("\(shareData.memoryLimitMB) MB")
                                .font(.caption)
                                .frame(width: 70, alignment: .trailing)
                                .monospacedDigit()
                        }
                        Text("メモリ使用量がこの値を超えると低メモリモードに移行します")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // メモリ上限設定 (パーセント)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("上限 (%)", systemImage: "percent")
                                .font(.caption)
                                .frame(width: 100, alignment: .leading)
                            Slider(value: Binding(
                                get: { Double(shareData.memoryLimitPercent) },
                                set: { shareData.memoryLimitPercent = Int($0) }
                            ), in: 20...80, step: 5)
                            Text("\(shareData.memoryLimitPercent)%")
                                .font(.caption)
                                .frame(width: 70, alignment: .trailing)
                                .monospacedDigit()
                        }
                        Text("物理メモリに対する使用割合の上限")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } label: {
                Label("メモリ管理", systemImage: "memorychip")
                    .font(.headline)
            }
            
            // ステータス表示
            if let lastSavedDate = textModel.lastSavedDate {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("最終保存: \(lastSavedDate, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }
    
    /// データ管理セクション
    /// - ファイル保存場所の表示
    /// - データ状態の表示
    /// - データ管理アクション
    var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ファイルパス情報
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    // JSONL保存先
                    HStack {
                        Label("データ保存先", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            openFolderInFinder(url: textModel.getFileURL())
                        }) {
                            Image(systemName: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Text(textModel.getFileURL().path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    
                    Divider()
                    
                    // インポートフォルダ
                    HStack {
                        Label("インポートフォルダ", systemImage: "square.and.arrow.down.on.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("変更") {
                            selectImportFolder()
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        
                        if shareData.importBookmarkData != nil {
                            Button(action: openImportFolderInFinder) {
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    
                    if !shareData.importTextPath.isEmpty {
                        Text(shareData.importTextPath)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } else {
                        Text("未設定")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } label: {
                Label("ファイル管理", systemImage: "folder")
                    .font(.headline)
            }
            
            // データインポート
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("テキストファイルインポート")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            if let lastImportDate = shareData.lastImportDateAsDate {
                                Text("最終実行: \(lastImportDate, formatter: dateFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if shareData.lastImportedFileCount >= 0 {
                                    Text("\(shareData.lastImportedFileCount)ファイルをインポート")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("未実行")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    isImporting = true
                                    defer { isImporting = false }
                                    await textModel.importTextFiles(
                                        shareData: shareData,
                                        avoidApps: shareData.avoidApps,
                                        minTextLength: shareData.minTextLength
                                    )
                                }
                            } label: {
                                if isImporting {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("インポート中...")
                                    }
                                } else {
                                    Label("インポート", systemImage: "square.and.arrow.down")
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(shareData.importBookmarkData == nil || isImporting)
                            
                            if shareData.importBookmarkData != nil {
                                Button(role: .destructive) {
                                    showingResetAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .help("インポート履歴をリセット")
                            }
                        }
                    }
                    
                    Text("インポートフォルダ内の.txt、.md、.pdfファイルを読み込みます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } label: {
                HStack {
                    Label("データインポート", systemImage: "square.and.arrow.down.on.square")
                        .font(.headline)
                    if isImporting {
                        Spacer()
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("実行中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // 学習モデル管理
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    // Original Marisa
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Original Marisa")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            if let lastDate = textModel.lastOriginalModelTrainingDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("最終訓練: \(lastDate, formatter: dateFormatter)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("未訓練")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            Task {
                                isTrainingOriginal = true
                                defer { isTrainingOriginal = false }
                                await textModel.trainOriginalModelManually()
                            }
                        } label: {
                            if isTrainingOriginal {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("訓練中...")
                                }
                            } else {
                                Label("手動再構築", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(isTrainingOriginal)
                    }
                    
                    Divider()
                    
                    // LM Model
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LM Model")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            if let lastDate = textModel.lastNGramTrainingDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("最終訓練: \(lastDate, formatter: dateFormatter)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("未訓練")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    isTrainingLM = true
                                    defer { isTrainingLM = false }
                                    await textModel.trainNGramFromTextEntries()
                                }
                            } label: {
                                if isTrainingLM {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("再構築中...")
                                    }
                                } else {
                                    Label("再構築", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(isTrainingLM || isIncrementalTraining)
                            
                            Button {
                                Task {
                                    isIncrementalTraining = true
                                    defer { isIncrementalTraining = false }
                                    await textModel.trainIncrementalNGramManually()
                                }
                            } label: {
                                if isIncrementalTraining {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("学習中...")
                                    }
                                } else {
                                    Label("追加学習", systemImage: "plus.circle")
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(isTrainingLM || isIncrementalTraining)
                        }
                    }
                }
            } label: {
                HStack {
                    Label("学習モデル", systemImage: "brain")
                        .font(.headline)
                    if isTrainingOriginal || isTrainingLM || isIncrementalTraining {
                        Spacer()
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("処理中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // データ整理
            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("重複データ除去")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let lastDate = textModel.lastPurifyDate {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("最終実行: \(lastDate, formatter: dateFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("未実行")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        Task {
                            isPurifying = true
                            defer { isPurifying = false }
                            await textModel.purifyFile(
                                avoidApps: shareData.avoidApps,
                                minTextLength: shareData.minTextLength
                            ) {}
                        }
                    } label: {
                        if isPurifying {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("整理中...")
                            }
                        } else {
                            Label("整理実行", systemImage: "sparkles")
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(isPurifying)
                }
            } label: {
                HStack {
                    Label("データ整理", systemImage: "sparkles")
                        .font(.headline)
                    if isPurifying {
                        Spacer()
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("実行中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .alert("インポート履歴のリセット", isPresented: $showingResetAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("リセット", role: .destructive) {
                Task {
                    await textModel.resetImportHistory(shareData: shareData)
                }
            }
        } message: {
            Text("import.jsonlファイルと記録された日時/ファイル数が削除されます。")
        }
    }
    
    // インポートフォルダを選択
    private func selectImportFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "インポートフォルダを選択"
        openPanel.message = "テキストファイル（.txt、.md、.pdf）を含むフォルダを選択してください"
        openPanel.prompt = "選択"

        shareData.isImportPanelShowing = true

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                Task.detached(priority: .userInitiated) {
                    var newBookmarkData: Data?
                    var errorMessage: String?

                    do {
                        newBookmarkData = try url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                    } catch {
                        errorMessage = "ブックマークの作成に失敗しました: \(error.localizedDescription)"
                        print(errorMessage ?? "")
                    }

                    await MainActor.run {
                        if let newBookmarkData = newBookmarkData {
                            shareData.importTextPath = url.path
                            shareData.importBookmarkData = newBookmarkData
                        } else {
                            shareData.importTextPath = ""
                            shareData.importBookmarkData = nil
                        }
                    }
                }
            }
            shareData.isImportPanelShowing = false
        }
    }

    // インポートフォルダをFinderで開く
    private func openImportFolderInFinder() {
        Task.detached(priority: .userInitiated) {
            await self.openImportFolderInFinderAsync()
        }
    }
    
    // インポートフォルダをFinderで開く（非同期版）
    private func openImportFolderInFinderAsync() async {
        guard let bookmarkData = shareData.importBookmarkData else {
            return
        }

        var resolvedURL: URL?
        var isStale = false
        var accessGranted = false

        do {
            resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard let url = resolvedURL else {
                throw URLError(.badURL)
            }

            if isStale {
                print("ブックマークが古くなっています。再選択が必要です。")
                return
            }

            accessGranted = url.startAccessingSecurityScopedResource()
            if !accessGranted {
                print("フォルダへのアクセス権を取得できませんでした: \(url.path)")
                return
            }

            await MainActor.run {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
            }

        } catch {
            print("ブックマークからのURL解決に失敗しました: \(error.localizedDescription)")
        }

        if let url = resolvedURL, accessGranted {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// MARK: - AppExclusion Section
extension SettingsView {
    // MARK: - アプリ除外セクション
    var appExclusionSection: some View {
        VStack(spacing: 16) {
            // コントロールパネル
            GroupBox {
                VStack(spacing: 10) {
                    // 更新ボタンとステータス
                    HStack {
                        Button(action: updateRunningApps) {
                            HStack(spacing: 4) {
                                if isRefreshing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("アプリリスト更新")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing)
                        
                        Spacer()
                        
                        // ステータス表示
                        HStack(spacing: 12) {
                            Label("\(shareData.apps.count)", systemImage: "app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !shareData.avoidApps.isEmpty {
                                Label("\(shareData.avoidApps.count)除外", systemImage: "xmark.app")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        if !shareData.avoidApps.isEmpty {
                            Button(role: .destructive) {
                                shareData.avoidApps.removeAll()
                            } label: {
                                Label("すべて解除", systemImage: "trash")
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // 検索フィールド
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("アプリを検索...", text: $searchText)
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
            } label: {
                Label("アプリケーション管理", systemImage: "app.badge.checkmark")
                    .font(.headline)
            }
            
            // 除外中のアプリ
            if !shareData.avoidApps.isEmpty {
                GroupBox {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shareData.avoidApps.sorted(), id: \.self) { appName in
                                excludedAppChip(appName)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } label: {
                    Label("除外中のアプリ (\(shareData.avoidApps.count))", systemImage: "xmark.app")
                        .font(.headline)
                        .foregroundColor(.red)
                }
            }
            
            // アプリリスト
            GroupBox {
                if filteredApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: searchText.isEmpty ? "app.dashed" : "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "アプリが見つかりません" : "「\(searchText)」に一致するアプリがありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(filteredApps, id: \.self) { appName in
                            appRow(appName)
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 300)
                }
            } label: {
                Label(searchText.isEmpty ? "実行中のアプリ" : "検索結果", systemImage: "app")
                    .font(.headline)
            }
        }
    }
    
    // 除外中アプリのチップ表示
    private func excludedAppChip(_ appName: String) -> some View {
        HStack(spacing: 4) {
            if let icon = appIcons[appName] {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
                    .font(.caption)
            }
            
            Text(appName)
                .font(.caption)
                .lineLimit(1)
            
            Button(action: {
                withAnimation {
                    shareData.toggleAppExclusion(appName)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    // アプリ行の表示
    private func appRow(_ appName: String) -> some View {
        Button(action: {
            withAnimation {
                shareData.toggleAppExclusion(appName)
            }
        }) {
            HStack {
                // アイコン
                if let icon = appIcons[appName] {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed")
                        .frame(width: 20, height: 20)
                }
                
                // アプリ名
                Text(appName)
                    .font(.system(.body, design: .default))
                
                Spacer()
                
                // ステータス
                if shareData.isAppExcluded(appName) {
                    Label("除外中", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(10)
                } else {
                    Label("監視中", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - SettingsView Extension for App Icons
extension SettingsView {
    // アプリリスト更新
    func updateRunningApps() {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        loadingMessage = "アプリリスト取得中..."
        
        shareData.updateRunningApps()
        
        Task.detached(priority: .background) {
            await self.loadAppIconsAsync()
        }
    }
    
    // アプリアイコンを非同期で取得
    func loadAppIconsAsync() async {
        await MainActor.run {
            self.loadingMessage = "アプリアイコン読み込み中..."
        }
        
        let allApps = Array(Set(shareData.apps + shareData.avoidApps))
        var processedIcons: [String: NSImage] = [:]
        
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for appName in allApps {
                group.addTask {
                    let icon = await self.loadIconForApp(appName)
                    return (appName, icon)
                }
            }
            
            for await (appName, icon) in group {
                if let icon = icon {
                    processedIcons[appName] = icon
                }
                
                if processedIcons.count % 10 == 0 {
                    let currentBatch = processedIcons
                    await MainActor.run {
                        self.appIcons.merge(currentBatch) { _, new in new }
                    }
                    processedIcons.removeAll()
                }
            }
        }
        
        if !processedIcons.isEmpty {
            await MainActor.run {
                self.appIcons.merge(processedIcons) { _, new in new }
            }
        }
        
        await MainActor.run {
            self.isRefreshing = false
        }
    }
    
    // 単一アプリのアイコンを取得
    private func loadIconForApp(_ appName: String) async -> NSImage? {
        return await Task.detached(priority: .background) {
            let workspace = NSWorkspace.shared
            
            if let bundleId = self.getBundleIdentifierForApp(appName),
               let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                return workspace.icon(forFile: appURL.path)
            }
            
            if let appURL = await self.findAppPathAsync(for: appName) {
                return workspace.icon(forFile: appURL.path)
            }
            
            return nil
        }.value
    }
    
    // よく知られたアプリのバンドルID
    private func getBundleIdentifierForApp(_ appName: String) -> String? {
        let knownApps: [String: String] = [
            "Finder": "com.apple.finder",
            "Safari": "com.apple.Safari",
            "Mail": "com.apple.mail",
            "Messages": "com.apple.MobileSMS",
            "Calendar": "com.apple.iCal",
            "Notes": "com.apple.Notes",
            "Terminal": "com.apple.Terminal",
            "Xcode": "com.apple.dt.Xcode",
            "システム設定": "com.apple.systempreferences",
        ]
        
        return knownApps[appName]
    }
    
    // アプリのパスを検索
    private func findAppPathAsync(for appName: String) async -> URL? {
        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        for searchPath in searchPaths {
            if let appURL = await findAppAsync(named: appName, in: searchPath) {
                return appURL
            }
        }
        
        return nil
    }
    
    // 指定ディレクトリ内でアプリを検索
    private func findAppAsync(named appName: String, in directory: URL) async -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        var count = 0
        let maxCount = 100
        
        for case let fileURL as URL in enumerator {
            guard count < maxCount else { break }
            
            if fileURL.pathExtension == "app" && 
               fileURL.lastPathComponent.lowercased().hasPrefix(appName.lowercased()) {
                return fileURL
            }
            
            if count % 10 == 0 {
                await Task.yield()
            }
            
            count += 1
        }
        
        return nil
    }
}