import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var settingsController: SettingsController?
    private var isTranscribing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // Auto-load config (which copies token from DITIngest if empty)
        _ = Config.load()
        
        setupMenu()
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Notion Transcribe")
        }
        
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let transcribeItem = NSMenuItem(title: "Transcribe Folder…", action: #selector(selectFolderToTranscribe), keyEquivalent: "t")
        transcribeItem.target = self
        menu.addItem(transcribeItem)
        
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc private func selectFolderToTranscribe() {
        guard !isTranscribing else {
            let alert = NSAlert()
            alert.messageText = "Transcription in Progress"
            alert.informativeText = "Please wait for the current transcription job to finish."
            alert.runModal()
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Transcribe Folder"
        openPanel.message = "Select a folder containing interview footage or audio files to transcribe."
        
        let cfg = Config.load()
        if !cfg.lastFolder.isEmpty, FileManager.default.fileExists(atPath: cfg.lastFolder) {
            openPanel.directoryURL = URL(fileURLWithPath: cfg.lastFolder)
        }
        
        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            self?.startJob(folderURL: url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
            startJob(folderURL: first)
        }
    }

    private func startJob(folderURL: URL) {
        guard !isTranscribing else { return }
        
        var cfg = Config.load()
        cfg.lastFolder = folderURL.path
        cfg.save()
        
        isTranscribing = true
        updateStatus("Scanning folder…")
        
        Task.detached {
            let pipeline = TranscriptionPipeline()
            await pipeline.run(folderURL: folderURL) { [weak self] statusText in
                Task { @MainActor in
                    self?.updateStatus(statusText)
                }
            }
            
            Task { @MainActor [weak self] in
                self?.isTranscribing = false
                self?.updateStatus("Idle")
            }
        }
    }

    func updateStatus(_ text: String) {
        statusMenuItem.title = text
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsController(appDelegate: self)
        }
        settingsController?.show()
    }

    func settingsWindowClosed() {
        settingsController = nil
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
