//
//  ContextDatabaseAppApp.swift
//  ContextDatabaseApp
//
//  Created by 高橋直希 on 2024/06/26.
//

import SwiftUI
import Cocoa

@main
struct ContextDatabaseAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.textModel)
        }
    }
}
