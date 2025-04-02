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

    /// Documents/importText フォルダーのURL
    private var importFolderURL: URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("importText")
    }
    
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

                    // インポートフォルダパス
                    fileLocationRow(label: "インポート:", path: importFolderURL, isDirectory: true)
                }
                .padding(.vertical, 4)
            }
            .padding(.bottom, 4)

            // 状態表示セクション
            GroupBox(label: Label("データ状態", systemImage: "info.circle").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 8) {
                    // 最終保存日時
                    if let lastSavedDate = textModel.lastSavedDate {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                                .foregroundColor(.blue)
                            Text("最終保存:")
                                .font(.caption)
                            Text(lastSavedDate, formatter: dateFormatter)
                                .font(.caption)
                        }
                    }
                    
                    // 最終purify日時
                    if let lastPurifyDate = textModel.lastPurifyDate {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.green)
                            Text("最終整理:")
                                .font(.caption)
                            Text(lastPurifyDate, formatter: dateFormatter)
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.bottom, 4)

            // アクションセクション
            GroupBox(label: Label("アクション", systemImage: "gearshape").font(.subheadline)) {
                VStack(alignment: .leading, spacing: 10) {
                    // インポートボタン
                    HStack {
                        Button {
                            Task {
                                await textModel.importTextFiles(avoidApps: shareData.avoidApps, minTextLength: shareData.minTextLength)
                            }
                        } label: {
                            Label("テキストファイルをインポート", systemImage: "square.and.arrow.down")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }

                    Divider()

                    // N-gram 訓練ボタンと最終訓練日時
                    HStack {
                        Button {
                            Task {
                                await textModel.trainNGramFromTextEntries()
                            }
                        } label: {
                            Label("N-gramモデル訓練", systemImage: "wand.and.stars")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        // 最終訓練日時を表示
                        if let lastTrainingDate = textModel.lastNGramTrainingDate {
                             HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                                Text("最終訓練: \(lastTrainingDate, formatter: dateFormatter)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.orange)
                                Text("未訓練")
                            }
                           .font(.caption)
                           .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    // ファイル/フォルダパス表示用の補助ビュー
    private func fileLocationRow(label: String, path: URL, isDirectory: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .frame(width: 60, alignment: .leading) // ラベル幅を固定

            // パス表示 (省略表示)
            Text(path.lastPathComponent)
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
