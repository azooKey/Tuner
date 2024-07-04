//
//  SettingsView.swift
//  ContextDatabaseApp
//
//  Created by 高橋直希 on 2024/07/03.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var textModel: TextModel
    @EnvironmentObject var shareData: ShareData
    @State private var selectedApp: String = ""

    var body: some View {
        ScrollView {
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
            .padding()

            Divider()

            // 保存のON/OFFスイッチ
            Toggle("Save Data", isOn: $textModel.isDataSaveEnabled)
                .padding(.bottom)

            HStack {
                Text("Line Threshold:")
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $shareData.saveLineTh, in: 10...100, step: 10) {
                    Text("\(shareData.saveLineTh) lines")
                        .frame(width: 80, alignment: .leading)
                }
            }

            HStack {
                Text("Save Interval:")
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $shareData.saveIntervalSec, in: 10...600, step: 10) {
                    Text("\(shareData.saveIntervalSec) seconds")
                        .frame(width: 80, alignment: .leading)
                }
            }

            HStack {
                Text("Min Text Length:")
                    .frame(width: 120, alignment: .trailing)
                Stepper(value: $shareData.minTextLength, in: 0...100, step: 10) {
                    Text("\(shareData.minTextLength) characters")
                        .frame(width: 80, alignment: .leading)
                }
            }

            Text("Data will be saved when either condition is met.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

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
                    print(shareData.avoidApps)
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
            .frame(height: 200)
            .padding(.horizontal)

            if let lastSavedDate = textModel.lastSavedDate {
                Text("Last Saved: \(lastSavedDate, formatter: dateFormatter)")
                    .padding(.top)
            }
        }
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
