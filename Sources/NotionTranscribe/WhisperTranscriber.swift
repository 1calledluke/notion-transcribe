import Foundation

enum WhisperTranscriber {
    static func transcribe(wavURL: URL, modelPath: String, outputBaseURL: URL) -> String? {
        let cliPath: String
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/whisper-cli") {
            cliPath = "/opt/homebrew/bin/whisper-cli"
        } else {
            cliPath = "whisper-cli"
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "-m", modelPath,
            "-f", wavURL.path,
            "-osrt",
            "-of", outputBaseURL.path,
            "-l", "en"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let srtPath = outputBaseURL.path + ".srt"
            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: srtPath) {
                let srtContent = try String(contentsOfFile: srtPath, encoding: .utf8)
                try? FileManager.default.removeItem(atPath: srtPath)
                return srtContent
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: data, encoding: .utf8) ?? ""
                Log.write("whisper-cli failed (code \(process.terminationStatus)) for \(wavURL.lastPathComponent): \(errStr)")
                return nil
            }
        } catch {
            Log.write("whisper-cli exception for \(wavURL.lastPathComponent): \(error)")
            return nil
        }
    }
}
