import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @State private var appNameCounts: [String: Int] = [:]
    @State private var appTexts: [String: Int] = [:]
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
            HStack{
                PieChartView(data: appNameCounts)
                Text(stats)
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
    var data: [String: Int]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(data.keys.enumerated()), id: \.element) { index, key in
                    PieSliceView(
                        startAngle: angle(at: index, from: data),
                        endAngle: angle(at: index + 1, from: data),
                        color: colors[index % colors.count]
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width)
        }
        .padding()
    }

    private func angle(at index: Int, from data: [String: Int]) -> Angle {
        let total = data.values.reduce(0, +)
        let value = data.values.prefix(index).reduce(0, +)
        return Angle(degrees: Double(value) / Double(total) * 360.0)
    }

    private let colors: [Color] = [.red, .green, .blue, .orange, .purple, .yellow, .pink, .gray]
}

struct PieSliceView: View {
    var startAngle: Angle
    var endAngle: Angle
    var color: Color

    var body: some View {
        Path { path in
            let center = CGPoint(x: 100, y: 100)
            path.move(to: center)
            path.addArc(center: center, radius: 100, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        }
        .fill(color)
    }
}
