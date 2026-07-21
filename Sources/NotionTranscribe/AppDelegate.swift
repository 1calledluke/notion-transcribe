import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var settingsController: SettingsController?
    private var progressController: ProgressController?

    private var isTranscribing = false
    private var jobQueue: [URL] = []
    private var queueTimer: Timer?

    /// DIT (or anything) drops a .txt here holding a folder path; we pick it up
    /// and run it through the visible pipeline. This is how the auto-trigger
    /// after a card dump becomes something you can actually watch.
    static var queueDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotionTranscribe/queue")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        _ = Config.load()
        setupMenu()
        LoginItem.enable()

        try? FileManager.default.createDirectory(at: Self.queueDir, withIntermediateDirectories: true)
        // Poll the queue every 3s (simple + robust vs. FSEvents edge cases).
        queueTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.drainQueue()
        }
        drainQueue()
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateBarIcon(active: false)

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "Show Progress…", action: #selector(showProgress), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let transcribeItem = NSMenuItem(title: "Transcribe Folder…", action: #selector(selectFolderToTranscribe), keyEquivalent: "t")
        transcribeItem.target = self
        menu.addItem(transcribeItem)
        let resumeItem = NSMenuItem(title: "Resume Last Job", action: #selector(resumeLastJob), keyEquivalent: "")
        resumeItem.target = self
        menu.addItem(resumeItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateBarIcon(active: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = active ? "text.bubble.fill" : "text.bubble"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Notion Transcribe")
        // Show a queue depth badge when work is piled up.
        let waiting = jobQueue.count
        button.title = (active && waiting > 0) ? " \(waiting + 1)" : (active ? " •" : "")
    }

    // MARK: - Queue

    private func drainQueue() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.queueDir,
                                                      includingPropertiesForKeys: [.creationDateKey]) else { return }
        for file in files where file.pathExtension == "txt" {
            if let path = (try? String(contentsOf: file, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, fm.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                if !jobQueue.contains(url) { enqueue(url) }
            }
            try? fm.removeItem(at: file)   // consumed
        }
    }

    private func enqueue(_ folderURL: URL) {
        jobQueue.append(folderURL)
        Log.write("Queued for transcription: \(folderURL.path)")
        updateStatus(isTranscribing
            ? "\(statusMenuItem.title)  (+\(jobQueue.count) queued)"
            : "Queued: \(folderURL.lastPathComponent)")
        startNextIfIdle()
    }

    private func startNextIfIdle() {
        guard !isTranscribing, !jobQueue.isEmpty else { return }
        let folderURL = jobQueue.removeFirst()
        runJob(folderURL: folderURL)
    }

    // MARK: - Job execution

    @objc private func selectFolderToTranscribe() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Transcribe Folder"
        openPanel.message = "Select a folder containing interview footage or audio to transcribe."
        let cfg = Config.load()
        if !cfg.lastFolder.isEmpty, FileManager.default.fileExists(atPath: cfg.lastFolder) {
            openPanel.directoryURL = URL(fileURLWithPath: cfg.lastFolder)
        }
        NSApp.activate(ignoringOtherApps: true)
        openPanel.begin { [weak self] response in
            guard response == .OK, let url = openPanel.url else { return }
            self?.enqueue(url)   // queues if one's already running
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                enqueue(url)
            }
        }
    }

    private func runJob(folderURL: URL) {
        var cfg = Config.load()
        cfg.lastFolder = folderURL.path
        cfg.save()

        isTranscribing = true
        updateBarIcon(active: true)
        showProgress()
        progressController?.beginJob(folder: folderURL)
        updateStatus("Scanning \(folderURL.lastPathComponent)…")

        Task.detached {
            let pipeline = TranscriptionPipeline()
            await pipeline.run(folderURL: folderURL) { [weak self] statusText in
                Task { @MainActor in
                    self?.updateStatus(statusText)
                    self?.progressController?.update(line: statusText)
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isTranscribing = false
                self.progressController?.finishJob()
                if self.jobQueue.isEmpty {
                    self.updateStatus("Idle")
                    self.updateBarIcon(active: false)
                } else {
                    self.startNextIfIdle()
                }
            }
        }
    }

    func updateStatus(_ text: String) {
        statusMenuItem.title = text
        updateBarIcon(active: isTranscribing)
    }

    @objc private func showProgress() {
        if progressController == nil {
            progressController = ProgressController(appDelegate: self)
        }
        progressController?.show()
    }

    func progressWindowClosed() { progressController = nil }

    @objc private func resumeLastJob() {
        guard let state = JobState.resumable() else {
            let a = NSAlert()
            a.messageText = "Nothing to resume"
            a.informativeText = "The last transcription job finished (or its folder is gone)."
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            return
        }
        Log.write("Resuming job: \(state.folderPath) (\(state.doneClips.count)/\(state.totalClips) were done)")
        enqueue(URL(fileURLWithPath: state.folderPath))
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsController(appDelegate: self)
        }
        settingsController?.show()
    }

    func settingsWindowClosed() { settingsController = nil }

    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}
