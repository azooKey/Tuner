//
//  ChartView.swift
//  Tuner
//
//  Created by 高橋直希 on 2024/07/02.
//

import SwiftUI
import Charts

/// グラフの表示スタイルを定義する列挙型
enum GraphStyle {
    /// 円グラフ表示
    case pie
    /// 棒グラフ表示
    case bar
    /// 詳細リスト表示
    case detail
}

/// 円グラフを表示するビュー
/// - 上位N件のデータを個別に表示
/// - 残りのデータを「Others」として集計
struct PieChartView: View {
    /// 表示するデータ（キーと値のペアの配列）
    var data: [(key: String, value: Int)]
    
    /// データの合計値
    var total: Int
    
    /// 個別に表示する上位エントリ数
    var topEntries: Int = 5

    /// ビューの本体
    /// - 上位N件のデータを円グラフで表示
    /// - 残りのデータを「Others」として表示
    var body: some View {
        Chart {
            let sortedData = data
            let topData = sortedData.prefix(topEntries)
            let otherData = sortedData.dropFirst(topEntries)
            let otherValue = otherData.reduce(0) { $0 + $1.value }

            // 上位N件のデータを表示
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

            // 残りのデータを「Others」として表示
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

/// 棒グラフを表示するビュー
/// - 上位N件のデータを個別に表示
/// - 残りのデータを「Others」として集計
struct BarChartView: View {
    /// 表示するデータ（キーと値のペアの配列）
    var data: [(key: String, value: Int)]
    
    /// データの合計値
    var total: Int
    
    /// 個別に表示する上位エントリ数
    var topEntries: Int = 5

    /// ビューの本体
    /// - 上位N件のデータを棒グラフで表示
    /// - 残りのデータを「Others」として表示
    var body: some View {
        Chart {
            // 上位N件のデータを表示
            ForEach(data.prefix(topEntries), id: \.key) { item in
                BarMark(
                    x: .value("Key", item.key),
                    y: .value("Value", item.value)
                )
                .foregroundStyle(by: .value("Key", item.key))
            }
            
            // 残りのデータを「Others」として表示
            BarMark(
                x: .value("Key", "Others"),
                y: .value("Value", data.dropFirst(topEntries).reduce(0) { $0 + $1.value })
            )
        }
        .chartLegend(.hidden)
    }
}

/// 詳細なデータリストを表示するビュー
/// - アプリケーション名と文字数を表形式で表示
/// - 上位N件のデータのみを表示可能
struct DetailView: View {
    /// 表示するデータ（キーと値のペアの配列）
    var data: [(key: String, value: Int)]
    
    /// 表示する上位エントリ数（-1の場合は全件表示）
    var topEntries: Int = -1

    /// ビューの本体
    /// - アプリケーション名と文字数を表形式で表示
    /// - 上位N件のデータのみを表示（指定時）
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
