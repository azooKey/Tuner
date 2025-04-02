//
//  ShareData.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI
import Combine

class ShareData: ObservableObject {
    @Published var avoidApps: [String] = ["ContextHarvester"] {
        didSet {
            saveAvoidApps()
        }
    }
    @Published var apps: [String] = []
    @Published var saveLineTh: Int = 50 {
        didSet {
            saveSaveLineTh()
        }
    }
    @Published var saveIntervalSec: Int = 10 {
        didSet {
            saveSaveIntervalSec()
        }
    }
    @Published var minTextLength: Int = 0 {
        didSet {
            saveMinTextLength()
        }
    }
    // ポーリング間隔の設定（秒）
    @Published var pollingInterval: Int = 10 {
        didSet {
            savePollingInterval()
        }
    }
    // アクセシビリティAPIの利用
    @Published var activateAccessibility: Bool = false {
        didSet {
            saveActivateAccessibility()
        }
    }

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
}
