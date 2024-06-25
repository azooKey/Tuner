//
//  ContentView.swift
//  ContextDatabaseApp
//
//  Created by 高橋直希 on 2024/06/26.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(textModel.texts, id: \.self) { text in
                    Text(text)
                        .padding()
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }
}


class TextModel: ObservableObject {
    @Published var texts: [String] = [] {
        didSet {
            saveToUserDefaults()
        }
    }

    init() {
        loadFromUserDefaults()
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(texts, forKey: "savedTexts")
    }

    private func loadFromUserDefaults() {
        if let savedTexts = UserDefaults.standard.stringArray(forKey: "savedTexts") {
            texts = savedTexts
        }
    }
}
