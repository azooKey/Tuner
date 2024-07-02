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

        private let userDefaultsKey = "avoidApps"

        init() {
            loadAvoidApps()
        }

        private func saveAvoidApps() {
            UserDefaults.standard.set(avoidApps, forKey: userDefaultsKey)
        }

        private func loadAvoidApps() {
            if let savedAvoidApps = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String] {
                avoidApps = savedAvoidApps
            }
        }
}
