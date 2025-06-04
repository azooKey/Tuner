//
//  ShareData.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI
import Combine
import Foundation

/// アプリケーション全体で共有される設定や状態を管理するクラス
/// - アクセシビリティ設定
/// - アプリケーション除外リスト
/// - テキスト取得の設定
/// - データ保存の設定
class ShareData: ObservableObject {
    /// アクセシビリティ機能によるテキスト取得を有効にするか
    @AppStorage("activateAccessibility") var activateAccessibility: Bool = true
    
    /// テキスト取得を除外するアプリケーション名のリスト
    @AppStorage("avoidApps") var avoidAppsData: Data = ShareData.encodeAvoidApps(["Finder", "Tuner"])
    
    /// テキスト取得のポーリング間隔（秒）
    @AppStorage("pollingInterval") var pollingInterval: Int = 5
    
    /// 一度にファイルに保存するテキストエントリ数の閾値
    @AppStorage("saveLineTh") var saveLineTh: Int = 10
    
    /// ファイルへの保存間隔の閾値（秒）
    @AppStorage("saveIntervalSec") var saveIntervalSec: Int = 5
    
    /// 保存するテキストの最小文字数
    @AppStorage("minTextLength") var minTextLength: Int = 3
    
    /// 自動学習機能を有効にするか
    @AppStorage("autoLearningEnabled") var autoLearningEnabled: Bool = true
    
    /// 自動学習を実行する時刻（時）
    @AppStorage("autoLearningHour") var autoLearningHour: Int = 3
    
    /// 自動学習を実行する時刻（分）
    @AppStorage("autoLearningMinute") var autoLearningMinute: Int = 0
    
    /// ユーザーが設定したテキストインポートフォルダのパス (表示用)
    @AppStorage("importTextPath") var importTextPath: String = ""
    /// ユーザーが設定したテキストインポートフォルダへのアクセス権を保持するブックマークデータ
    @Published var importBookmarkData: Data? = nil
    
    /// 最終インポート日時 (Unixタイムスタンプ)
    @Published var lastImportDate: TimeInterval? = nil
    /// 最後にインポートしたファイル数 (-1は未実行)
    @Published var lastImportedFileCount: Int = -1
    
    /// 現在実行中のアプリケーションのリスト (これは永続化しない)
    @Published var apps: [String] = []
    /// インポートフォルダ選択パネルが表示中かどうか (UI制御用、永続化しない)
    @Published var isImportPanelShowing: Bool = false

    // UserDefaultsのキー定義
    private let activateAccessibilityKey = "activateAccessibility"
    private let avoidAppsKey = "avoidApps"
    private let pollingIntervalKey = "pollingInterval"
    private let saveLineThKey = "saveLineTh"
    private let saveIntervalSecKey = "saveIntervalSec"
    private let minTextLengthKey = "minTextLength"
    private let autoLearningEnabledKey = "autoLearningEnabled"
    private let autoLearningHourKey = "autoLearningHour"
    private let autoLearningMinuteKey = "autoLearningMinute"
    private let importTextPathKey = "importTextPath"
    private let importBookmarkDataKey = "importBookmarkData"
    private let lastImportDateKey = "lastImportDate"
    private let lastImportedFileCountKey = "lastImportedFileCount"

    // avoidAppsをData <-> [String] 変換するためのComputed Property
    var avoidApps: [String] {
        get { ShareData.decodeAvoidApps(avoidAppsData) }
        set { avoidAppsData = ShareData.encodeAvoidApps(newValue) }
    }

    /// lastImportDateをDate?型で取得するためのComputed Property
    var lastImportDateAsDate: Date? {
        guard let timestamp = lastImportDate else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    // Combineの購読を管理するためのセット
    private var cancellables = Set<AnyCancellable>()

    /// 初期化時に保存された設定を読み込み、変更を監視
    init() {
        // 重いUserDefaults操作を非同期で実行
        DispatchQueue.global(qos: .utility).async {
            // ブックマークデータをUserDefaultsから読み込む
            let bookmarkData = UserDefaults.standard.data(forKey: self.importBookmarkDataKey)
            // 最終インポート日時をUserDefaultsから読み込む
            let lastImportDateValue: TimeInterval? = {
                if UserDefaults.standard.object(forKey: self.lastImportDateKey) != nil {
                    return UserDefaults.standard.double(forKey: self.lastImportDateKey)
                }
                return nil
            }()
            // 最後にインポートしたファイル数をUserDefaultsから読み込む (存在しなければ-1)
            let lastImportedFileCountValue = UserDefaults.standard.object(forKey: self.lastImportedFileCountKey) as? Int ?? -1
            
            DispatchQueue.main.async {
                self.importBookmarkData = bookmarkData
                self.lastImportDate = lastImportDateValue
                self.lastImportedFileCount = lastImportedFileCountValue
            }
        }

        // importBookmarkDataの変更を監視し、UserDefaultsに保存する
        $importBookmarkData
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main) // 短期間の連続変更をまとめる
            .sink { [weak self] newValue in
                guard let self = self else { return }
                DispatchQueue.global(qos: .utility).async {
                    UserDefaults.standard.set(newValue, forKey: self.importBookmarkDataKey)
                }
                // print("Bookmark data saved to UserDefaults.") // デバッグ用
            }
            .store(in: &cancellables)
        
        // lastImportDateの変更を監視し、UserDefaultsに保存する
        $lastImportDate
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                DispatchQueue.global(qos: .utility).async {
                    if let value = newValue {
                        UserDefaults.standard.set(value, forKey: self.lastImportDateKey)
                    } else {
                        UserDefaults.standard.removeObject(forKey: self.lastImportDateKey)
                    }
                }
            }
            .store(in: &cancellables)
        
