import Foundation

enum SelfTest {
    static func run() -> Never {
        print("==> Running NotionTranscribe self-tests…")
        
        // 1. Test Project Name Extraction
        let test1 = ProjectResolver.extractProjectName(fromFolderPath: "/Volumes/Footage/26.07_Equip Videos_0118")
        guard test1 == "Equip Videos" else {
            print("FAIL: Expected 'Equip Videos', got '\(test1 ?? "nil")'")
            exit(1)
        }
        print("PASS: Project name extraction (\"26.07_Equip Videos_0118\" -> \"Equip Videos\")")

        let test2 = ProjectResolver.extractProjectName(fromFolderPath: "/Volumes/Footage/25.12_Christmas")
        guard test2 == "Christmas" else {
            print("FAIL: Expected 'Christmas', got '\(test2 ?? "nil")'")
            exit(1)
        }
        print("PASS: Project name extraction (\"25.12_Christmas\" -> \"Christmas\")")

        let test3 = ProjectResolver.extractProjectName(fromFolderPath: "/Volumes/Footage/Video")
        guard test3 == nil else {
            print("FAIL: Expected nil, got '\(test3!)'")
            exit(1)
        }
        print("PASS: Project name extraction (\"Video\" -> nil)")

        // 2. Test SRT Parser
        let sampleSRT = """
        1
        00:00:01,230 --> 00:00:04,500
        Welcome to the interview session.

        2
        00:00:05,100 --> 00:00:09,800
        We will discuss project updates today.

        3
        00:04:12,340 --> 00:04:15,000
        This is a segment after a pause.
        """
        
        let paragraphsNormal = SRTParser.parse(sampleSRT, maxCharsPerParagraph: 1800)
        guard paragraphsNormal.count == 1 else {
            print("FAIL: Expected 1 grouped paragraph, got \(paragraphsNormal.count)")
            exit(1)
        }
        guard paragraphsNormal[0].hasPrefix("[00:00:01]") else {
            print("FAIL: Expected timestamp prefix '[00:00:01]', got '\(paragraphsNormal[0])'")
            exit(1)
        }
        guard paragraphsNormal[0].contains("Welcome to the interview session.") && paragraphsNormal[0].contains("This is a segment after a pause.") else {
            print("FAIL: Missing expected content in paragraph: '\(paragraphsNormal[0])'")
            exit(1)
        }
        print("PASS: SRT parser paragraph grouping with timestamp prefixes")

        let paragraphsSplit = SRTParser.parse(sampleSRT, maxCharsPerParagraph: 60)
        guard paragraphsSplit.count == 3 else {
            print("FAIL: Expected 3 split paragraphs for small max size, got \(paragraphsSplit.count)")
            exit(1)
        }
        guard paragraphsSplit[0].hasPrefix("[00:00:01]"),
              paragraphsSplit[1].hasPrefix("[00:00:05]"),
              paragraphsSplit[2].hasPrefix("[00:04:12]") else {
            print("FAIL: Incorrect prefixes in split paragraphs: \(paragraphsSplit)")
            exit(1)
        }
        print("PASS: SRT parser paragraph max size split testing")

        print("PASS: All self-tests passed cleanly.")
        exit(0)
    }
}
