import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @State private var statistics: String = ""

    var body: some View {
        VStack {
            Label("ContextDatabaseApp", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)
            
            // 保存のON/OFFスイッチ
            Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
                       .padding(.bottom)

            Button("Update Statics") {
                statistics = textModel.generateStatistics()
            }

            VStack {
                Text("Statistics")
                    .font(.headline)
                    .padding()
                ScrollView {
                    Text(statistics)
                        .padding()
                }
            }

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
        .onAppear() {
            statistics = textModel.generateStatistics()
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .long
        return formatter
    }
}
