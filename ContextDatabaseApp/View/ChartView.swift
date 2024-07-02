//
//  ChartView.swift
//  ContextDatabaseApp
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI
import Charts


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
        .chartLegend(position: .trailing, alignment: .center)
    }
}
