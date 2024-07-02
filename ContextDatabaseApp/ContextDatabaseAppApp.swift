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
        MenuBarExtra("ContextDatabaseApp", systemImage: "doc.text"){
            MenuView()
                .environmentObject(appDelegate.textModel)
        }
        Settings {
            ContentView()
                .environmentObject(appDelegate.textModel)
                .environmentObject(appDelegate.shareData)
                .frame(width: 400, height: 600)
        }
    }
}
