import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @State private var showStatistics = false
    @State private var statistics: String = ""

    var body: some View {
        VStack {
            Label("ContextDatabaseApp", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)
            
            // 保存のON/OFFスイッチ

            Button("統計") {
                statistics = textModel.generateStatistics()
                showStatistics = true
            }

            if showStatistics {
                VStack {
                    Text("Statistics")
                        .font(.headline)
                        .padding()
                    ScrollView {
                        Text(statistics)
                            .padding()
                    }
                    Button("Close") {
                        showStatistics = false
                    }
                    .padding()
                }
            }

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .long
        return formatter
    }
}
