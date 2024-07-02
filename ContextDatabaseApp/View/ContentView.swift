import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @State private var appNameCounts: [String: Int] = [:]
    @State private var totalEntries: Int = 0
    @State private var totalTextLength: Int = 0
    @State private var averageTextLength: Int = 0
    @State private var stats: String = ""

    var body: some View {
        VStack {
            Label("ContextDatabaseApp", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)

            // 保存のON/OFFスイッチ
            Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
                .padding(.bottom)

            Button("Update Statics") {
                updateStatistics()
            }

            Text("Statistics")
                .font(.headline)
                .padding()

            BarChartView(data: appNameCounts)

            ScrollView {
                VStack(alignment: .leading) {
                    Text("Total Text Entries: \(totalEntries)")
                    Text("Total Text Length: \(totalTextLength) characters")
                    Text("Average Text Length: \(averageTextLength) characters")
                }
                .padding()
            }

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
        .onAppear() {
            updateStatistics()
        }
    }

    private func updateStatistics() {
        let (counts, entries, length, stats) = textModel.generateStatisticsParameter()
        self.appNameCounts = counts
        self.totalEntries = entries
        self.totalTextLength = length
        self.stats = stats
        self.averageTextLength = entries > 0 ? length / entries : 0
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .long
        return formatter
    }
}

struct BarChartView: View {
    var data: [String: Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 15) {
            ForEach(data.sorted(by: >), id: \.key) { appName, count in
                VStack {
                    Text("\(count)")
                        .font(.caption)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 20, height: CGFloat(count * 10))
                    Text(appName)
                        .font(.caption)
                        .rotationEffect(.degrees(-45))
                        .frame(width: 40, height: 20)
                }
            }
        }
    }
}
