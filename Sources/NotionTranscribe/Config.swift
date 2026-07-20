import Foundation

struct Config: Codable {
    var notionToken: String = ""
    var documentsDB: String = "240714d3-333f-80ae-b147-e1bc122f0c86"
    var projectsDB: String = "232714d3-333f-80c8-88fd-d1eefeed3b3f"
    var whisperModel: String = NSHomeDirectory() + "/Models/ggml-large-v3-turbo.bin"
    var lastFolder: String = ""

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("NotionTranscribe/config.json")
    }

    private static var ditConfigURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("DITIngest/config.json")
    }

    static func load() -> Config {
        var cfg = Config()
        let url = fileURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            cfg = decoded
        }
        
        // On first launch, if notionToken is empty, try to copy it from DITIngest/config.json
        if cfg.notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let ditData = try? Data(contentsOf: ditConfigURL),
               let json = try? JSONSerialization.jsonObject(with: ditData) as? [String: Any],
               let token = json["notionToken"] as? String,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cfg.notionToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                cfg.save()
                Log.write("Copied notionToken from DITIngest config.")
            }
        }
        return cfg
    }

    func save() {
        let url = Config.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: url)
        }
    }
}