        // lastImportedFileCountの変更を監視し、UserDefaultsに保存する
        $lastImportedFileCount
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                DispatchQueue.global(qos: .utility).async {
                    UserDefaults.standard.set(newValue, forKey: self.lastImportedFileCountKey)
                }
            }
            .store(in: &cancellables)
    }

    /// アクセシビリティ権限を要求
    func requestAccessibilityPermission() {
        print("requestAccessibilityPermission")
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 現在実行中のアプリケーションリストを更新
    /// - 通常のアプリケーションのみをフィルタリング
    /// - アプリケーション名をアルファベット順にソート
    func updateRunningApps() {
        // NSWorkspace操作を非同期で実行
        Task.detached(priority: .userInitiated) {
            let workspace = NSWorkspace.shared
            let apps = workspace.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.localizedName }
                .sorted()
            
            await MainActor.run {
                self.apps = apps
            }
        }
    }

    /// アプリケーションの除外設定を切り替え
    /// - Parameters:
    ///   - appName: 対象のアプリケーション名
    func toggleAppExclusion(_ appName: String) {
        var currentAvoidApps = self.avoidApps // Computed propertyから値を取得
        if currentAvoidApps.contains(appName) {
            currentAvoidApps.removeAll { $0 == appName }
        } else {
            currentAvoidApps.append(appName)
        }
        self.avoidApps = currentAvoidApps // Computed property経由で値を設定（自動で保存される）
    }

    /// アプリケーションが除外されているかどうかを確認
    /// - Parameters:
    ///   - appName: 対象のアプリケーション名
    /// - Returns: 除外されている場合はtrue
    func isAppExcluded(_ appName: String) -> Bool {
        return avoidApps.contains(appName)
    }

    // Helper functions for encoding/decoding avoidApps [String] <-> Data
    static func encodeAvoidApps(_ apps: [String]) -> Data {
        (try? JSONEncoder().encode(apps)) ?? Data()
    }
    
    static func decodeAvoidApps(_ data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

#if DEBUG
extension ShareData {
    /// デバッグ用：設定をデフォルト値にリセット
    func resetToDefaults() {
        // @AppStorageで管理されているものはUserDefaultsから削除するだけで初期値に戻る
        UserDefaults.standard.removeObject(forKey: activateAccessibilityKey)
        // avoidAppsDataはData型なので、キー削除でデフォルト値に戻る
        UserDefaults.standard.removeObject(forKey: avoidAppsKey)
        UserDefaults.standard.removeObject(forKey: pollingIntervalKey)
        UserDefaults.standard.removeObject(forKey: saveLineThKey)
        UserDefaults.standard.removeObject(forKey: saveIntervalSecKey)
        UserDefaults.standard.removeObject(forKey: minTextLengthKey)
        UserDefaults.standard.removeObject(forKey: autoLearningEnabledKey)
        UserDefaults.standard.removeObject(forKey: autoLearningHourKey)
        UserDefaults.standard.removeObject(forKey: autoLearningMinuteKey)
        UserDefaults.standard.removeObject(forKey: importTextPathKey)
        UserDefaults.standard.removeObject(forKey: importBookmarkDataKey)
        UserDefaults.standard.removeObject(forKey: lastImportDateKey)
        UserDefaults.standard.removeObject(forKey: lastImportedFileCountKey)
        
        // @Publishedなプロパティは直接初期化
        DispatchQueue.main.async {
            self.apps = []
            self.importBookmarkData = nil // Publishedプロパティもリセット
            self.lastImportDate = nil
            self.lastImportedFileCount = -1
        }
    }
    
    /// デバッグ用：デフォルト値の検証
    /// - Returns: すべての値がデフォルト値と一致する場合はtrue
    func verifyDefaultValues() -> Bool {
        return activateAccessibility == true &&
               self.avoidApps == ["Finder", "Tuner"] && // Computed Propertyで比較 (selfを明示)
               pollingInterval == 5 &&
               saveLineTh == 10 &&
               saveIntervalSec == 5 &&
               minTextLength == 3 &&
               autoLearningEnabled == true &&
               autoLearningHour == 3 &&
               autoLearningMinute == 0 &&
               apps.isEmpty &&
               importTextPath == "" &&
               importBookmarkData == nil &&
               lastImportDate == nil &&
               lastImportedFileCount == -1
    }
}
#endif
