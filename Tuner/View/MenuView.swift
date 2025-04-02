//
//  MenuView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI

struct MenuView: View {
    @EnvironmentObject var textModel: TextModel
    @EnvironmentObject var shareData: ShareData

    var body: some View {
        //
        Toggle("Enable Read Everything", isOn: $shareData.activateAccessibility)
            .padding(.bottom)
            .onChange(of: shareData.activateAccessibility) { oldValue, newValue in
                if newValue {
                    checkAndRequestAccessibilityPermission()
                }
            }
        Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
            .padding(.bottom)
        
        Divider()

        // Open Window
        SettingsLink {
            Label("詳細...", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
        // Quit
        Button("Quit") {
            NSApplication.shared.terminate(self)
        }
    }

    private func checkAndRequestAccessibilityPermission() {
        print("Enable Accessibility")
        shareData.requestAccessibilityPermission()
    }
}

#Preview {
    MenuView()
        .environmentObject(TextModel())
        .environmentObject(ShareData())
}
