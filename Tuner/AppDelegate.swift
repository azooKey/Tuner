//
//  AppDelegate.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/06/26.
//
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var textModel = TextModel()
    var isDataSaveEnabled = true
    var observer: AXObserver?
    var shareData = ShareData()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // アクセシビリティの権限を確認するためのオプションを設定
        let trustedCheckOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options = [trustedCheckOptionPrompt: true] as CFDictionary

        // アクセシビリティの権限が許可されているか確認
        if AXIsProcessTrustedWithOptions(options) {
            // アクティブなアプリケーションが変更されたときの通知を登録
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeAppDidChange(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        } else {
            print("Accessibility permissions are not granted.")
        }
    }

    // アクティブなアプリケーションが変更されたときに呼び出されるメソッド
    @objc func activeAppDidChange(_ notification: Notification) {
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

    // アクティブなアプリケーションのAXUIElementオブジェクトを取得するメソッド
    private func getActiveApplicationAXUIElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    // 指定されたAXUIElementからテキスト要素を取得するメソッド
    private func fetchTextElements(from element: AXUIElement, appName: String) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if result == .success, let children = value as? [AXUIElement] {
            for child in children {
                extractTextFromElement(child, appName: appName)
            }
        }
    }

    // AXUIElementからテキストを抽出するメソッド
    private func extractTextFromElement(_ element: AXUIElement, appName: String) {
        let role = self.getRole(of: element)
        switch self.getRole(of: element) {
        case nil:
            // Roleは常に存在する（kAXRoleAttributeのドキュメントを参照）
            return
        case "AXButton", "AXPopUpButton", "AXRadioButton", "AXCheckBox":
            // ボタンのようなUI情報は不要
            return
        case "AXTextField", "AXTextArea":
            // 編集中のテキストを取ってしまうと無意味にテキストが増える
            return
        case "AXToolbar":
            // ツールバーにアクセスする必要はない
            return
        case "AXMenu", "AXMenuItem", "AXMenuBarItem", "AXMenuBar":
            // メニューバーにアクセスする必要はない
            return
        case "AXValueIndicator":
            // よくわからないが多分不要
            return
        case "AXText", "AXStaticText", "AXLink":
            // 明らかに進めるべき
            break
        default:
            // それ以外の場合はこのまま進める
            break
        }

        var value: AnyObject?
        // FIXME: Error: Thread 1: EXC_BAD_ACCESS (code=2, address=0x16f563f40)
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        if result == .success, let text = value as? String {
            if text != "" {
                DispatchQueue.main.async {
                    self.textModel.addText(text, appName: appName, saveLineTh: self.shareData.saveLineTh, saveIntervalSec: self.shareData.saveIntervalSec, avoidApps: self.shareData.avoidApps, minTextLength: self.shareData.minTextLength)
                }
            }
        }

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
        var roleValue: AnyObject?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        if roleResult == .success, let role = roleValue as? String {
            return role
        } else {
            return nil
        }
    }

    // アプリケーションの監視を開始するメソッド
    private func startMonitoringApp(_ app: AXUIElement, appName: String) {
        print("Start monitoring app: \(String(describing: getAppNameFromAXUIElement(app)))")
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            return
        }

        var newObserver: AXObserver?
        let error = AXObserverCreate(activeApp.processIdentifier, AppDelegate.axObserverCallback, &newObserver)

        if error != .success {
            print("Failed to create observer: \(error)")
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
                currentElement = (newParentElement as! AXUIElement)
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
}
