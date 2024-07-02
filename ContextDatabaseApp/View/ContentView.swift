import SwiftUI
import Charts

enum GraphStyle {
    case pie
    case bar
    case detail
}

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @State private var appNameCounts: [(key: String, value: Int)] = []
    @State private var appTexts:  [(key: String, value: Int)] = []
    @State private var totalEntries: Int = 0
    @State private var totalTextLength: Int = 0
    @State private var averageTextLength: Int = 0
    @State private var stats: String = ""
    @State private var selectedGraphStyle: GraphStyle = .pie

    var body: some View {
        VStack {
            Label("ContextDatabaseApp", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)

            // 保存のON/OFFスイッチ
            Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
                .padding(.bottom)

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }

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
            if selectedGraphStyle == .bar {
                BarChartView(data: appTexts, total: totalTextLength)
                    .frame(maxWidth: 300, minHeight: 200)
            } else if selectedGraphStyle == .pie {
                PieChartView(data: appTexts, total: totalTextLength)
                    .frame(maxWidth: 300, minHeight: 200)
            } else if selectedGraphStyle == .detail {
                DetailView(data: appTexts)
                    .frame(maxWidth: 300, minHeight: 200)
            }
            Picker("", selection: $selectedGraphStyle) {
                Text("Pie").tag(GraphStyle.pie)
                Text("Bar").tag(GraphStyle.bar)
                Text("Detail").tag(GraphStyle.detail)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
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
