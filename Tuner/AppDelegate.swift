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
                            // AXUIElementの有効性をチェック
                            if self.isValidAXUIElement(axApp) {
                                self.fetchTextElements(from: axApp, appName: frontAppName)
                                DispatchQueue.main.async {
                                    self.startMonitoringApp(axApp, appName: frontAppName)
                                }
                            } else {
                                os_log("Invalid initial AXUIElement for app: %@", log: OSLog.default, type: .debug, frontAppName)
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
                // AXUIElementの有効性をチェック
                if isValidAXUIElement(axApp) {
                    os_log("ポーリング実行: %@", log: OSLog.default, type: .debug, activeApplicationName)
                    fetchTextElements(from: axApp, appName: activeApplicationName)
                    // ポーリング時の浄化処理呼び出しは削除（専用タイマーで行うため）
                } else {
                    os_log("Invalid AXUIElement during polling for app: %@", log: OSLog.default, type: .debug, activeApplicationName)
                }
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
                // AXUIElementの有効性をチェック
                if isValidAXUIElement(axApp) {
                    fetchTextElements(from: axApp, appName: activeApplicationName)
                    startMonitoringApp(axApp, appName: activeApplicationName)
                } else {
                    os_log("Invalid AXUIElement for app: %@", log: OSLog.default, type: .debug, activeApplicationName)
                }
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
        // 要素の有効性をチェック
        guard isValidAXUIElement(element) else {
            os_log("Invalid AXUIElement in fetchTextElements", log: OSLog.default, type: .debug)
            return
        }
        
        if let childrenValue = safeGetAttributeValue(from: element, attribute: kAXChildrenAttribute as CFString),
           let children = childrenValue as? [AXUIElement] {
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
        // 要素の有効性を事前チェック
        guard isValidAXUIElement(element) else {
            return
        }
        
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
        
        // role別の属性許可リスト（ウェブアプリケーション対応を拡張）
        let roleSpecificAttributes: [CFString]
        switch role {
        case "AXTextField", "AXTextArea", "AXStaticText":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXSelectedTextAttribute as CFString]
        case "AXLink":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXTitleAttribute as CFString, kAXDescriptionAttribute as CFString]
        case "AXWebArea", "AXScrollArea":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXSelectedTextAttribute as CFString]
        case "AXButton":
            roleSpecificAttributes = [kAXTitleAttribute as CFString, kAXValueAttribute as CFString, kAXDescriptionAttribute as CFString]
        case "AXText":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXSelectedTextAttribute as CFString]
        case "AXMessage":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXDescriptionAttribute as CFString]
        case "AXTabPanel":
            roleSpecificAttributes = [kAXTitleAttribute as CFString, kAXValueAttribute as CFString]
        case "AXList", "AXContentList":
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXDescriptionAttribute as CFString]
        case "AXGroup":
            // グループ要素は複数の属性からテキストを探す
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXTitleAttribute as CFString, kAXDescriptionAttribute as CFString, kAXSelectedTextAttribute as CFString]
        default:
            roleSpecificAttributes = [kAXValueAttribute as CFString, kAXTitleAttribute as CFString, kAXDescriptionAttribute as CFString]
        }
        
        let textAttributes = Array(Set(contentAttributes + roleSpecificAttributes))
        
        // 特定のroleに対する優先的処理
        switch role {
        case "AXGroup":
            // グループ要素は自身のテキストを取得してから子要素も処理
            extractAttributesFromElement(element, appName: appName, role: role, attributes: roleSpecificAttributes)
            if let childValue = safeGetAttributeValue(from: element, attribute: kAXChildrenAttribute as CFString),
               let children = childValue as? [AXUIElement] {
                for child in children {
                    extractTextFromElement(child, appName: appName)
                }
            }
            return
            
        case "AXMessage":
            // メッセージ要素の特別処理
            handleMessageElement(element, appName: appName, role: role)
            return
            
        case "AXTabPanel":
            // タブパネルのテキストを取得してから子要素も処理
            extractAttributesFromElement(element, appName: appName, role: role, attributes: roleSpecificAttributes)
            if let childValue = safeGetAttributeValue(from: element, attribute: kAXChildrenAttribute as CFString),
               let children = childValue as? [AXUIElement] {
                for child in children {
                    extractTextFromElement(child, appName: appName)
                }
            }
            return
            
        case "AXList", "AXContentList":
            // リスト要素は直接の値と子要素の両方を処理
            extractAttributesFromElement(element, appName: appName, role: role, attributes: roleSpecificAttributes)
            if let childValue = safeGetAttributeValue(from: element, attribute: kAXChildrenAttribute as CFString),
               let children = childValue as? [AXUIElement] {
                for child in children {
                    extractTextFromElement(child, appName: appName)
                }
            }
            return
            
        default:
            break
        }
        
        // リンク要素の場合は特別な処理
        if role == "AXLink" {
            if let linkText = safeGetAttributeValue(from: element, attribute: kAXValueAttribute as CFString),
               let text = linkText as? String, !text.isEmpty {
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
                                               minTextLength: self.shareData.minTextLength,
                                               maxTextLength: self.shareData.maxTextLength)
                    }
                }
            }
        }
        
        // 複数の属性からテキスト取得を試みる
        for attribute in textAttributes {
            guard let value = safeGetAttributeValue(from: element, attribute: attribute) else {
                continue
            }
            
            if true { // result == .success に相当
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
                                                   minTextLength: self.shareData.minTextLength,
                                                   maxTextLength: self.shareData.maxTextLength)
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
                                                       minTextLength: self.shareData.minTextLength,
                                                       maxTextLength: self.shareData.maxTextLength)
                            }
                        }
                    }
                }
            }
        }

        // 子要素の探索を安全に実行
        if let childValue = safeGetAttributeValue(from: element, attribute: kAXChildrenAttribute as CFString),
           let children = childValue as? [AXUIElement] {
            for child in children {
                // 再帰的にテキストを取得（各子要素の有効性は extractTextFromElement 内でチェック）
                extractTextFromElement(child, appName: appName)
            }
        }
    }

    /// AXUIElementのroleを取得するメソッド（安全性チェック付き）
    private func getRole(of element: AXUIElement) -> String? {
        // 要素の有効性を事前チェック
        guard isValidAXUIElement(element) else {
            return nil
        }
        
        var roleValue: CFTypeRef?
        
        // アクセス権限とバリデーションを確認
        guard hasAccessibilityPermission() else {
            return nil
        }
        
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        
        if roleResult == .success, let role = roleValue as? String {
            return role
        }
        
        // エラーログは詳細レベルを下げる（頻繁に発生する可能性があるため）
        if roleResult != .success && roleResult != .attributeUnsupported {
            os_log("Failed to get role attribute: %{public}@", log: OSLog.default, type: .debug, String(describing: roleResult))
        }
        
        return nil
    }
    
    /// AXUIElementの有効性をチェックするヘルパーメソッド
    private func isValidAXUIElement(_ element: AXUIElement) -> Bool {
        // AXUIElementが有効かどうかを確認する軽量なチェック
        var attributeNames: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &attributeNames)
        return result == .success || result == .attributeUnsupported
    }
    
    /// 安全にAXUIElementの属性値を取得するヘルパーメソッド
    private func safeGetAttributeValue(from element: AXUIElement, attribute: CFString) -> AnyObject? {
        // 要素の有効性を再確認
        guard isValidAXUIElement(element) else {
            return nil
        }
        
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        
        if result == .success {
            return value
        }
        
        // 特定のエラーのみログ出力（頻繁なエラーを避けるため）
        if result == .invalidUIElement || result == .cannotComplete {
            os_log("Accessibility element became invalid during attribute access", log: OSLog.default, type: .debug)
        }
        
        return nil
    }

    // アプリケーションの監視を開始するメソッド
    private func startMonitoringApp(_ app: AXUIElement, appName: String) {
        // 要素の有効性をチェック
        guard isValidAXUIElement(app) else {
            os_log("Invalid AXUIElement in startMonitoringApp", log: OSLog.default, type: .debug)
            return
        }
        
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
            // 通知の追加時もエラーチェック
            let valueChangeResult = AXObserverAddNotification(newObserver, app, kAXValueChangedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            let destroyResult = AXObserverAddNotification(newObserver, app, kAXUIElementDestroyedNotification as CFString, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            
            if valueChangeResult == .success && destroyResult == .success {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
                self.observer = newObserver
            } else {
                os_log("Failed to add notifications: value=%@, destroy=%@", log: OSLog.default, type: .error, String(describing: valueChangeResult), String(describing: destroyResult))
            }
        }
    }

    static let axObserverCallback: AXObserverCallback = { observer, element, notificationName, userInfo in
        guard let userInfo = userInfo else { return }
        
        // 安全にデリゲートを取得
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
        // メインスレッドで実行して安全性を確保
        DispatchQueue.main.async {
            delegate.handleAXEvent(element: element, notification: notificationName as String)
        }
    }

    func handleAXEvent(element: AXUIElement, notification: String) {
        // インポートフォルダ選択パネル表示中は処理をスキップ
        guard !shareData.isImportPanelShowing else {
            os_log("インポートパネル表示中のため handleAXEvent をスキップ", log: OSLog.default, type: .debug)
            return
        }

        // 要素の有効性をチェック
        guard isValidAXUIElement(element) else {
            os_log("Invalid AXUIElement in handleAXEvent", log: OSLog.default, type: .debug)
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
        // 要素の有効性をチェック
        guard isValidAXUIElement(element) else {
            return nil
        }
        
        var currentElement = element
        var parentElement: AXUIElement? = nil
        var iterationCount = 0
        let maxIterations = 100 // 無限ループ防止

        // ヒエラルキーの一番上の要素まで遡る
        while iterationCount < maxIterations {
            iterationCount += 1
            
            // 現在の要素の有効性をチェック
            guard isValidAXUIElement(currentElement) else {
                break
            }
            
            if let parentValue = safeGetAttributeValue(from: currentElement, attribute: kAXParentAttribute as CFString),
               CFGetTypeID(parentValue as CFTypeRef) == AXUIElementGetTypeID() {
                currentElement = parentValue as! AXUIElement
            } else {
                // 親要素がない場合、currentElementが一番上の要素
                parentElement = currentElement
                break
            }
        }

        // 最上位の要素からアプリケーション名を取得
        if let appElement = parentElement {
            if let titleValue = safeGetAttributeValue(from: appElement, attribute: kAXTitleAttribute as CFString),
               let appNameString = titleValue as? String {
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
                // AXUIElementの有効性をチェック
                if isValidAXUIElement(axApp) {
                    os_log("Polling for app: %@", log: OSLog.default, type: .debug, activeApplicationName)
                    fetchTextElements(from: axApp, appName: activeApplicationName)
                } else {
                    os_log("Invalid AXUIElement during timer polling for app: %@", log: OSLog.default, type: .debug, activeApplicationName)
                }
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
        
        // 除外するroleのリスト（最小限に抑制）
        let excludedRoles = [
            "AXToolbar",
            "AXMenuBar",
            "AXScrollBar"
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
        
        // タイトルでフィルタリング（明確なUI要素のみ除外）
        if let title = getTitle(of: element) {
            let excludedTitles = [
                "Close",
                "閉じる", 
                "Minimize",
                "最小化",
                "Zoom",
                "拡大/縮小",
                "Back",
                "戻る",
                "Forward", 
                "進む",
                "Reload",
                "再読み込み",
                "Bookmarks",
                "ブックマーク",
                "History",
                "履歴",
                "Downloads",
                "ダウンロード",
                "Preferences",
                "環境設定"
            ]
            
            if excludedTitles.contains(title) {
                return true
            }
        }
        
        return false
    }
    
    /// AXUIElementのsubroleを取得
    private func getSubrole(of element: AXUIElement) -> String? {
        guard let value = safeGetAttributeValue(from: element, attribute: kAXSubroleAttribute as CFString),
              let subrole = value as? String else {
            return nil
        }
        return subrole
    }
    
    /// AXUIElementのtitleを取得
    private func getTitle(of element: AXUIElement) -> String? {
        guard let value = safeGetAttributeValue(from: element, attribute: kAXTitleAttribute as CFString),
              let title = value as? String else {
            return nil
        }
        return title
    }
    
    /// メッセージ要素の特別処理
    private func handleMessageElement(_ element: AXUIElement, appName: String, role: String?) {
        // メッセージ要素は複数の属性からテキストを収集
        let messageAttributes = [
            kAXValueAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXTitleAttribute as CFString
        ]
        
        var collectedTexts: [String] = []
        
        // 各属性からテキストを収集
        for attribute in messageAttributes {
            if let value = safeGetAttributeValue(from: element, attribute: attribute),
               let text = value as? String,
               !text.isEmpty,
               isQualityContent(text: text, role: role) {
                collectedTexts.append(text)
            }
        }
        
        // 収集したテキストを追加
        for text in collectedTexts {
            print("📩 [AccessibilityAPI] メッセージテキスト取得: [\(appName)] [\(role ?? "Unknown")]")
            print("   📄 メッセージ内容: \"\(text)\"")
            DispatchQueue.main.async {
                self.textModel.addText(text, appName: appName,
                                       avoidApps: self.shareData.avoidApps,
                                       minTextLength: self.shareData.minTextLength,
                                       maxTextLength: self.shareData.maxTextLength)
            }
        }
        
        // 子要素も処理（メッセージ内のリンクやボタンなど）
        if let childValue = safeGetAttributeValue(from: element, attribute: kAXChildrenAttribute as CFString),
           let children = childValue as? [AXUIElement] {
            for child in children {
                extractTextFromElement(child, appName: appName)
            }
        }
    }
    
    /// 指定された属性リストから要素のテキストを抽出
    private func extractAttributesFromElement(_ element: AXUIElement, appName: String, role: String?, attributes: [CFString]) {
        for attribute in attributes {
            if let value = safeGetAttributeValue(from: element, attribute: attribute) {
                if let text = value as? String, !text.isEmpty {
                    if isQualityContent(text: text, role: role) {
                        print("📝 [AccessibilityAPI] 要素テキスト取得: [\(appName)] [\(role ?? "Unknown")] [\(String(describing: attribute))]")
                        print("   📄 テキスト内容: \"\(text)\"")
                        DispatchQueue.main.async {
                            self.textModel.addText(text, appName: appName,
                                                   avoidApps: self.shareData.avoidApps,
                                                   minTextLength: self.shareData.minTextLength,
                                                   maxTextLength: self.shareData.maxTextLength)
                        }
                    }
                } else if let array = value as? [String] {
                    // 配列形式のテキストも処理
                    for text in array {
                        if !text.isEmpty && isQualityContent(text: text, role: role) {
                            print("📝 [AccessibilityAPI] 配列テキスト取得: [\(appName)] [\(role ?? "Unknown")]")
                            print("   📄 配列テキスト内容: \"\(text)\"")
                            DispatchQueue.main.async {
                                self.textModel.addText(text, appName: appName,
                                                       avoidApps: self.shareData.avoidApps,
                                                       minTextLength: self.shareData.minTextLength,
                                                       maxTextLength: self.shareData.maxTextLength)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// テキストの品質をチェック（コンテンツとして有用かどうか）
    /// - Parameters:
    ///   - text: チェックするテキスト
    ///   - role: 要素のrole
    /// - Returns: 品質が高い場合はtrue
    internal func isQualityContent(text: String, role: String?) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 空テキストを除外
        guard !trimmedText.isEmpty else {
            return false
        }
        
        // 単一文字の繰り返しを除外（ただし2文字以下は例外）
        let uniqueChars = Set(trimmedText)
        if uniqueChars.count == 1 && trimmedText.count > 2 {
            return false
        }
        
        // よくあるUI文字列を除外（ただしメッセージや特定の役割では許可）
        let commonUIStrings = [
            "Cancel", "Apply", "Reset", "Save", "Delete", "Copy", "Paste",
            "Cut", "Undo", "Redo", "Select All", "Print", "Share", "Export", "Import",
            "キャンセル", "適用", "リセット", "保存", "削除", "コピー", "貼り付け",
            "切り取り", "元に戻す", "やり直し", "すべて選択", "印刷", "共有", "書き出し", "読み込み",
            "Loading...", "読み込み中...", "Please wait...", "お待ちください...",
            "Error", "エラー", "Warning", "警告", "Info", "情報",
            "Navigation", "ナビゲーション", "Menu", "メニュー", "Toolbar", "ツールバー",
            "Header", "ヘッダー", "Footer", "フッター", "Sidebar", "サイドバー"
        ]
        
        // メッセージやテキスト要素では短いレスポンスも有効
        if role != "AXMessage" && role != "AXText" && role != "AXGroup" && commonUIStrings.contains(trimmedText) {
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
        
        // 数字や記号のみの文字列を除外（ただし絵文字や一部の記号は除く）
        let numbersAndBasicSymbols = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?"))
        if trimmedText.unicodeScalars.allSatisfy({ numbersAndBasicSymbols.contains($0) }) {
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
            // 静的テキストは1文字から有効（ウェブアプリ対応）
            return trimmedText.count >= 1
            
        case "AXLink":
            // リンクは短くても有効
            return trimmedText.count >= 1
            
        case "AXMessage":
            // メッセージは短くても有効（Slackメッセージ）
            return trimmedText.count >= 1
            
        case "AXButton":
            // ボタンは人名や短いテキストも有効
            if trimmedText.count >= 2 {
                // ユーザー名のパターンを許可（日本語名、英語名）
                if trimmedText.contains("/") || // "Yuki Yamaguchi/Sales" のようなパターン
                   isValidNamePattern(trimmedText) { // 文字、数字、スペース、ピリオド、ハイフン、スラッシュ
                    return true
                }
            }
            return trimmedText.count >= 2
            
        case "AXText":
            // テキスト要素は1文字でも有効（絵文字や短いテキスト）
            return trimmedText.count >= 1
            
        case "AXTabPanel":
            // タブパネルのタイトルは短くても有効
            return trimmedText.count >= 1
            
        case "AXList", "AXContentList":
            // リスト要素は内容次第
            return trimmedText.count >= 1
            
        case "AXGroup":
            // グループ要素内のテキストも積極的に取得（ウェブアプリ対応）
            return trimmedText.count >= 1
            
        default:
            // その他の要素は緩い品質チェック（ウェブアプリ対応）
            return trimmedText.count >= 1
        }
    }
    
    /// ユーザー名として有効なパターンかどうかを判定
    internal func isValidNamePattern(_ text: String) -> Bool {
        // 基本的な文字、数字、および一般的な区切り文字のみを許可
        let allowedCharacterSet = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "./- "))
        
        // すべての文字が許可された文字セットに含まれているかチェック
        let textCharacterSet = CharacterSet(charactersIn: text)
        return allowedCharacterSet.isSuperset(of: textCharacterSet)
    }
}
