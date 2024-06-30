import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel

    var body: some View {
        VStack {
            Label("Saved Texts", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)

            // 統計ボタン
            Button("統計") {
                print("統計")
            }

            // 最後に保存した時間を表示
            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }

    // 日付フォーマットを定義
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .long
        return formatter
    }
}
