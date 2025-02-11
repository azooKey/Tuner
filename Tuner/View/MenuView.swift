//
//  MenuView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI

struct MenuView: View {
    @EnvironmentObject var textModel: TextModel

    var body: some View {
        //
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
