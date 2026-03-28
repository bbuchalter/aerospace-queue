import SwiftUI
import AppKit
import Combine

// MARK: - App Entry Point

@main
struct AeroQueueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var queueState: QueueState!
    private var queueObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let dir = "\(NSHomeDirectory())/workspace/aerospace-queue"
        queueState = QueueState(queuePath: "\(dir)/queue.txt")

        queueObserver = queueState.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] workspaces in
                self?.updateBadge(count: workspaces.count)
            }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tray.fill", accessibilityDescription: "AeroQueue")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(queueState: queueState))
    }

    func updateBadge(count: Int) {
        guard let button = statusItem.button else { return }
        if count == 0 {
            button.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "AeroQueue")
            button.title = ""
        } else {
            button.image = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: "AeroQueue")
            button.title = " \(count)"
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Queue State

@MainActor
class QueueState: ObservableObject {
    @Published var workspaces: [String] = []

    private let queuePath: String
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?

    init(queuePath: String) {
        self.queuePath = queuePath
        readQueue()
        startWatching()
    }

    func readQueue() {
        guard let contents = try? String(contentsOfFile: queuePath, encoding: .utf8) else {
            workspaces = []
            return
        }
        workspaces = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private func startWatching() {
        if !FileManager.default.fileExists(atPath: queuePath) {
            FileManager.default.createFile(atPath: queuePath, contents: nil)
        }

        fileDescriptor = open(queuePath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                let flags = source.data
                if flags.contains(.delete) || flags.contains(.rename) {
                    source.cancel()
                    close(self.fileDescriptor)
                    self.readQueue()
                    self.startWatching()
                } else {
                    self.readQueue()
                }
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source.resume()
        dispatchSource = source
    }
}

// MARK: - Main Popover View

struct PopoverView: View {
    @ObservedObject var queueState: QueueState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QueueSection(workspaces: queueState.workspaces)
            Divider()
            Text("Workspace grid and timeline coming soon.")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding()
            Spacer()
        }
        .frame(width: 320, height: 400)
    }
}

// MARK: - Queue Section

struct QueueSection: View {
    let workspaces: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUEUE (\(workspaces.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            if workspaces.isEmpty {
                Text("Empty")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(workspaces.enumerated()), id: \.offset) { index, ws in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Text(ws)
                            .font(.system(size: 13, weight: index == 0 ? .bold : .regular, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(index == 0 ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(index == 0 ? .white : .primary)
                            .cornerRadius(6)
                    }
                }
            }

            Text("Next: workspace \(workspaces.first ?? "—") · ⌘⌥⌃Space to pop")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
    }
}
