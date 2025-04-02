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
    @Published var activateAccessibility: Bool = true
    
    /// テキスト取得を除外するアプリケーション名のリスト
    @Published var avoidApps: [String] = ["Finder", "ContextDatabaseApp"]
    
    /// テキスト取得のポーリング間隔（秒）
    @Published var pollingInterval: Int = 5
    
    /// 一度にファイルに保存するテキストエントリ数の閾値
    @Published var saveLineTh: Int = 10
    
    /// ファイルへの保存間隔の閾値（秒）
    @Published var saveIntervalSec: Int = 5
    
    /// 保存するテキストの最小文字数
    @Published var minTextLength: Int = 3
    
    /// 現在実行中のアプリケーションのリスト
    @Published var apps: [String] = []

    // UserDefaultsのキー定義
    private let avoidAppsKey = "avoidApps"
    private let saveLineThKey = "saveLineTh"
    private let saveIntervalSecKey = "saveIntervalSec"
    private let minTextLengthKey = "minTextLength"
    private let pollingIntervalKey = "pollingInterval"
    private let activateAccessibilityKey = "activateAccessibility"

    /// 初期化時に保存された設定を読み込む
    init() {
        loadActivateAccessibility()
        loadAvoidApps()
        loadSaveLineTh()
        loadSaveIntervalSec()
        loadMinTextLength()
        loadPollingInterval()
    }

    /// アクセシビリティ設定を保存
    private func saveActivateAccessibility() {
        UserDefaults.standard.set(activateAccessibility, forKey: activateAccessibilityKey)
    }

    /// アクセシビリティ設定を読み込む
    private func loadActivateAccessibility() {
        if let savedValue = UserDefaults.standard.value(forKey: activateAccessibilityKey) as? Bool {
            activateAccessibility = savedValue
        }
    }

    /// 除外アプリリストを保存
    private func saveAvoidApps() {
        UserDefaults.standard.set(avoidApps, forKey: avoidAppsKey)
    }

    /// 除外アプリリストを読み込む
    private func loadAvoidApps() {
        if let savedAvoidApps = UserDefaults.standard.array(forKey: avoidAppsKey) as? [String] {
            avoidApps = savedAvoidApps
        }
    }

    /// 保存行数閾値を保存
    private func saveSaveLineTh() {
        UserDefaults.standard.set(saveLineTh, forKey: saveLineThKey)
    }

    /// 保存行数閾値を読み込む
    private func loadSaveLineTh() {
        if let savedSaveLineTh = UserDefaults.standard.value(forKey: saveLineThKey) as? Int {
            saveLineTh = savedSaveLineTh
        }
    }

    /// 保存間隔を保存
    private func saveSaveIntervalSec() {
        UserDefaults.standard.set(saveIntervalSec, forKey: saveIntervalSecKey)
    }

    /// 保存間隔を読み込む
    private func loadSaveIntervalSec() {
        if let savedSaveIntervalSec = UserDefaults.standard.value(forKey: saveIntervalSecKey) as? Int {
            saveIntervalSec = savedSaveIntervalSec
        }
    }

    /// 最小テキスト長を保存
    private func saveMinTextLength() {
        UserDefaults.standard.set(minTextLength, forKey: minTextLengthKey)
    }

    /// 最小テキスト長を読み込む
    private func loadMinTextLength() {
        if let savedMinTextLength = UserDefaults.standard.value(forKey: minTextLengthKey) as? Int {
            minTextLength = savedMinTextLength
        }
    }

    /// ポーリング間隔を保存
    private func savePollingInterval() {
        UserDefaults.standard.set(pollingInterval, forKey: pollingIntervalKey)
    }

    /// ポーリング間隔を読み込む
    private func loadPollingInterval() {
        if let savedPollingInterval = UserDefaults.standard.value(forKey: pollingIntervalKey) as? Int {
            pollingInterval = savedPollingInterval
        }
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
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .sorted()
        
        DispatchQueue.main.async {
            self.apps = apps
        }
    }

    /// アプリケーションの除外設定を切り替え
    /// - Parameters:
    ///   - appName: 対象のアプリケーション名
    func toggleAppExclusion(_ appName: String) {
        if avoidApps.contains(appName) {
            avoidApps.removeAll { $0 == appName }
        } else {
            avoidApps.append(appName)
        }
        saveAvoidApps()
    }

    /// アプリケーションが除外されているかどうかを確認
    /// - Parameters:
    ///   - appName: 対象のアプリケーション名
    /// - Returns: 除外されている場合はtrue
    func isAppExcluded(_ appName: String) -> Bool {
        return avoidApps.contains(appName)
    }
}

#if DEBUG
extension ShareData {
    /// デバッグ用：設定をデフォルト値にリセット
    func resetToDefaults() {
        activateAccessibility = true
        avoidApps = ["Finder", "ContextDatabaseApp"]
        pollingInterval = 5
        saveLineTh = 10
        saveIntervalSec = 5
        minTextLength = 3
        apps = []
        
        // UserDefaultsもリセット
        UserDefaults.standard.removeObject(forKey: activateAccessibilityKey)
        UserDefaults.standard.removeObject(forKey: avoidAppsKey)
        UserDefaults.standard.removeObject(forKey: pollingIntervalKey)
        UserDefaults.standard.removeObject(forKey: saveLineThKey)
        UserDefaults.standard.removeObject(forKey: saveIntervalSecKey)
        UserDefaults.standard.removeObject(forKey: minTextLengthKey)
    }
    
    /// デバッグ用：デフォルト値の検証
    /// - Returns: すべての値がデフォルト値と一致する場合はtrue
    func verifyDefaultValues() -> Bool {
        return activateAccessibility == true &&
               avoidApps == ["Finder", "ContextDatabaseApp"] &&
               pollingInterval == 5 &&
               saveLineTh == 10 &&
               saveIntervalSec == 5 &&
               minTextLength == 3 &&
               apps.isEmpty
    }
}
#endif
