import Foundation

enum AudioExtractor {
    static func extractAudio(from inputURL: URL, to outputWavURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            inputURL.path,
            outputWavURL.path
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputWavURL.path) {
                return true
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: data, encoding: .utf8) ?? ""
                Log.write("afconvert failed (code \(process.terminationStatus)) for \(inputURL.lastPathComponent): \(errStr)")
                return false
            }
        } catch {
            Log.write("afconvert exception for \(inputURL.lastPathComponent): \(error)")
            return false
        }
    }
}
