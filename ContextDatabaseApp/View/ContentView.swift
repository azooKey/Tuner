import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @State private var appNameCounts: [(key: String, value: Int)] = []
    @State private var appTexts:  [(key: String, value: Int)] = []
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
            HStack {
                PieChartView(data: appNameCounts, total: totalTextLength)
                    .frame(maxWidth: 300, minHeight: 200)
                Text(stats)
            }

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
        .onAppear {
            updateStatistics()
        }
    }

    private func updateStatistics() {
        let (counts, appText, entries, length, stats) = textModel.generateStatisticsParameter()
        self.appNameCounts = counts
        self.appTexts = appText
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

struct PieChartView: View {
    var data: [(key: String, value: Int)]
    var total: Int
    var topEntries: Int = 5

    var body: some View {
        Chart {
            let sortedData = data.sorted { $0.value > $1.value }
            let topData = sortedData.prefix(topEntries)
            let otherData = sortedData.dropFirst(topEntries)
            let otherValue = otherData.reduce(0) { $0 + $1.value }

            ForEach(topData, id: \.key) { item in
                SectorMark(
                    angle: .value("Value", item.value),
                    angularInset: 1
                    
                )
                .foregroundStyle(by: .value("Key", item.key))
                .annotation(position: .overlay, alignment: .center, spacing: 0) {
                    Text("\(item.key)\n\(item.value)")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }

            if otherValue > 0 {
                SectorMark(
                    angle: .value("Value", otherValue),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Key", "Others"))
                .annotation(position: .overlay, alignment: .center, spacing: 0) {
                    Text("Others\n\(otherValue)")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .chartLegend(.hidden)
    }
}
