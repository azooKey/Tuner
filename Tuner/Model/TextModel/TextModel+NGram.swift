import Foundation
import EfficientNGram

// MARK: - N-gram Training
extension TextModel {
    /// 新規エントリを使用してN-gramモデルを追加学習
    /// - Parameters:
    ///   - newEntries: 新規テキストエントリの配列
    ///   - ngramSize: N-gramのサイズ
    ///   - baseFilename: ベースとなるファイル名
    func trainNGramOnNewEntries(newEntries: [TextEntry], ngramSize: Int, baseFilePattern: String) async {
        let lines = newEntries.map { $0.text }
        if lines.isEmpty {
            return
        }
        let fileManager = self.fileManager
        let outputDirURL = getLMDirectory() // Use the LM directory function
        let outputDir = outputDirURL.path
        
        do {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return
        }
        
        // WIPファイルの作成（コピー処理は削除）
        let wipFileURL = URL(fileURLWithPath: outputDir).appendingPathComponent("\(baseFilePattern).wip")
        do {
            try "Training in progress".write(to: wipFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to create WIP file: \(error)")
        }
        
        // trainNGram 呼び出しを do-catch で囲む
        do {
             // --- テスト用変更を元に戻す ---
             let resumePattern = baseFilePattern // lm の場合は lm を resumePattern として渡す
             print("    Calling trainNGram with resumeFilePattern = \\(resumePattern)") // ログ追加
             let resumeFileURL = outputDirURL.appendingPathComponent(resumePattern) // フルパスを生成
             try await trainNGram( // try を追加 (もし trainNGram が throws する場合)
                 lines: lines,
                 n: ngramSize,
                 baseFilePattern: baseFilePattern,
                 outputDir: outputDir,
                 resumeFilePattern: resumeFileURL.path // フルパスを渡すように変更
             )
             // --- テスト用変更ここまで ---
             print("  trainNGram call finished successfully.")
        } catch {
            print("❌ Failed to train N-gram model: \(error)")
        }

        // WIP ファイルを削除
        do {
            try fileManager.removeItem(at: wipFileURL)
        } catch {
            print("❌ Failed to remove WIP file: \(error)")
        }

        // lm モデルのコピー処理は trainNGramFromTextEntries で行うため、ここからは削除
    }
    
    
    /// 保存されたテキストエントリからN-gramモデルを学習
    /// - Parameters:
    ///   - ngramSize: N-gramのサイズ
    ///   - baseFilename: ベースとなるファイル名
    ///   - maxEntryCount: 最大エントリ数
    func trainNGramFromTextEntries(ngramSize: Int = 5, baseFilePattern: String = "original", maxEntryCount: Int = 100_000) async {
        let fileManager = self.fileManager
        
        let savedTexts = await loadFromFileAsync()
        
        let importFileURL = getTextEntryDirectory().appendingPathComponent("import.jsonl") // Use TextEntry directory
        var importEntries: [TextEntry] = []
        if fileManager.fileExists(atPath: importFileURL.path) {
            if let fileContents = try? String(contentsOf: importFileURL, encoding: .utf8) {
                let lines = fileContents.split(separator: "\n")
                for line in lines {
                    guard !line.isEmpty else { continue }
                    if let jsonData = line.data(using: .utf8),
                       let entry = try? JSONDecoder().decode(TextEntry.self, from: jsonData) {
                        importEntries.append(entry)
                    }
                }
            }
        }
        
        let combinedEntries = savedTexts + importEntries
        let trainingEntries = combinedEntries.suffix(maxEntryCount)
        let lines = trainingEntries.map { $0.text }
        
        let outputDirURL = getLMDirectory() // Use the LM directory function
        let outputDir = outputDirURL.path
        
        do {
            try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return
        }
        
        if baseFilePattern == "original" {
            let lmFiles = [
                "lm_c_abc.marisa",
                "lm_u_abx.marisa",
                "lm_u_xbc.marisa",
                "lm_r_xbx.marisa",
                "lm_c_bc.marisa",
            ]
            for lmFile in lmFiles {
                let lmFilePath = URL(fileURLWithPath: outputDir).appendingPathComponent(lmFile).path
                if fileManager.fileExists(atPath: lmFilePath) {
                    do {
                        try fileManager.removeItem(atPath: lmFilePath)
                    } catch {
                        print("❌ Failed to remove lm file \(lmFile): \(error)")
                    }
                }
            }
        }
        
        await trainNGram(lines: lines, n: ngramSize, baseFilePattern: baseFilePattern, outputDir: outputDir)

        // オリジナルモデル生成後、追加学習用のlmモデルをコピーして準備 (baseFilePattern == "original" の場合のみ)
        if baseFilePattern == "original" {
            let originalFiles = [
                "original_c_abc.marisa",
                "original_u_abx.marisa",
                "original_u_xbc.marisa",
                "original_r_xbx.marisa",
                "original_c_bc.marisa",
            ]
            let lmFiles = [
                "lm_c_abc.marisa",
                "lm_u_abx.marisa",
                "lm_u_xbc.marisa",
                "lm_r_xbx.marisa",
                "lm_c_bc.marisa",
            ]

            print("Copying original models to lm models after training...")
            for (origFile, lmFile) in zip(originalFiles, lmFiles) {
                let origPath = URL(fileURLWithPath: outputDir).appendingPathComponent(origFile).path
                let lmPath = URL(fileURLWithPath: outputDir).appendingPathComponent(lmFile).path
                
                // 既存の lm ファイルがあれば削除
                if fileManager.fileExists(atPath: lmPath) {
                    do {
                        try fileManager.removeItem(atPath: lmPath)
                        print("  Removed existing lm file: \(lmFile)")
                    } catch {
                        print("❌ Failed to remove existing lm file \(lmFile): \(error)")
                    }
                }
                
                // original ファイルが存在すればコピー
                if fileManager.fileExists(atPath: origPath) {
                    do {
                        try fileManager.copyItem(at: URL(fileURLWithPath: origPath), to: URL(fileURLWithPath: lmPath))
                        print("  Copied \(origFile) to \(lmFile)")
                    } catch {
                        print("❌ Error duplicating \(origFile) to \(lmFile): \(error)")
                    }
                } else {
                    print("⚠️ Original file \(origFile) not found, cannot copy to \(lmFile).")
                }
            }
        }

        await MainActor.run {
            self.lastNGramTrainingDate = Date()
        }
    }
}

// MARK: - 手動での追加学習
extension TextModel {
    /// 手動でN-gramモデルの追加学習 (lm) を実行する
    func trainIncrementalNGramManually() async {
        print("Starting manual incremental N-gram training (lm)...")
        
        // --- 事前チェック: 必要な lm ファイルが存在するか確認 ---
        let fileManager = self.fileManager
        let lmDirURL = getLMDirectory()
        let expectedLmFiles = [
            "lm_c_abc.marisa",
            "lm_u_abx.marisa",
            "lm_u_xbc.marisa",
            "lm_r_xbx.marisa",
            "lm_c_bc.marisa"
        ]
        var allLmFilesExist = true
        print("  Checking for existing LM files in: \(lmDirURL.path)")
        for lmFile in expectedLmFiles {
            let lmPath = lmDirURL.appendingPathComponent(lmFile).path
            if fileManager.fileExists(atPath: lmPath) {
                print("    Found: \(lmFile)")
            } else {
                print("    ❌ MISSING: \(lmFile)")
                allLmFilesExist = false
            }
        }
        
        guard allLmFilesExist else {
            print("  Required LM files are missing. Aborting incremental training.")
            print("  Please run 'N-gram再構築 (全データ)' first to create the initial LM models.")
            // ここでユーザーにアラートを表示するなどの処理を追加することも可能
            return
        }
        print("  All required LM files found.")
        // --- 事前チェック完了 ---
        
        // savedTexts.jsonl から読み込み
        let savedTexts = await loadFromFileAsync()
        print("  Loaded \(savedTexts.count) entries from savedTexts.jsonl")
        
        // import.jsonl から読み込み
        let importTexts = await loadFromImportFileAsync()
        print("  Loaded \(importTexts.count) entries from import.jsonl")
        
        // 両方を結合
        let combinedEntries = savedTexts + importTexts
        print("  Total entries for training: \(combinedEntries.count)")
        
        guard !combinedEntries.isEmpty else {
            print("No entries found to train. Aborting incremental training.")
            // 必要であればユーザーに通知する処理を追加
            return
        }
        
        // trainNGramOnNewEntries を lm モードで呼び出す
        // trainNGramOnNewEntries は内部で trainNGram を呼び出し、
        // resumeFilePattern="lm" により既存の lm モデルに追記学習する
        await trainNGramOnNewEntries(newEntries: combinedEntries, ngramSize: self.ngramSize, baseFilePattern: "lm")
        
        // 最終訓練日時を更新
        await MainActor.run {
            self.lastNGramTrainingDate = Date()
            print("Manual incremental N-gram training (lm) finished at \(self.lastNGramTrainingDate!)")
        }
    }
} 