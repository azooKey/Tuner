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
        let folderURL = url.deletingLastPathComponent()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
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
        VStack(alignment: .leading, spacing: 12) {
            // アクセシビリティセクション
            GroupBox(label: Label("アクセシビリティ", systemImage: "accessibility").font(.subheadline)) {
                Toggle("アクセシビリティを有効化", isOn: $shareData.activateAccessibility)
                    .toggleStyle(.switch)
                    .onChange(of: shareData.activateAccessibility) { _, newValue in
                        shareData.activateAccessibility = newValue
                        if newValue {
                            shareData.requestAccessibilityPermission()
                        }
                    }
            }
            .padding(.vertical, 4)
            
            // 保存設定セクション
            GroupBox(label: Label("保存設定", systemImage: "square.and.arrow.down").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("データを保存する", isOn: $textModel.isDataSaveEnabled)
                        .toggleStyle(.switch)
                    
                    // しきい値設定
                    VStack(spacing: 4) {
                        HStack {
                            Text("行数閾値:")
                                .font(.footnote)
                            Spacer()
                            Text("\(shareData.saveLineTh)行")
                                .font(.footnote)
                        }
                        Slider(value: Binding(
                            get: { Double(shareData.saveLineTh) },
                            set: { shareData.saveLineTh = Int($0) }
                        ), in: 10...100, step: 10)
                        
                        HStack {
                            Text("保存間隔:")
                                .font(.footnote)
                            Spacer()
                            Text("\(shareData.saveIntervalSec)秒")
                                .font(.footnote)
                        }
                        Slider(value: Binding(
                            get: { Double(shareData.saveIntervalSec) },
                            set: { shareData.saveIntervalSec = Int($0) }
                        ), in: 10...600, step: 10)
                        
                        HStack {
                            Text("最小テキスト長:")
                                .font(.footnote)
                            Spacer()
                            Text("\(shareData.minTextLength)文字")
                                .font(.footnote)
                        }
                        Slider(value: Binding(
                            get: { Double(shareData.minTextLength) },
                            set: { shareData.minTextLength = Int($0) }
                        ), in: 0...100, step: 10)
                    }
                }
            }
            .padding(.vertical, 4)
            
            // ポーリング設定セクション
            GroupBox(label: Label("ポーリング間隔", systemImage: "timer").font(.subheadline)) {
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
            .padding(.vertical, 4)
            
            // 自動学習設定セクション
            GroupBox(label: Label("自動学習", systemImage: "clock.arrow.circlepath").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("毎日自動でoriginal_marisaを更新", isOn: $shareData.autoLearningEnabled)
                        .toggleStyle(.switch)
                        .onChange(of: shareData.autoLearningEnabled) { _, newValue in
                            textModel.updateAutoLearningSettings()
                        }
                    
                    if shareData.autoLearningEnabled {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("実行時刻:")
                                .font(.footnote)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 8) {
                                // 時間選択
                                Picker("時", selection: $shareData.autoLearningHour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text("\(hour)時").tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .onChange(of: shareData.autoLearningHour) { _, _ in
                                    textModel.updateAutoLearningSettings()
                                }
                                
                                // 分選択
                                Picker("分", selection: $shareData.autoLearningMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text("\(minute)分").tag(minute)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 80)
                                .onChange(of: shareData.autoLearningMinute) { _, _ in
                                    textModel.updateAutoLearningSettings()
                                }
                                
                                Spacer()
                            }
                            
                            // 次回実行予定時刻の表示（軽量計算）
                            Text("次回実行予定: 毎日 \(shareData.autoLearningHour):\(String(format: "%02d", shareData.autoLearningMinute))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 最終自動学習日時の表示
                    if let lastAutoLearningDate = textModel.lastOriginalModelTrainingDate {
                        Divider()
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("最終自動学習: \(lastAutoLearningDate, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            
            // 保存ステータス
            if let lastSavedDate = textModel.lastSavedDate {
                GroupBox(label: Label("最終保存", systemImage: "info.circle").font(.subheadline)) {
                    Text(lastSavedDate, formatter: dateFormatter)
                        .font(.footnote)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    /// データ管理セクション
    /// - ファイル保存場所の表示
    /// - データ状態の表示
    /// - データ管理アクション
    var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // パス表示セクション
            GroupBox(label: Label("保存場所", systemImage: "folder").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    // 保存先 JSONL パス
                    fileLocationRow(label: "JSONL:", path: textModel.getFileURL())

                    Divider()

                    // インポートフォルダパス（変更可能）
                    importFolderRow()
                }
                .padding(.vertical, 4)
            }
            .padding(.bottom, 4)

            // 状態表示セクション
            GroupBox(label: Label("データ状態", systemImage: "info.circle").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    // 最終保存日時
                    HStack {
                        Image(systemName: "arrow.down.doc")
                            .foregroundColor(textModel.lastSavedDate == nil ? .gray : .blue)
                        Text("最終保存:")
                            .font(.caption)
                        if let lastSavedDate = textModel.lastSavedDate {
                            Text(lastSavedDate, formatter: dateFormatter)
                                .font(.caption)
                        } else {
                            Text("データなし")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.bottom, 4)

            // アクションセクション
            GroupBox(label: Label("アクション", systemImage: "gearshape").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 10) {
                    // インポートボタン、リセットボタン、最終状況表示のHStack
                    HStack {
                        // インポートボタン
                        Button {
                            Task {
                                await textModel.importTextFiles(shareData: shareData, avoidApps: shareData.avoidApps, minTextLength: shareData.minTextLength)
                            }
                        } label: {
                            Label("ファイルインポート", systemImage: "square.and.arrow.down")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRefreshing)

                        // インポート履歴リセットボタン (インポートフォルダが設定されている場合のみ表示)
                        if shareData.importBookmarkData != nil {
                             Button(role: .destructive) {
                                 showingResetAlert = true
                             } label: {
                                 Label("リセット", systemImage: "trash")
                                     .font(.caption)
                             }
                             .buttonStyle(.bordered)
                             .controlSize(.small)
                             .help("import.jsonlとインポート記録を削除")
                        }

                        Spacer()

                        // 最終インポート状況を表示
                        if let lastImportDate = shareData.lastImportDateAsDate {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("最終チェック: \(lastImportDate, formatter: dateFormatter)")
                                if shareData.lastImportedFileCount >= 0 {
                                    Text("最後に \(shareData.lastImportedFileCount) ファイルをインポート")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                             Text("未実行")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // インポート機能の説明
                    Text("インポートフォルダ内の `.txt` ファイルを読み込み、`savedText.jsonl` に追加します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("既にインポート済みのファイルはスキップされます。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    // N-gram 訓練ボタンと最終訓練日時
                    VStack(spacing: 8) {
                        // 上段: original_marisa手動再構築
                        HStack {
                            Button {
                                Task {
                                    await textModel.trainOriginalModelManually() // 手動でoriginal_marisaを再構築
                                }
                            } label: {
                                Label("original_marisa手動再構築", systemImage: "arrow.triangle.2.circlepath.circle")
                                    .font(.footnote)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("保存された全データからoriginal_marisaモデルを手動で再構築します。")

                            Spacer()

                            // 最終original_marisa訓練日時を表示
                            if let lastOriginalTrainingDate = textModel.lastOriginalModelTrainingDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.blue)
                                    Text("最終original訓練: \(lastOriginalTrainingDate, formatter: dateFormatter)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.orange)
                                    Text("original未訓練")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        
                        // 下段: 従来のlm関連ボタン
                        HStack {
                            // 全データ再構築ボタン (lm初期化用)
                            Button {
                                Task {
                                    await textModel.trainNGramFromTextEntries() // original モデルを生成
                                }
                            } label: {
                                Label("N-gram再構築 (全データ)", systemImage: "arrow.triangle.2.circlepath.circle")
                                    .font(.footnote)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("保存された全データから original モデルと lm モデルの初期状態を再生成します。")

                            // 追加学習ボタン
                            Button {
                                Task {
                                    await textModel.trainIncrementalNGramManually() // 実装済みのメソッドを呼び出す
                                }
                            } label: {
                                Label("N-gram追加学習 (lm)", systemImage: "plus.circle")
                                    .font(.footnote)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("保存されたデータを使用して既存の lm モデルを更新します。")

                            Spacer()

                            // 最終lm訓練日時を表示
                            if let lastTrainingDate = textModel.lastNGramTrainingDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.green)
                                    Text("最終lm訓練: \(lastTrainingDate, formatter: dateFormatter)")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.orange)
                                    Text("lm未訓練")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider() // アクション間の区切り線を追加

                    // データ整理ボタン
                    HStack {
                        Button {
                            Task {
                                // データ整理処理を呼び出す
                                await textModel.purifyFile(avoidApps: shareData.avoidApps, minTextLength: shareData.minTextLength) {}
                            }
                        } label: {
                            Label("データ整理を実行", systemImage: "sparkles")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        // 最終整理日時を表示（アクションセクションにも追加）
                        if let lastPurifyDate = textModel.lastPurifyDate {
                             HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal")
                                    .foregroundColor(.orange)
                                Text("最終整理: \(lastPurifyDate, formatter: dateFormatter)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.gray)
                                Text("未実行")
                            }
                           .font(.caption)
                           .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
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
            Text("`import.jsonl` ファイルと記録された日時/ファイル数が削除されます。よろしいですか？")
        }
    }

    // ファイル/フォルダパス表示用の補助ビュー
    private func fileLocationRow(label: String, path: URL, isDirectory: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .frame(width: 60, alignment: .leading) // ラベル幅を固定

            // パス表示 (省略表示) - フルパス表示に変更
            Text(path.path) // .lastPathComponent を削除
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle) // 中央を省略

            Spacer()

            // Finderで開くボタン
            Button {
                if isDirectory {
                    // ディレクトリを開く
                     NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                } else {
                    // ファイルを含むフォルダを開く
                    openFolderInFinder(url: path)
                }
            } label: {
                Image(systemName: "folder")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            .help("Finderで表示") // ツールチップ追加
        }
    }

    // インポートフォルダのパス表示と設定変更用の補助ビュー
    private func importFolderRow() -> some View {
        HStack {
            Text("インポート:")
                .font(.footnote)
                .frame(width: 60, alignment: .leading)

            // パス表示 (クリックでFinder表示)
            Button(action: openImportFolderInFinder) {
                // パスが空でなく、ファイルURLとして有効な場合にlastPathComponentを表示 - フルパス表示に変更
                let pathToShow = shareData.importTextPath.isEmpty ? "未設定" : shareData.importTextPath
                Text(pathToShow)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // ブックマークが存在しない場合はグレー表示
                    .foregroundColor(shareData.importBookmarkData == nil ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            // ブックマークが存在しない場合は無効
            .disabled(shareData.importBookmarkData == nil)
            // ツールチップにはフルパスを表示（ブックマークがあれば）
            .help(shareData.importBookmarkData == nil ? "" : shareData.importTextPath)

            Spacer()

            // フォルダ選択ボタン
            Button("変更") {
                selectImportFolder()
            }
            .font(.footnote)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("インポートフォルダを選択")

            // Finderで開くボタン (TextFieldのクリックと機能重複するが、視認性のために残す)
            Button {
                 openImportFolderInFinder()
            } label: {
                Image(systemName: "folder")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            // ブックマークが存在しない場合は無効
            .disabled(shareData.importBookmarkData == nil)
            .help(shareData.importBookmarkData == nil ? "" : "Finderでインポートフォルダを表示")
        }
    }
    
    // インポートフォルダを選択するためのパネルを表示
    private func selectImportFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "インポートフォルダを選択してください"
        openPanel.message = "テキストファイルを含むフォルダを選択してください。"
        openPanel.prompt = "選択"

        // パネル表示前にフラグを立てる
        shareData.isImportPanelShowing = true

        openPanel.begin { response in
            // パネルが閉じたらフラグを下ろす → ハンドラの最後に移動
            // 完了ハンドラはメインスレッドで実行されるため、ここで安全に更新できる
            // shareData.isImportPanelShowing = false

            if response == .OK, let url = openPanel.url {
                // ブックマーク生成と状態更新をバックグラウンドで行う
                Task.detached(priority: .userInitiated) {
                    var newBookmarkData: Data?
                    var errorMessage: String?

                    do {
                        // 時間のかかる可能性のあるブックマーク生成
                        newBookmarkData = try url.bookmarkData(options: .withSecurityScope,
                                                               includingResourceValuesForKeys: nil,
                                                               relativeTo: nil)
                        print("ブックマークを生成しました: \(url.path)")
                    } catch {
                        errorMessage = "ブックマークの作成に失敗しました: \(error.localizedDescription)"
                        print(errorMessage ?? "")
                    }

                    // メインスレッドで状態を更新
                    await MainActor.run {
                        if let newBookmarkData = newBookmarkData {
                            shareData.importTextPath = url.path
                            shareData.importBookmarkData = newBookmarkData
                        } else {
                            // エラー発生時はクリア
                            shareData.importTextPath = ""
                            shareData.importBookmarkData = nil
                            // 必要であればユーザーにエラーを通知する処理を追加
                        }
                    }
                }
            }

            // パネルが閉じる処理（完了、キャンセル、エラー）の最後にフラグを下ろす
            shareData.isImportPanelShowing = false
        }
    }

    // 設定されたインポートフォルダをFinderで開く
    private func openImportFolderInFinder() {
        guard let bookmarkData = shareData.importBookmarkData else {
            print("ブックマークデータが見つかりません。")
            return
        }

        // ブックマーク解決とFinder表示をバックグラウンド→メインスレッドで行う
        Task.detached(priority: .userInitiated) {
            var resolvedURL: URL?
            var isStale = false
            var accessGranted = false
            var errorMessage: String?

            do {
                // 時間のかかる可能性のあるブックマーク解決
                resolvedURL = try URL(resolvingBookmarkData: bookmarkData,
                                      options: [.withSecurityScope],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)

                guard let url = resolvedURL else {
                    throw URLError(.badURL) // 簡略化のため。より具体的なエラーを定義しても良い
                }

                if isStale {
                    errorMessage = "ブックマークが古くなっています。再選択が必要です。"
                    print(errorMessage ?? "")
                    // 必要であればメインスレッドでブックマークをクリア
                    // await MainActor.run { ... }
                    return
                }

                // 時間のかかる可能性のあるアクセス権取得
                accessGranted = url.startAccessingSecurityScopedResource()
                if !accessGranted {
                    errorMessage = "フォルダへのアクセス権を取得できませんでした: \(url.path)"
                    print(errorMessage ?? "")
                    // アクセス権取得失敗時はここで終了
                    return
                }

                // アクセス権取得成功後、メインスレッドでFinderを開く
                await MainActor.run {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    print("Finderで開きました: \(url.path)")
                }

            } catch {
                errorMessage = "ブックマークからのURL解決またはアクセス権取得に失敗しました: \(error.localizedDescription)"
                print(errorMessage ?? "")
                // 必要であればメインスレッドでエラーをユーザーに通知 or ブックマーククリア
                // await MainActor.run { ... }
            }

            // アクセス権取得を試みた場合、最後に必ず解放処理を行う
            // startAccessingSecurityScopedResource が呼ばれた後でのみ stop を呼ぶ
            if let url = resolvedURL, accessGranted {
                 // url.stopAccessingSecurityScopedResource() // stopAccessingSecurityScopedResourceは、アクセスが不要になったらすぐに呼び出すべきです。Finderが開いた後すぐに不要になるかはユースケースによりますが、ここではTask終了時に解放します。
                // startAccessingSecurityScopedResourceと対になるように、Taskのスコープを抜ける際に確実に呼ばれるようにします。
                // deferブロックをTask.detached内で使用することも検討できますが、ここでは最後に配置します。
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

// MARK: - AppExclusion Section
extension SettingsView {
    // MARK: - アプリ除外セクション
    var appExclusionSection: some View {
        VStack(spacing: 12) {
            // アプリアイコン取得とアプリリスト更新
            GroupBox(label: Label("アプリケーション管理", systemImage: "app.badge.checkmark").font(.subheadline)) {
                VStack(spacing: 8) {
                    HStack {
                        Button(action: {
                            updateRunningApps()
                        }) {
                            HStack {
                                if isRefreshing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("アプリリスト更新")
                                    .font(.footnote)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRefreshing)
                        
                        Spacer()
                        
                        if !shareData.avoidApps.isEmpty {
                            Menu {
                                Button(role: .destructive, action: {
                                    shareData.avoidApps.removeAll()
                                }) {
                                    Label("すべて解除", systemImage: "trash")
                                }
                            } label: {
                                Label("", systemImage: "ellipsis.circle")
                                    .font(.footnote)
                            }
                            .menuStyle(.borderlessButton)
                            .controlSize(.small)
                        }
                    }
                    
                    // 検索フィールド
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("アプリを検索...", text: $searchText)
                            .font(.footnote)
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    // 除外アプリ数表示
                    HStack {
                        Text("実行中のアプリ: \(shareData.apps.count)個")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text("除外中: \(shareData.avoidApps.count)個")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            }
            .padding(.bottom, 4)
            
            // 除外中のアプリリスト（存在する場合）
            if !shareData.avoidApps.isEmpty {
                excludedAppsGroup
            }
            
            // アプリケーションリスト
            runningAppsGroup
        }
    }
    
    // 除外中アプリを表示するためのGroupBox
    private var excludedAppsGroup: some View {
        GroupBox(label: Label("除外中のアプリ", systemImage: "xmark.app").font(.subheadline)) {
            excludedAppsScrollView
        }
        .padding(.bottom, 4)
    }
    
    // 除外中アプリのスクロールビュー
    private var excludedAppsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shareData.avoidApps.sorted(), id: \.self) { appName in
                    excludedAppItem(appName)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // 個別の除外アプリアイテム表示
    private func excludedAppItem(_ appName: String) -> some View {
        VStack {
            appIconView(for: appName, size: 24)
            
            Text(appName)
                .font(.system(size: 9))
                .lineLimit(1)
                .frame(maxWidth: 60)
            
            Button(action: {
                shareData.toggleAppExclusion(appName)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
        }
        .padding(4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    // アプリアイコン表示用のビュー
    private func appIconView(for appName: String, size: CGFloat) -> some View {
        Group {
            if let icon = appIcons[appName] {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
    
    // 実行中アプリを表示するためのGroupBox
    private var runningAppsGroup: some View {
        GroupBox(label: Label(searchText.isEmpty ? "実行中のアプリ" : "検索結果", systemImage: "app").font(.subheadline)) {
            if filteredApps.isEmpty {
                emptyAppsView
            } else {
                appListView
            }
        }
    }
    
    // アプリが見つからない場合のビュー
    private var emptyAppsView: some View {
        HStack {
            Spacer()
            Text(searchText.isEmpty ? "アプリが見つかりません" : "「\(searchText)」に一致するアプリがありません")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding()
            Spacer()
        }
    }
    
    // アプリのリスト表示
    private var appListView: some View {
        List {
            ForEach(filteredApps, id: \.self) { appName in
                appRow(for: appName)
            }
        }
        .frame(height: 250)
        .listStyle(.plain)
    }
    
    // 個別のアプリ行
    private func appRow(for appName: String) -> some View {
        HStack {
            Button(action: {
                withAnimation {
                    shareData.toggleAppExclusion(appName)
                }
            }) {
                HStack {
                    // アプリアイコン
                    appIconView(for: appName, size: 16)
                    
                    // アプリ名
                    Text(appName)
                        .font(.footnote)
                    
                    Spacer()
                    
                    // 除外状態表示
                    appStatusBadge(for: appName)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
    
    // アプリの状態表示バッジ
    private func appStatusBadge(for appName: String) -> some View {
        Group {
            if shareData.isAppExcluded(appName) {
                Text("除外中")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
            } else {
                Text("監視中")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - SettingsView Extension for App Icons
extension SettingsView {
    // アプリリスト更新（アイコン取得を含む）
    func updateRunningApps() {
        // 既にリフレッシュ中なら何もしない
        guard !isRefreshing else { return }
        
        isRefreshing = true
        loadingMessage = "アプリリスト取得中..."
        
        // まずアプリリストだけ更新（高速）
        shareData.updateRunningApps()
        
        // 次にバックグラウンドスレッドでアイコンを読み込む
        Task.detached(priority: .background) {
            await loadAppIconsAsync()
        }
    }
    
    // 非同期でアプリアイコンを取得
    @MainActor
    func loadAppIconsAsync() async {
        // アイコンをクリア
        appIcons.removeAll()
        
        loadingMessage = "アプリアイコン読み込み中..."
        
        // 各アプリのアイコンを取得
        let workspace = NSWorkspace.shared
        
        // まず実行中のアプリアイコンを取得
        for appName in shareData.apps {
            await loadIconForAppAsync(appName, workspace: workspace)
            
            // UIの反応性を保つために少し待機
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ミリ秒
        }
        
        // 次に除外アプリのアイコンを取得（現在実行中でない可能性がある）
        for appName in shareData.avoidApps where appIcons[appName] == nil {
            await loadIconForAppAsync(appName, workspace: workspace)
            
            // UIの反応性を保つために少し待機
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ミリ秒
        }
        
        // 完了
        isRefreshing = false
    }
    
    // 非同期で単一アプリのアイコンを取得
    @MainActor
    private func loadIconForAppAsync(_ appName: String, workspace: NSWorkspace) async {
        var icon: NSImage?
        
        // 公開された非同期コンテキストに移動してファイル操作を行う
        await Task.detached(priority: .background) {
            // バンドルIDからアプリURLを取得
            if let bundleId = getBundleIdentifierForApp(appName),
               let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                icon = workspace.icon(forFile: appURL.path)
            }
            // パスからアプリを検索
            else if let appURL = await findAppPathAsync(for: appName) {
                icon = workspace.icon(forFile: appURL.path)
            }
        }.value
        
        // アイコンが見つかれば設定
        if let icon = icon {
            self.appIcons[appName] = icon
        }
    }
    
    // アプリ名からバンドルIDを推測
    private func getBundleIdentifierForApp(_ appName: String) -> String? {
        // 一般的なAppleアプリのバンドルID
        let knownApps: [String: String] = [
            "Finder": "com.apple.finder",
            "Safari": "com.apple.Safari",
            "Mail": "com.apple.mail",
            "Messages": "com.apple.MobileSMS",
            "Calendar": "com.apple.iCal",
            "Notes": "com.apple.Notes",
            "Photos": "com.apple.Photos",
            "Music": "com.apple.Music",
            "Terminal": "com.apple.Terminal",
            "Xcode": "com.apple.dt.Xcode",
            "システム設定": "com.apple.systempreferences",
            "システム環境設定": "com.apple.systempreferences",
            "App Store": "com.apple.AppStore",
            "Maps": "com.apple.Maps",
            "FaceTime": "com.apple.FaceTime",
            "Books": "com.apple.iBooksX",
            "Preview": "com.apple.Preview",
            "QuickTime Player": "com.apple.QuickTimePlayerX",
            "TextEdit": "com.apple.TextEdit",
            "Calculator": "com.apple.Calculator",
            "Dictionary": "com.apple.Dictionary",
            "Reminders": "com.apple.reminders",
            "Contacts": "com.apple.AddressBook",
            "Home": "com.apple.Home",
        ]
        
        return knownApps[appName]
    }
    
    // アプリ名からアプリへのパスを非同期で検索
    private func findAppPathAsync(for appName: String) async -> URL? {
        // まず/Applicationsフォルダを探索
        let applicationFolderURL = URL(fileURLWithPath: "/Applications")
        if let appURL = await findAppAsync(named: appName, in: applicationFolderURL) {
            return appURL
        }
        
        // 次にユーザーのApplicationsフォルダを探索
        if let userApplicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            if let appURL = await findAppAsync(named: appName, in: userApplicationsURL) {
                return appURL
            }
        }
        
        return nil
    }
    
    // 指定されたディレクトリ内でアプリを非同期で探す
    private func findAppAsync(named appName: String, in directory: URL) async -> URL? {
        guard let fileEnumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        // 一定数のファイルだけ調べて時間がかかりすぎないようにする
        var count = 0
        let maxCount = 100
        
        for case let fileURL as URL in fileEnumerator {
            guard count < maxCount else { break }
            
            if fileURL.pathExtension == "app" && fileURL.lastPathComponent.lowercased().hasPrefix(appName.lowercased()) {
                return fileURL
            }
            
            // UIの反応性を保つために定期的に中断
            if count % 10 == 0 {
                await Task.yield()
            }
            
            count += 1
        }
        
        return nil
    }
}
