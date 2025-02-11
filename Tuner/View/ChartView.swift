//
//  ChartView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI
import Charts


enum GraphStyle {
    case pie
    case bar
    case detail
}

struct PieChartView: View {
    var data: [(key: String, value: Int)]
    var total: Int
    var topEntries: Int = 5

    var body: some View {
        Chart {
            let sortedData = data
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
                    Text("\(item.key.prefix(10))\n\(item.value)")
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


struct BarChartView: View {
    var data: [(key: String, value: Int)]
    var total: Int
    var topEntries: Int = 5

    var body: some View {
        Chart {
            ForEach(data.prefix(topEntries), id: \.key) { item in
                BarMark(
                    x: .value("Key", item.key),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(by: .value("Key", item.key))
            }
            BarMark(
                x: .value("Key", "Others"),
                y: .value("Value", data.dropFirst(topEntries).reduce(0) { $0 + $1.value })
            )
        }
        .chartLegend(.hidden)
    }
}

struct DetailView: View {
    var data: [(key: String, value: Int)]
    var topEntries: Int = -1

    var body: some View {
        let displayData = topEntries < 0 ? data : Array(data.prefix(topEntries))

        List {
            Section(header: HStack {
                Text("AppName")
                Spacer()
                Text("Characters")
            }) {
                ForEach(displayData, id: \.key) { item in
                    HStack {
                        Text(item.key)
                        Spacer()
                        Text("\(item.value)")
                    }
                }
            }
        }
    }
}
