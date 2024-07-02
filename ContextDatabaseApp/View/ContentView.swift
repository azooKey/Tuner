import SwiftUI
import Charts

enum GraphStyle {
    case pie
    case bar
    case detail
}

struct ContentView: View {
    @EnvironmentObject var textModel: TextModel
    @EnvironmentObject var shareData: ShareData
    @State private var appNameCounts: [(key: String, value: Int)] = []
    @State private var appTexts: [(key: String, value: Int)] = []
    @State private var totalEntries: Int = 0
    @State private var totalTextLength: Int = 0
    @State private var averageTextLength: Int = 0
    @State private var stats: String = ""
    @State private var selectedGraphStyle: GraphStyle = .pie
    @State private var isLoading: Bool = false
    @State private var selectedApp: String = ""

    var body: some View {
        ScrollView {
            Label("ContextHarvester", systemImage: "doc.text")
                .font(.title)
                .padding(.bottom)

            // 保存先pathの表示
            HStack {
                Text("Save Path:")
                Spacer()
                Text(textModel.getFileURL().path)
                Button(action: {
                    openFolderInFinder(url: textModel.getFileURL())
                }) {
                    Image(systemName: "folder")
                }
            }
            .padding(.horizontal)
            // 保存のON/OFFスイッチ
            Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
                .padding(.bottom)

            Label("Log Avoid Apps", systemImage: "xmark.circle.fill")
                .font(.headline)
                .padding(.bottom)

            HStack {
                Picker("Select App", selection: $selectedApp) {
                    Text("Select an app").tag("")
                    ForEach(shareData.apps, id: \.self) { app in
                        Text(app).tag(app)
                    }
                }
                .pickerStyle(MenuPickerStyle())


                Button(action: {
                    if !selectedApp.isEmpty && !shareData.avoidApps.contains(selectedApp) {
                        shareData.avoidApps.append(selectedApp)
                        selectedApp = ""
                    }
                }) {
                    Image(systemName: "plus")
                }
            }
            .padding(.horizontal)



            List {
                ForEach(shareData.avoidApps.indices, id: \.self) { index in
                    HStack {
                        Text(shareData.avoidApps[index])
                        Spacer()
                        if index == 0 {
                            Text("Default")
                                .foregroundColor(.gray)
                        } else {
                            Button(action: {
                                shareData.avoidApps.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .frame(height: 100)
            .padding(.horizontal)

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }

            Divider()

            HStack {
                Label("Statics", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .padding(.bottom)
                Button(action: {
                    Task {
                        await loadStatistics()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if isLoading {
                ProgressView("Loading...")
                    .padding()
            } else {
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
        }
        .task {
            await loadStatistics()
        }
    }

    private func loadStatistics() async {
        isLoading = true
        defer { isLoading = false }  // This will ensure isLoading is set to false when the function exits

        let (counts, appText, entries, length, stats) = await textModel.generateStatisticsParameter()
        self.appNameCounts = counts
        self.appTexts = appText
        self.totalEntries = entries
        self.totalTextLength = length
        self.stats = stats
        shareData.apps = appNameCounts.map { $0.key }
        self.averageTextLength = entries > 0 ? length / entries : 0
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .long
        return formatter
    }

    private func openFolderInFinder(url: URL) {
        let folderURL = url.deletingLastPathComponent()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

}
