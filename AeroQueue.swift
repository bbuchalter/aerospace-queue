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
    var workspaceState: WorkspaceState!
    var eventLog: EventLog!
    private var queueObserver: AnyCancellable?
    private var eventObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let dir = "\(NSHomeDirectory())/workspace/aerospace-queue"
        queueState = QueueState(queuePath: "\(dir)/queue.txt")
        workspaceState = WorkspaceState()
        eventLog = EventLog(eventsPath: "\(dir)/events.jsonl")

        eventObserver = eventLog.$events
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                guard let self else { return }
                var seen = Set<String>()
                for event in events {
                    if event.type == "status", !seen.contains(event.workspace), let state = event.state {
                        self.workspaceState.updateAgentStatus(workspace: event.workspace, status: state)
                        seen.insert(event.workspace)
                    }
                }
            }

        queueObserver = queueState.$workspaces
            .combineLatest(workspaceState.$workspaces)
            .receive(on: RunLoop.main)
            .sink { [weak self] queue, wsMap in
                let needsAttention = wsMap.values.contains { $0.agentStatus == "needsAttention" }
                self?.updateBadge(count: queue.count, needsAttention: needsAttention)
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
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(queueState: queueState, workspaceState: workspaceState, eventLog: eventLog)
        )
    }

    func updateBadge(count: Int, needsAttention: Bool = false) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        if count == 0 {
            symbolName = "tray"
            button.title = ""
        } else {
            symbolName = "tray.full.fill"
            button.title = " \(count)"
        }

        var image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AeroQueue")
        if needsAttention {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            image = image?.withSymbolConfiguration(config)
        } else if count > 0 {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemBlue])
            image = image?.withSymbolConfiguration(config)
        }
        button.image = image
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

// MARK: - Workspace State

struct WorkspaceInfo {
    var apps: [String] = []
    var agentStatus: String? = nil
}

@MainActor
class WorkspaceState: ObservableObject {
    @Published var workspaces: [String: WorkspaceInfo] = [:]
    @Published var focused: String = ""

    private var timer: Timer?
    private let allWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func poll() {
        if let focusedOutput = runAerospace(["list-workspaces", "--focused"]) {
            focused = focusedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let output = runAerospace(["list-windows", "--all", "--format", "%{window-id} %{workspace} %{app-name}"]) else { return }

        var newMap: [String: WorkspaceInfo] = [:]
        for ws in allWorkspaces { newMap[ws] = WorkspaceInfo() }

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            let ws = String(parts[1])
            let app = String(parts[2])
            if newMap[ws] != nil { newMap[ws]!.apps.append(app) }
        }

        for ws in allWorkspaces {
            if let existing = workspaces[ws] {
                newMap[ws]?.agentStatus = existing.agentStatus
            }
        }

        workspaces = newMap
    }

    func updateAgentStatus(workspace: String, status: String) {
        if workspaces[workspace] != nil {
            workspaces[workspace]!.agentStatus = status
        }
    }

    nonisolated private func runAerospace(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/aerospace")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Event Log

struct AeroEvent: Identifiable {
    let id = UUID()
    let type: String
    let workspace: String
    let state: String?
    let timestamp: Date
}

@MainActor
class EventLog: ObservableObject {
    @Published var events: [AeroEvent] = []

    private let eventsPath: String
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0

    init(eventsPath: String) {
        self.eventsPath = eventsPath
        readNewEvents()
        startWatching()
    }

    func readNewEvents() {
        guard let handle = FileHandle(forReadingAtPath: eventsPath) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        lastOffset = handle.offsetInFile

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            guard let jsonData = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = dict["type"] as? String,
                  let workspace = dict["workspace"] as? String,
                  let ts = dict["timestamp"] as? TimeInterval else { continue }

            let event = AeroEvent(
                type: type,
                workspace: workspace,
                state: dict["state"] as? String,
                timestamp: Date(timeIntervalSince1970: ts)
            )
            events.insert(event, at: 0)
        }

        if events.count > 50 {
            events = Array(events.prefix(50))
        }
    }

    private func startWatching() {
        if !FileManager.default.fileExists(atPath: eventsPath) {
            FileManager.default.createFile(atPath: eventsPath, contents: nil)
        }

        fileDescriptor = open(eventsPath, O_EVTONLY)
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
                    self.lastOffset = 0
                    self.readNewEvents()
                    self.startWatching()
                } else {
                    self.readNewEvents()
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
    @ObservedObject var workspaceState: WorkspaceState
    @ObservedObject var eventLog: EventLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QueueSection(workspaces: queueState.workspaces)
            Divider()
            WorkspaceGrid(workspaces: workspaceState.workspaces, focused: workspaceState.focused)
            Divider()
            ActivityTimeline(events: eventLog.events)
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

// MARK: - Workspace Grid

struct WorkspaceGrid: View {
    let workspaces: [String: WorkspaceInfo]
    let focused: String
    let allWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKSPACES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(allWorkspaces, id: \.self) { ws in
                    let info = workspaces[ws] ?? WorkspaceInfo()
                    let isFocused = ws == focused
                    WorkspaceCell(name: ws, info: info, isFocused: isFocused)
                }
            }

            HStack(spacing: 12) {
                LegendDot(color: .orange, label: "needs attention")
                LegendDot(color: .blue, label: "working")
                LegendDot(color: .green, label: "idle")
                LegendDot(color: .purple, label: "focused")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(12)
    }
}

struct WorkspaceCell: View {
    let name: String
    let info: WorkspaceInfo
    let isFocused: Bool

    var borderColor: Color {
        if isFocused { return .purple }
        switch info.agentStatus {
        case "needsAttention": return .orange
        case "idle", "stopped": return .green
        default:
            return info.apps.isEmpty ? .clear : .blue
        }
    }

    var bgColor: Color {
        borderColor.opacity(borderColor == .clear ? 0 : 0.15)
    }

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: isFocused ? .bold : .regular, design: .monospaced))
            .foregroundColor(borderColor == .clear ? .secondary.opacity(0.5) : borderColor)
            .frame(width: 28, height: 28)
            .background(bgColor)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1.5)
            )
            .cornerRadius(4)
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
}

// MARK: - Activity Timeline

struct ActivityTimeline: View {
    let events: [AeroEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            if events.isEmpty {
                Text("No activity yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events.prefix(10)) { event in
                            EventRow(event: event)
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

struct EventRow: View {
    let event: AeroEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var indicatorColor: Color {
        switch event.type {
        case "push": return .blue
        case "pop": return .purple
        case "status":
            switch event.state {
            case "needsAttention": return .orange
            case "idle", "stopped": return .green
            default: return .gray
            }
        default: return .gray
        }
    }

    var description: String {
        switch event.type {
        case "push": return "pushed to queue"
        case "pop": return "popped & switched"
        case "status":
            switch event.state {
            case "needsAttention": return "needs attention"
            case "idle": return "agent idle"
            case "stopped": return "agent stopped"
            default: return event.state ?? "unknown"
            }
        default: return event.type
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
            Text(event.workspace)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}
