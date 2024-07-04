//
//  ShareData.swift
//  ContextDatabaseApp
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

    private let avoidAppsKey = "avoidApps"
    private let saveLineThKey = "saveLineTh"
    private let saveIntervalSecKey = "saveIntervalSec"
    private let minTextLengthKey = "minTextLength"

    init() {
        loadAvoidApps()
        loadSaveLineTh()
        loadSaveIntervalSec()
        loadMinTextLength()
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
}
