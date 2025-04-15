//
//  AppDelegate.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/06/26.
//
import Cocoa
import SwiftUI
import os.log

/// アプリケーションのメインのデリゲートクラス
/// - アクセシビリティ権限の管理
/// - アプリケーション切り替えの監視
/// - テキスト要素の取得と保存
/// - 定期的なデータの浄化
class AppDelegate: NSObject, NSApplicationDelegate {
    var textModel = TextModel()
    var isDataSaveEnabled = true
    var observer: AXObserver?
    var shareData = ShareData()
    var pollingTimer: Timer?
    // 定期的な浄化処理用タイマー
    var purifyTimer: Timer?
    // 最後に浄化処理を実行した時刻
    var lastPurifyTime: Date?
    // 浄化処理の実行間隔（秒）例: 1時間ごと
    let purifyInterval: TimeInterval = 3600

    /// アプリケーション起動時の初期化処理
    /// - アクセシビリティ権限の確認
    /// - アプリケーション切り替えの監視設定
    /// - テキスト取得用のポーリングタイマー開始
    /// - 定期的な浄化処理タイマー開始
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // アクセシビリティ権限を確認（初回起動時のみ）
        checkAndRequestAccessibilityPermission()
        
        // アプリケーション切り替えの監視を設定
        if shareData.activateAccessibility {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeAppDidChange(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
            
            // 最初のアプリ情報を取得
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let frontAppName = getAppName(for: frontApp) ?? "Unknown"
                os_log("初期アプリケーション: %@", log: OSLog.default, type: .debug, frontAppName)
                
                if !shareData.avoidApps.contains(frontAppName), hasAccessibilityPermission() {
                    if let axApp = getActiveApplicationAXUIElement() {
                        fetchTextElements(from: axApp, appName: frontAppName)
                        startMonitoringApp(axApp, appName: frontAppName)
                    }
                }
            }
            
            // テキスト取得用のポーリングタイマーを開始
            startTextPollingTimer()

            // 定期的な浄化処理タイマーを開始
            startPurifyTimer()
            lastPurifyTime = Date() // 開始時刻を記録
        }
    }

    /// アプリケーション終了時のクリーンアップ処理
    /// - ポーリングタイマーの停止
    /// - 浄化タイマーの停止
    /// - 最終的なデータ浄化の実行
    func applicationWillTerminate(_ aNotification: Notification) {
        // ポーリングタイマーを停止
        stopTextPollingTimer()
        // 浄化タイマーを停止
        purifyTimer?.invalidate()
        purifyTimer = nil
        
        // アプリ終了前に最後の浄化処理を実行
        print("Running final purify before termination...")
        textModel.purifyFile(avoidApps: shareData.avoidApps, minTextLength: shareData.minTextLength) {
             print("Final purify completed.")
             // 必要であれば、ここでアプリ終了を待つ処理を追加
         }
         // 非同期処理の完了を待つ必要があるかもしれないが、一旦待たない実装とする
    }

    /// テキスト取得用のポーリングタイマーを開始
    /// - 既存のタイマーを停止
    /// - 設定された間隔で新しいタイマーを開始
    private func startTextPollingTimer() {
        // 既存のタイマーがあれば停止
        stopTextPollingTimer()
        
        // ポーリング間隔が0の場合はポーリングを開始しない
        guard shareData.pollingInterval > 0 else {
            return
        }
        
        // 設定された間隔でポーリングタイマーを開始
        pollingTimer = Timer.scheduledTimer(timeInterval: TimeInterval(shareData.pollingInterval), target: self, selector: #selector(pollActiveAppForText), userInfo: nil, repeats: true)
    }
    
    /// テキスト取得用のポーリングタイマーを停止
    private func stopTextPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    /// 定期的な浄化処理タイマーを開始
    /// - 既存のタイマーを停止
    /// - 設定された間隔で新しいタイマーを開始
    private func startPurifyTimer() {
        // 既存のタイマーがあれば停止
        purifyTimer?.invalidate()
        
        // 設定された間隔でタイマーを開始
        purifyTimer = Timer.scheduledTimer(timeInterval: purifyInterval, target: self, selector: #selector(runPeriodicPurify), userInfo: nil, repeats: true)
        print("Purify timer started with interval: \(purifyInterval) seconds")
    }

    /// 定期的な浄化処理を実行
    /// - テキストモデルの浄化処理を呼び出し
    /// - 実行時刻を更新
    @objc private func runPeriodicPurify() {
        print("Running periodic purify...")
        textModel.purifyFile(avoidApps: shareData.avoidApps, minTextLength: shareData.minTextLength) {
            print("Periodic purify completed.")
        }
        lastPurifyTime = Date() // 実行時刻を更新
    }

    /// アクティブアプリケーションからテキストを定期的に取得
    /// - アクセシビリティ権限の確認
    /// - 除外アプリのチェック
    /// - テキスト要素の取得
    @objc private func pollActiveAppForText() {
        // インポートフォルダ選択パネル表示中はポーリングをスキップ
        guard !shareData.isImportPanelShowing else {
            os_log("インポートパネル表示中のためポーリングをスキップ", log: OSLog.default, type: .debug)
            return
        }

        guard shareData.activateAccessibility, hasAccessibilityPermission() else {
            return
        }
        
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            let activeApplicationName = getAppName(for: activeApp) ?? "Unknown"
            if shareData.avoidApps.contains(activeApplicationName) {
                return
            }
            
            if let axApp = getActiveApplicationAXUIElement() {
                os_log("ポーリング実行: %@", log: OSLog.default, type: .debug, activeApplicationName)
                fetchTextElements(from: axApp, appName: activeApplicationName)
                // ポーリング時の浄化処理呼び出しは削除（専用タイマーで行うため）
            }
        }
    }

    /// アクセシビリティ権限をチェックし、必要に応じて要求
    /// - 権限がない場合は説明付きのアラートを表示
    /// - ユーザーが許可した場合はシステムの権限ダイアログを表示
    private func checkAndRequestAccessibilityPermission() {
        if !hasAccessibilityPermission() {
            // 権限がない場合は説明付きのアラートを表示
            let alert = NSAlert()
            alert.messageText = "アクセシビリティ権限が必要です"
            alert.informativeText = "このアプリケーションは画面上のテキストを取得するためにアクセシビリティ権限が必要です。続行するには「OK」を押して、次の画面で「アクセシビリティ」のチェックボックスをオンにしてください。\n\n一度許可すると、アプリを再起動しても再度許可する必要はありません。"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "キャンセル")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // OKが押された場合、システムの権限ダイアログを表示
                let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
                AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
        }
    }
    
    /// アクセシビリティ権限の有無をチェック
    /// - Returns: 権限がある場合はtrue
    private func hasAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// アクティブアプリケーションが変更されたときの処理
    /// - アクセシビリティ権限の確認
    /// - 除外アプリのチェック
    /// - テキスト要素の取得と監視開始
    @objc func activeAppDidChange(_ notification: Notification) {
        // インポートフォルダ選択パネル表示中は処理をスキップ
        guard !shareData.isImportPanelShowing else {
            os_log("インポートパネル表示中のため activeAppDidChange をスキップ", log: OSLog.default, type: .debug)
            return
        }

        guard shareData.activateAccessibility else {
            return
        }
        
        // 権限チェック（プロンプトは表示しない）
        if !hasAccessibilityPermission() {
            os_log("アクセシビリティ権限がありません", log: OSLog.default, type: .error)
            return
        }

        if let activeApp = NSWorkspace.shared.frontmostApplication {
            let activeApplicationName = getAppName(for: activeApp) ?? "Unknown"
            if shareData.avoidApps.contains(activeApplicationName) {
                return
            }
            if let axApp = getActiveApplicationAXUIElement() {
                fetchTextElements(from: axApp, appName: activeApplicationName)
                startMonitoringApp(axApp, appName: activeApplicationName)
            }
        }
    }

    /// アクティブアプリケーションのAXUIElementを取得
    /// - Returns: AXUIElementオブジェクト、取得できない場合はnil
    private func getActiveApplicationAXUIElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    /// 指定されたAXUIElementからテキスト要素を取得
    /// - Parameters:
    ///   - element: 対象のAXUIElement
    ///   - appName: アプリケーション名
    private func fetchTextElements(from element: AXUIElement, appName: String) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if result == .success, let children = value as? [AXUIElement] {
            for child in children {
                extractTextFromElement(child, appName: appName)
            }
        }
    }

    /// AXUIElementからテキストを抽出
    /// - Parameters:
    ///   - element: 対象のAXUIElement
    ///   - appName: アプリケーション名
    private func extractTextFromElement(_ element: AXUIElement, appName: String) {
        let role = self.getRole(of: element)
        
        // 不要な要素は最小限だけ除外する
        switch role {
        case nil:
            // Roleは常に存在する（kAXRoleAttributeのドキュメントを参照）
            return
        case "AXMenu", "AXMenuBar":
            // メニューバーは除外（フォーカスがないとき）
            return
        default:
            // それ以外の要素は処理を続行
            break
        }

        // テキスト取得を試みる属性のリスト
        let textAttributes = [
            kAXValueAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXPlaceholderValueAttribute as CFString,
            kAXSelectedTextAttribute as CFString
        ]
        
        // 複数の属性からテキスト取得を試みる
        for attribute in textAttributes {
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            if result == .success, let text = value as? String, !text.isEmpty {
                // 取得したテキストをデバッグログに出力
                // os_log("取得テキスト [アプリ: %@] [%@] [%@] %@", 
                //        log: OSLog.default, 
                //        type: .debug, 
                //        appName, 
                //        role ?? "Unknown", 
                //        String(describing: attribute), 
                //        text)
                DispatchQueue.main.async {
                    self.textModel.addText(text, appName: appName,
                                           // saveLineTh と saveIntervalSec のデフォルト値はTextModel側で定義されているものを使用
                                           avoidApps: self.shareData.avoidApps,
                                           minTextLength: self.shareData.minTextLength)
                }
                break  // テキストが見つかったらこの要素の他の属性は確認しない
            }
        }

        // 子要素の探索
        var childValue: AnyObject?
        let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childValue)
        if childResult == .success, let children = childValue as? [AXUIElement] {
            for child in children {
                extractTextFromElement(child, appName: appName)
            }
        }
    }

    /// AXUIElementのroleを取得するメソッド
    private func getRole(of element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        
        if roleResult == .success, let role = roleValue as? String {
            return role
        }
        
        if roleResult != .success {
            os_log("Error getting role attribute: %{public}@", log: OSLog.default, type: .error, String(describing: roleResult))
        } else {
            os_log("Failed to cast role value to String.", log: OSLog.default, type: .error)
        }
        
        return nil
    }

    // アプリケーションの監視を開始するメソッド
    private func startMonitoringApp(_ app: AXUIElement, appName: String) {
        os_log("Start monitoring app: %@", log: OSLog.default, type: .debug, String(describing: getAppNameFromAXUIElement(app)))
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            return
        }

        var newObserver: AXObserver?
        let error = AXObserverCreate(activeApp.processIdentifier, AppDelegate.axObserverCallback, &newObserver)

        if error != .success {
            os_log("Failed to create observer: %@", log: OSLog.default, type: .error, String(describing: error))
            return
        }

        if let newObserver = newObserver {
            AXObserverAddNotification(newObserver, app, kAXValueChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            AXObserverAddNotification(newObserver, app, kAXUIElementDestroyedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
            self.observer = newObserver
        }
    }

    static let axObserverCallback: AXObserverCallback = { observer, element, notificationName, userInfo in
        guard let userInfo = userInfo else { return }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
        delegate.handleAXEvent(element: element, notification: notificationName as String)
    }

    func handleAXEvent(element: AXUIElement, notification: String) {
        // インポートフォルダ選択パネル表示中は処理をスキップ
        guard !shareData.isImportPanelShowing else {
            os_log("インポートパネル表示中のため handleAXEvent をスキップ", log: OSLog.default, type: .debug)
            return
        }

        if notification == kAXValueChangedNotification as String || notification == kAXUIElementDestroyedNotification as String {
            if let appName = getAppNameFromAXUIElement(element){
                fetchTextElements(from: element, appName: appName)
            }
        }
    }

    // アプリケーションの名前を取得するメソッド
    private func getAppName(for application: NSRunningApplication) -> String? {
        return application.localizedName
    }

    // AXUIElementからアプリケーションの名前を取得するメソッド
    func getAppNameFromAXUIElement(_ element: AXUIElement) -> String? {
        var currentElement = element
        var parentElement: AXUIElement? = nil

        // ヒエラルキーの一番上の要素まで遡る
        while true {
            var newParentElement: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &newParentElement)

            if result != .success || newParentElement == nil {
                // 親要素がない場合、currentElementが一番上の要素
                parentElement = currentElement
                break
            } else {
                currentElement = newParentElement as! AXUIElement
            }
        }

        // 最上位の要素からアプリケーション名を取得
        if let appElement = parentElement {
            var appName: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &appName)

            if result == .success, let appNameString = appName as? String {
                return appNameString
            }
        }

        return nil
    }

    /// ポーリングタイマーイベント
    /// - アクセシビリティ有効、除外アプリでない、インポートパネル非表示の場合にテキスト取得を実行
    @objc func pollingTimerFired() {
        // インポートフォルダ選択パネル表示中はポーリングをスキップ
        guard !shareData.isImportPanelShowing else {
            os_log("インポートパネル表示中のためポーリングをスキップ", log: OSLog.default, type: .debug)
            return
        }

        guard shareData.activateAccessibility, shareData.pollingInterval > 0 else {
            return
        }

        if !hasAccessibilityPermission() {
            os_log("アクセシビリティ権限がありません（ポーリング）", log: OSLog.default, type: .error)
            return
        }

        if let activeApp = NSWorkspace.shared.frontmostApplication {
            let activeApplicationName = getAppName(for: activeApp) ?? "Unknown"
            if shareData.avoidApps.contains(activeApplicationName) {
                return
            }
            if let axApp = getActiveApplicationAXUIElement() {
                os_log("Polling for app: %@", log: OSLog.default, type: .debug, activeApplicationName)
                fetchTextElements(from: axApp, appName: activeApplicationName)
            }
        }
    }
}
