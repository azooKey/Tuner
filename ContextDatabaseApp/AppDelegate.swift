//
//  AppDelegate.swift
//  ContextDatabaseApp
//
//  Created by 高橋直希 on 2024/06/26.
//
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var textModel = TextModel()

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
            let activeApplicationName = activeApp.localizedName ?? "Unknown"
            print("Active app: \(activeApplicationName)")
            if let axApp = getActiveApplicationAXUIElement() {
                fetchTextElements(from: axApp, appName: activeApplicationName)
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
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        if result == .success, let text = value as? String {
            print("Text: \(text)")
            DispatchQueue.main.async {
                self.textModel.addText(text, appName: appName)  // 修正点: ここでaddTextメソッドを使用
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
}
