import Foundation
import AVFoundation

final class TranscriptionPipeline {
    func run(folderURL: URL, onStatusUpdate: @escaping (String) -> Void) async {
        let config = Config.load()
        
        if config.notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Log.write("Notion token is empty. Aborting job.")
            Notifier.notify(body: "Transcription failed: Notion token is empty. Please set token in Settings.")
            return
        }
        
        if !FileManager.default.fileExists(atPath: config.whisperModel) {
            Log.write("Whisper model file missing at \(config.whisperModel). Aborting job.")
            Notifier.notify(body: "Transcription failed: Whisper model missing at \(config.whisperModel).")
            return
        }
        
        Log.write("Starting transcription job for folder: \(folderURL.path)")
        
        let scanResult = MediaFinder.findMedia(in: folderURL)
        let items = scanResult.items
        let totalClips = items.count
        
        if totalClips == 0 {
            Log.write("No transcribable media files found in \(folderURL.path)")
            let summary = "Transcribed 0 clips → Notion (\(scanResult.skippedBrawCount) skipped)"
            Notifier.notify(body: summary)
            return
        }
        
        var projectPageId: String? = nil
        if let projectName = ProjectResolver.extractProjectName(fromFolderPath: folderURL.path) {
            Log.write("Extracted project name '\(projectName)' from path: \(folderURL.path)")
            projectPageId = NotionClient.findProjectPageId(projectName: projectName, config: config)
            if let projectPageId {
                Log.write("Resolved Notion Project ID: \(projectPageId)")
            } else {
                Log.write("Project '\(projectName)' not found in Notion Projects DB.")
            }
        } else {
            Log.write("No project name pattern matched in folder path hierarchy.")
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NotionTranscribe_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        var transcribedCount = 0
        var skippedCount = scanResult.skippedBrawCount
        
        for (index, item) in items.enumerated() {
            let statusText = "Transcribing \(item.clipName) (\(index + 1) of \(totalClips))…"
            onStatusUpdate(statusText)
            Log.write("Processing clip \(index + 1)/\(totalClips): \(item.clipName)")
            
            // Duration gate: interviews are long takes, b-roll is short bursts.
            // Skipping sub-minute clips keeps whisper off 100 clips of room tone.
            if config.minClipSeconds > 0 {
                let dur = Self.clipDuration(item.targetURL)
                if let dur, dur < config.minClipSeconds {
                    Log.write("Skipping \(item.clipName): \(Int(dur))s < \(Int(config.minClipSeconds))s minimum (b-roll gate)")
                    skippedCount += 1
                    continue
                }
            }

            let docTitle = "\(item.clipName) — Transcript"
            if NotionClient.isDuplicate(title: docTitle, config: config) {
                Log.write("Skipping \(item.clipName): already transcribed in Notion (\(docTitle))")
                skippedCount += 1
                continue
            }
            
            let wavURL = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
            let extractOK = AudioExtractor.extractAudio(from: item.targetURL, to: wavURL)
            if !extractOK {
                Log.write("Failed audio extraction for \(item.clipName). Skipping.")
                skippedCount += 1
                try? FileManager.default.removeItem(at: wavURL)
                continue
            }
            
            let tempBase = tempDir.appendingPathComponent(UUID().uuidString)
            let srtText = WhisperTranscriber.transcribe(wavURL: wavURL, modelPath: config.whisperModel, outputBaseURL: tempBase)
            try? FileManager.default.removeItem(at: wavURL)
            
            guard let srtText = srtText, !srtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.write("Whisper transcription returned no text for \(item.clipName). Skipping.")
                skippedCount += 1
                continue
            }
            
            let paragraphs = SRTParser.parse(srtText)
            if paragraphs.isEmpty {
                Log.write("Parsed SRT contains no cues for \(item.clipName). Skipping.")
                skippedCount += 1
                continue
            }
            
            let postOK = NotionClient.createTranscriptPage(clipName: item.clipName, paragraphs: paragraphs, projectPageId: projectPageId, config: config)
            if postOK {
                Log.write("Successfully posted transcript for \(item.clipName) to Notion.")
                transcribedCount += 1
            } else {
                Log.write("Failed to post transcript for \(item.clipName) to Notion.")
                skippedCount += 1
            }
        }
        
        let summary = "Transcribed \(transcribedCount) clips → Notion (\(skippedCount) skipped)"
        Log.write("Job finished: \(summary)")
        Notifier.notify(body: summary)
    }

    /// Clip length in seconds via AVFoundation; nil if unreadable (then we
    /// don't gate — better to transcribe than silently drop).
    static func clipDuration(_ url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let sema = DispatchSemaphore(value: 0)
        var seconds: Double? = nil
        Task {
            if let d = try? await asset.load(.duration) {
                seconds = CMTimeGetSeconds(d)
            }
            sema.signal()
        }
        sema.wait()
        return (seconds?.isFinite == true) ? seconds : nil
    }
}
