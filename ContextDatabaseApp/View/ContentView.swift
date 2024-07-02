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

            Divider()

            HStack{
                Text("Statistics")
                    .font(.headline)
                    .padding()
                Button(action: {
                    updateStatistics()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PlainButtonStyle())
            }
            Text(stats)
            PieChartView(data: appNameCounts, total: totalTextLength)
                .frame(maxWidth: 300, minHeight: 200)

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
