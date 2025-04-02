//
//  ShareData.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI
import Combine
import Foundation

// struct ShareData の定義を削除
/*
/// アプリケーション全体で共有される設定や状態を保持する構造体
struct ShareData {
    /// アクセシビリティ機能によるテキスト取得を有効にするか
    var activateAccessibility: Bool = true
    /// テキスト取得を除外するアプリケーション名のリスト
    var avoidApps: [String] = ["Finder", "ContextDatabaseApp"]
    /// テキスト取得のポーリング間隔（秒）
    var pollingInterval: Int = 5
    /// 一度にファイルに保存するテキストエントリ数の閾値
    var saveLineTh: Int = 10
    /// ファイルへの保存間隔の閾値（秒）
    var saveIntervalSec: Int = 5
    /// 保存するテキストの最小文字数
    var minTextLength: Int = 3
}
*/

class ShareData: ObservableObject {
    // AppDelegateから移動したプロパティをPublishedで定義
    @Published var activateAccessibility: Bool = true
    @Published var avoidApps: [String] = ["Finder", "ContextDatabaseApp"]
    @Published var pollingInterval: Int = 5
    @Published var saveLineTh: Int = 10
    @Published var saveIntervalSec: Int = 5
    @Published var minTextLength: Int = 3
    @Published var apps: [String] = []

    // 必要に応じて既存のプロパティやメソッドはそのまま維持
    // @Published var exampleProperty: String = ""

    private let avoidAppsKey = "avoidApps"
    private let saveLineThKey = "saveLineTh"
    private let saveIntervalSecKey = "saveIntervalSec"
    private let minTextLengthKey = "minTextLength"
    private let pollingIntervalKey = "pollingInterval"
    private let activateAccessibilityKey = "activateAccessibility"


    init() {
        loadActivateAccessibility()
        loadAvoidApps()
        loadSaveLineTh()
        loadSaveIntervalSec()
        loadMinTextLength()
        loadPollingInterval()
    }

    private func saveActivateAccessibility() {
        UserDefaults.standard.set(activateAccessibility, forKey: activateAccessibilityKey)
    }

    private func loadActivateAccessibility() {
        if let savedValue = UserDefaults.standard.value(forKey: activateAccessibilityKey) as? Bool {
            activateAccessibility = savedValue
        }
    }

    private func saveAvoidApps() {
        UserDefaults.standard.set(avoidApps, forKey: avoidAppsKey)
    }

    private func loadAvoidApps() {
        if let savedAvoidApps = UserDefaults.standard.array(forKey: avoidAppsKey) as? [String] {
            avoidApps = savedAvoidApps
        }
    }

    private func saveSaveLineTh() {
        UserDefaults.standard.set(saveLineTh, forKey: saveLineThKey)
    }

    private func loadSaveLineTh() {
        if let savedSaveLineTh = UserDefaults.standard.value(forKey: saveLineThKey) as? Int {
            saveLineTh = savedSaveLineTh
        }
    }

    private func saveSaveIntervalSec() {
        UserDefaults.standard.set(saveIntervalSec, forKey: saveIntervalSecKey)
    }

    private func loadSaveIntervalSec() {
        if let savedSaveIntervalSec = UserDefaults.standard.value(forKey: saveIntervalSecKey) as? Int {
            saveIntervalSec = savedSaveIntervalSec
        }
    }

    private func saveMinTextLength() {
        UserDefaults.standard.set(minTextLength, forKey: minTextLengthKey)
    }

    private func loadMinTextLength() {
        if let savedMinTextLength = UserDefaults.standard.value(forKey: minTextLengthKey) as? Int {
            minTextLength = savedMinTextLength
        }
    }

    private func savePollingInterval() {
        UserDefaults.standard.set(pollingInterval, forKey: pollingIntervalKey)
    }

    private func loadPollingInterval() {
        if let savedPollingInterval = UserDefaults.standard.value(forKey: pollingIntervalKey) as? Int {
            pollingInterval = savedPollingInterval
        }
    }

    func requestAccessibilityPermission() {
        print("requestAccessibilityPermission")
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // 現在実行中のアプリケーションを取得するメソッド
    func updateRunningApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular } // 通常のアプリケーションのみをフィルタリング
            .compactMap { $0.localizedName } // アプリケーション名を取得
            .sorted() // アルファベット順にソート
        
        DispatchQueue.main.async {
            self.apps = apps
        }
    }

    // アプリケーションの除外設定を更新
    func toggleAppExclusion(_ appName: String) {
        if avoidApps.contains(appName) {
            avoidApps.removeAll { $0 == appName }
        } else {
            avoidApps.append(appName)
        }
        saveAvoidApps()
    }

    // アプリケーションが除外されているかどうかを確認
    func isAppExcluded(_ appName: String) -> Bool {
        return avoidApps.contains(appName)
    }
}

#if DEBUG
extension ShareData {
    // テスト用のヘルパーメソッド
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
    
    // テスト用の検証メソッド
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
