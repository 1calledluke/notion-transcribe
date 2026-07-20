import Foundation

/// Append-only logger writing to ~/Library/Application Support/NotionTranscribe/app.log
enum Log {
    static var logFileURL: URL { url }

    private static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotionTranscribe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let queue = DispatchQueue(label: "NotionTranscribe.log")

    static func flush() {
        queue.sync {}
    }

    static func write(_ message: String) {
        let now = Date()
        let timestamp = formatter.string(from: now)
        print("[\(timestamp)] \(message)")
        queue.async {
            let line = "[\(timestamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
