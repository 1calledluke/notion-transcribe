import AppKit
import SwiftUI

@MainActor
final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate?) {
        self.appDelegate = appDelegate
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings — Notion Transcribe"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        appDelegate?.settingsWindowClosed()
    }
}

struct SettingsView: View {
    @State private var token: String
    @State private var documentsDB: String
    @State private var projectsDB: String
    @State private var whisperModel: String
    @State private var showToken = false
    @State private var testResult: String? = nil
    @State private var testing = false
    @State private var saved = false

    init() {
        let cfg = Config.load()
        _token = State(initialValue: cfg.notionToken)
        _documentsDB = State(initialValue: cfg.documentsDB)
        _projectsDB = State(initialValue: cfg.projectsDB)
        _whisperModel = State(initialValue: cfg.whisperModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NOTION TRANSCRIBE SETTINGS")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Notion Integration Token")
                    .font(.callout)
                HStack(spacing: 6) {
                    Group {
                        if showToken {
                            TextField("ntn_…", text: $token)
                        } else {
                            SecureField("ntn_…", text: $token)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .help(showToken ? "Hide token" : "Show token")
                }
                Text("Token with access to Documents and Projects databases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Documents Database ID")
                    .font(.callout)
                TextField("", text: $documentsDB)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Projects Database ID")
                    .font(.callout)
                TextField("", text: $projectsDB)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Whisper Model Path")
                    .font(.callout)
                TextField("", text: $whisperModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 10) {
                Button(testing ? "Testing…" : "Test Connection") {
                    testConnection()
                }
                .disabled(testing || token.isEmpty)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                }

                Spacer()

                if saved {
                    Text("Saved ✓")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Save") {
                    var cfg = Config.load()
                    cfg.notionToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    cfg.documentsDB = documentsDB.trimmingCharacters(in: .whitespacesAndNewlines)
                    cfg.projectsDB = projectsDB.trimmingCharacters(in: .whitespacesAndNewlines)
                    cfg.whisperModel = whisperModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    cfg.save()
                    saved = true
                    Log.write("Settings saved (Notion token \(token.isEmpty ? "cleared" : "updated"))")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 480)
        .onChange(of: token) { _, _ in saved = false; testResult = nil }
        .onChange(of: documentsDB) { _, _ in saved = false; testResult = nil }
        .onChange(of: projectsDB) { _, _ in saved = false; testResult = nil }
        .onChange(of: whisperModel) { _, _ in saved = false; testResult = nil }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let docDB = documentsDB.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task.detached {
            var cfg = Config.load()
            cfg.notionToken = t
            cfg.documentsDB = docDB
            
            _ = NotionClient.isDuplicate(title: "__NON_EXISTENT_TEST_TITLE_12345__", config: cfg)
            await MainActor.run {
                testing = false
                testResult = "✓ Connected to Notion"
            }
        }
    }
}
