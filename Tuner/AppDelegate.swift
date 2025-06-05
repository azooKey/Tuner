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
    var shareData = ShareData()
    var textModel: TextModel
    var isDataSaveEnabled = true
    var observer: AXObserver?
    var pollingTimer: Timer?
    // 定期的な浄化処理用タイマー
    var purifyTimer: Timer?
    // 最後に浄化処理を実行した時刻
    var lastPurifyTime: Date?
    // 浄化処理の実行間隔（秒）例: 1時間ごと
    let purifyInterval: TimeInterval = 3600
    
    override init() {
        // TextModelの初期化をsuperの前に行う
        textModel = TextModel(shareData: shareData)
        super.init()
    }

    /// アプリケーション起動時の初期化処理
    /// - アクセシビリティ権限の確認
    /// - アプリケーション切り替えの監視設定
    /// - テキスト取得用のポーリングタイマー開始
    /// - 定期的な浄化処理タイマー開始
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 重い初期化処理を非同期で実行してメインスレッドをブロックしないようにする
        DispatchQueue.global(qos: .userInitiated).async {
            // アクセシビリティ権限を確認（初回起動時のみ）
            DispatchQueue.main.async {
                self.checkAndRequestAccessibilityPermission()
            }
            
            // アプリケーション切り替えの監視を設定
            if self.shareData.activateAccessibility {
                DispatchQueue.main.async {
                    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.activeAppDidChange(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
                }
                
                // 最初のアプリ情報を取得
                if let frontApp = NSWorkspace.shared.frontmostApplication {
                    let frontAppName = self.getAppName(for: frontApp) ?? "Unknown"
                    os_log("初期アプリケーション: %@", log: OSLog.default, type: .debug, frontAppName)
                    
                    if !self.shareData.avoidApps.contains(frontAppName), self.hasAccessibilityPermission() {
                        if let axApp = self.getActiveApplicationAXUIElement() {
                            self.fetchTextElements(from: axApp, appName: frontAppName)
                            DispatchQueue.main.async {
                                self.startMonitoringApp(axApp, appName: frontAppName)
                            }
                        }
                    }
                }
                
                // テキスト取得用のポーリングタイマーを開始
                DispatchQueue.main.async {
                    self.startTextPollingTimer()
                }

                // 定期的な浄化処理タイマーを開始
                DispatchQueue.main.async {
                    self.startPurifyTimer()
                    self.lastPurifyTime = Date() // 開始時刻を記録
                }
            }
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
        // 権限チェックを非同期で実行
        Task.detached(priority: .userInitiated) {
            let hasPermission = await Task.detached {
                return self.hasAccessibilityPermission()
            }.value
            
            if !hasPermission {
                // アラート表示をメインスレッドで実行
                await MainActor.run {
                    self.showAccessibilityPermissionAlert()
                }
            }
        }
    }
    
    /// アクセシビリティ権限要求のアラートを表示
    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "アクセシビリティ権限が必要です"
        alert.informativeText = "このアプリケーションは画面上のテキストを取得するためにアクセシビリティ権限が必要です。続行するには「OK」を押して、次の画面で「アクセシビリティ」のチェックボックスをオンにしてください。\n\n一度許可すると、アプリを再起動しても再度許可する必要はありません。"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        
        // アラートを非同期で表示（メインスレッドをブロックしない）
        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // システムの権限ダイアログを表示
                    Task.detached(priority: .userInitiated) {
                        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
                        AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                }
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
        
        // UI要素やツールバー要素を除外
        if shouldSkipElement(role: role, element: element) {
            return
        }
        
        // コンテンツ重視の属性のみに限定（UI要素の属性を除外）
        let contentAttributes = [
            kAXValueAttribute as CFString,
            kAXSelectedTextAttribute as CFString
        ]
        
        // role別の属性許可リスト
        let roleSpecificAttributes: [CFString]
        switch role {
        case "AXTextField", "AXTextArea", "AXStaticText":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXSelectedTextAttribute as CFString]
        case "AXLink":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXTitleAttribute as CFString]
        case "AXWebArea", "AXScrollArea":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXSelectedTextAttribute as CFString]
        default:
            roleSpecificAttributes = [kAXValueAttribute as CFString]
        }
        
        let textAttributes = Array(Set(contentAttributes + roleSpecificAttributes))
        
        // グループ要素の場合は子要素を優先的に処理
        if role == "AXGroup" {
            var childValue: AnyObject?
            let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childValue)
            if childResult == .success, let children = childValue as? [AXUIElement] {
                for child in children {
                    extractTextFromElement(child, appName: appName)
                }
            }
            return
        }
        
        // リンク要素の場合は特別な処理
        if role == "AXLink" {
            var linkText: AnyObject?
            let linkResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &linkText)
            if linkResult == .success, let text = linkText as? String, !text.isEmpty {
                // print("🔗 リンクテキストを取得: [\(appName)] \(text)") // os_logに戻す
                os_log("リンクテキスト [アプリ: %@] [%@] %@", 
                       log: OSLog.default, 
                       type: .debug, 
                       appName, 
                       role ?? "Unknown", 
                       text)
                if self.isQualityContent(text: text, role: role) {
                    print("📝 [AccessibilityAPI] 品質リンクテキスト取得: [\(appName)] [\(role ?? "Unknown")]")
                    print("   📄 リンクテキスト内容: \"\(text)\"")
                    DispatchQueue.main.async {
                        self.textModel.addText(text, appName: appName,
                                               avoidApps: self.shareData.avoidApps,
                                               minTextLength: self.shareData.minTextLength)
                    }
                }
            }
        }
        
        // 複数の属性からテキスト取得を試みる
        for attribute in textAttributes {
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            if result == .success {
                if let text = value as? String {
                    // print("📝 テキストを取得: ...") // os_logに戻す
                    os_log("取得テキスト [アプリ: %@] [%@] [%@] %@", 
                           log: OSLog.default, 
                           type: .debug, 
                           appName, 
                           role ?? "Unknown", 
                           String(describing: attribute), 
                           text)
                    if self.isQualityContent(text: text, role: role) {
                        print("📝 [AccessibilityAPI] 品質テキスト取得: [\(appName)] [\(role ?? "Unknown")]")
                        print("   📄 テキスト内容: \"\(text)\"")
                        DispatchQueue.main.async {
                            self.textModel.addText(text, appName: appName,
                                                   avoidApps: self.shareData.avoidApps,
                                                   minTextLength: self.shareData.minTextLength)
                        }
                    }
                } else if let array = value as? [String] {
                    // 配列形式のテキストも処理
                    for text in array {
                        // print("📝 配列テキストを取得: ...") // os_logに戻す
                        os_log("取得テキスト [アプリ: %@] [%@] [%@] %@", 
                               log: OSLog.default, 
                               type: .debug, 
                               appName, 
                               role ?? "Unknown", 
                               String(describing: attribute), 
                               text)
                        if self.isQualityContent(text: text, role: role) {
                            print("📝 [AccessibilityAPI] 品質配列テキスト取得: [\(appName)] [\(role ?? "Unknown")]")
                            print("   📄 配列テキスト内容: \"\(text)\"")
                            DispatchQueue.main.async {
                                self.textModel.addText(text, appName: appName,
                                                       avoidApps: self.shareData.avoidApps,
                                                       minTextLength: self.shareData.minTextLength)
                            }
                        }
                    }
                }
            }
        }

        // 子要素の探索を改善
        var childValue: AnyObject?
        let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childValue)
        if childResult == .success, let children = childValue as? [AXUIElement] {
            for child in children {
                // 再帰的にテキストを取得
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
    
    /// UI要素をスキップするかどうかを判定
    /// - Parameters:
    ///   - role: 要素のrole
    ///   - element: AXUIElement
    /// - Returns: スキップする場合はtrue
    private func shouldSkipElement(role: String?, element: AXUIElement) -> Bool {
        guard let role = role else { return true }
        
        // 除外するroleのリスト（ツールバーのみ）
        let excludedRoles = [
            "AXToolbar"
        ]
        
        if excludedRoles.contains(role) {
            return true
        }
        
        // より詳細な判定：特定の属性を持つ要素を除外
        if let subrole = getSubrole(of: element) {
            let excludedSubroles = [
                "AXToolbarButton",
                "AXNavigationBar", 
                "AXSecureTextField"
            ]
            
            if excludedSubroles.contains(subrole) {
                return true
            }
        }
        
        // タイトルでフィルタリング（UI要素の一般的なタイトルを除外）
        if let title = getTitle(of: element) {
            let excludedTitles = [
                "Close",
                "閉じる", 
                "Minimize",
                "最小化",
                "Zoom",
                "拡大/縮小",
                "File",
                "ファイル",
                "Edit", 
                "編集",
                "View",
                "表示",
                "Window",
                "ウィンドウ",
                "Help",
                "ヘルプ",
                "Toolbar",
                "ツールバー",
                "Back",
                "戻る",
                "Forward", 
                "進む",
                "Reload",
                "再読み込み",
                "Home",
                "ホーム",
                "Bookmarks",
                "ブックマーク",
                "History",
                "履歴",
                "Downloads",
                "ダウンロード",
                "Settings",
                "設定",
                "Preferences",
                "環境設定"
            ]
            
            if excludedTitles.contains(title) {
                return true
            }
            
            // 短すぎるタイトル（ボタンなど）を除外
            if title.count <= 2 {
                return true
            }
        }
        
        return false
    }
    
    /// AXUIElementのsubroleを取得
    private func getSubrole(of element: AXUIElement) -> String? {
        var subroleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        if result == .success, let subrole = subroleValue as? String {
            return subrole
        }
        return nil
    }
    
    /// AXUIElementのtitleを取得
    private func getTitle(of element: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        if result == .success, let title = titleValue as? String {
            return title
        }
        return nil
    }
    
    /// テキストの品質をチェック（コンテンツとして有用かどうか）
    /// - Parameters:
    ///   - text: チェックするテキスト
    ///   - role: 要素のrole
    /// - Returns: 品質が高い場合はtrue
    private func isQualityContent(text: String, role: String?) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空や短すぎるテキストを除外
        guard !trimmedText.isEmpty, trimmedText.count >= 3 else {
            return false
        }
        
        // 単一文字の繰り返しを除外
        let uniqueChars = Set(trimmedText)
        if uniqueChars.count == 1 {
            return false
        }
        
        // よくあるUI文字列を除外
        let commonUIStrings = [
            "OK", "Cancel", "Yes", "No", "Apply", "Reset", "Save", "Delete", "Copy", "Paste",
            "Cut", "Undo", "Redo", "Select All", "Print", "Share", "Export", "Import",
            "はい", "いいえ", "キャンセル", "適用", "リセット", "保存", "削除", "コピー", "貼り付け",
            "切り取り", "元に戻す", "やり直し", "すべて選択", "印刷", "共有", "書き出し", "読み込み",
            "Loading...", "読み込み中...", "Please wait...", "お待ちください...",
            "Error", "エラー", "Warning", "警告", "Info", "情報"
        ]
        
        if commonUIStrings.contains(trimmedText) {
            return false
        }
        
        // URLっぽい文字列を除外（ただしリンクテキストは除く）
        if role != "AXLink" && (trimmedText.hasPrefix("http") || trimmedText.hasPrefix("www.") || trimmedText.contains("://")) {
            return false
        }
        
        // ファイルパスっぽい文字列を除外
        if trimmedText.hasPrefix("/") || trimmedText.contains("\\") || trimmedText.hasSuffix(".app") || trimmedText.hasSuffix(".exe") {
            return false
        }
        
        // 数字や記号のみの文字列を除外
        let numbersAndSymbols = CharacterSet.decimalDigits.union(.punctuationCharacters).union(.symbols)
        if trimmedText.unicodeScalars.allSatisfy({ numbersAndSymbols.contains($0) }) {
            return false
        }
        
        // 非常に長い単語（プログラムコードなど）を除外
        let words = trimmedText.components(separatedBy: .whitespacesAndNewlines)
        if words.contains(where: { $0.count > 50 }) {
            return false
        }
        
        // role別の特別なチェック
        switch role {
        case "AXTextField", "AXTextArea":
            // 入力フィールドはプレースホルダーを除外
            let placeholders = ["Search...", "検索...", "Enter text...", "テキストを入力...", "Type here...", "ここに入力..."]
            return !placeholders.contains(trimmedText)
            
        case "AXStaticText":
            // 静的テキストは実際のコンテンツを優先
            return trimmedText.count > 5 && trimmedText.contains(" ")
            
        case "AXLink":
            // リンクは短くても有効
            return trimmedText.count >= 2
            
        default:
            // その他の要素は最低限の品質チェック
            return trimmedText.count >= 5
        }
    }
}
