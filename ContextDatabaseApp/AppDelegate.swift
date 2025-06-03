import Cocoa
import SwiftUI
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    var lastExecutionDate: Date?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupPopover()
        setupNotifications()
        setupTimer()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Context Database")
            button.action = #selector(togglePopover)
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
    }
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("通知の許可が得られました")
            }
        }
    }
    
    private func setupTimer() {
        // 毎日午前0時に実行
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = 0
        components.minute = 0
        
        if let nextDate = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) {
            let timeInterval = nextDate.timeIntervalSince(Date())
            timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                self?.executeDailyTask()
                self?.setupTimer() // 次の実行をスケジュール
            }
        }
    }
    
    private func executeDailyTask() {
        // original_marisaの実行
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "cd \(FileManager.default.currentDirectoryPath) && ./original_marisa"]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                sendNotification(title: "実行完了", body: "original_marisaの実行が完了しました")
            } else {
                sendNotification(title: "実行エラー", body: "original_marisaの実行中にエラーが発生しました")
            }
        } catch {
            sendNotification(title: "実行エラー", body: "original_marisaの実行中にエラーが発生しました: \(error.localizedDescription)")
        }
        
        lastExecutionDate = Date()
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
} 