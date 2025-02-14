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
            .onChange(of: shareData.activateAccessibility) { newValue in
                shareData.activateAccessibility = newValue
                if newValue {
                    print("Enable Accessibility")
                    shareData.requestAccessibilityPermission()
                }else{
                    print("Deactivate Accessibility")
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

}

#Preview {
    MenuView()
}
