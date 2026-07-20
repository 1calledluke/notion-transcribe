import AppKit

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
    exit(0)   // never fall through to launching the GUI
}

// Headless run for testing/automation: --transcribe /path/to/folder
if let i = CommandLine.arguments.firstIndex(of: "--transcribe"),
   CommandLine.arguments.count > i + 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let sema = DispatchSemaphore(value: 0)
    Task {
        await TranscriptionPipeline().run(folderURL: folder) { status in
            print("status: \(status)")
        }
        sema.signal()
    }
    sema.wait()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
