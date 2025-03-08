//
//  StatisticsView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/03.
//

import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var textModel: TextModel
    @EnvironmentObject var shareData: ShareData
    @State private var appNameCounts: [(key: String, value: Int)] = []
    @State private var appTexts: [(key: String, value: Int)] = []
    @State private var langTexts:  [(key: String, value: Int)] = []
    @State private var totalEntries: Int = 0
    @State private var totalTextLength: Int = 0
    @State private var averageTextLength: Int = 0
    @State private var japaneseTextLength: Int = 0
    @State private var englishTextLength: Int = 0
    @State private var stats: String = ""
    @State private var selectedGraphStyle: GraphStyle = .pie
    @State private var isLoading: Bool = false

    var body: some View {
        ScrollView {
            HStack {
                Button(action: {
                    Task {
                        await loadStatistics()
                    }
                }) {
                    Label("Update Statistics", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding(.bottom)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()

            if isLoading {
                ProgressView("Loading...")
                    .padding()
            } else {
                Text(stats)
                if selectedGraphStyle == .bar {
                    BarChartView(data: appTexts, total: totalTextLength)
                        .frame(maxWidth: 300, minHeight: 200)
                } else if selectedGraphStyle == .pie {
                    HStack{
                        PieChartView(data: appTexts, total: totalTextLength)
                            .frame(maxWidth: 300, minHeight: 200)
                        PieChartView(data: langTexts, total: totalTextLength)
                            .frame(maxWidth: 300, minHeight: 200)
                    }
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
        }
    }

    private func loadStatistics() async {
        isLoading = true
        defer { isLoading = false }

        textModel.generateStatisticsParameter(avoidApps: shareData.avoidApps,minTextLength: shareData.minTextLength, completion: { (counts, appText, entries, length, stats, langTexts) in
            self.appNameCounts = counts
            self.appTexts = appText
            self.totalEntries = entries
            self.totalTextLength = length
            self.stats = stats
            self.langTexts = langTexts
            shareData.apps = appNameCounts.map { $0.key }
        })
    }
}

