# AeroQueue Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-file SwiftUI menu bar app that shows queue state, workspace status, and activity timeline for the aerospace-queue system.

**Architecture:** NSStatusItem with NSPopover containing SwiftUI views. Data comes from three sources: file-watching `queue.txt`, polling `aerospace list-windows` via Timer, and file-watching `events.jsonl`. Shell scripts emit structured JSON events.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit (NSStatusItem, NSPopover), DispatchSource for file monitoring, Foundation Process for CLI calls.

**Spec:** `docs/superpowers/specs/2026-03-28-aeroqueue-menubar-design.md`

---

### Task 1: Trim workspaces to 1–9

**Files:**
- Modify: `.aerospace.toml`
- Modify: `push.sh:85`

- [ ] **Step 1: Edit `.aerospace.toml` — remove A–Z persistent workspaces**

Change the persistent-workspaces line to:

```toml
persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
```

- [ ] **Step 2: Edit `.aerospace.toml` — remove A–Z workspace switching bindings**

Remove all `alt-a` through `alt-z` bindings (lines like `alt-a = 'workspace A'`). Keep `alt-1` through `alt-9`, `alt-tab`, and `alt-shift-tab`.

- [ ] **Step 3: Edit `.aerospace.toml` — remove A–Z move-node bindings**

Remove all `alt-shift-a` through `alt-shift-z` bindings (lines like `alt-shift-a = 'move-node-to-workspace A'`). Keep `alt-shift-1` through `alt-shift-9`.

- [ ] **Step 4: Edit `push.sh` — trim candidate list**

Change line 85 from:
```bash
  for candidate in 1 2 3 4 5 6 7 8 9 A B C D E F G I M N O P Q R S T U V W X Y Z; do
```
To:
```bash
  for candidate in 1 2 3 4 5 6 7 8 9; do
```

- [ ] **Step 5: Verify AeroSpace config is valid**

Run:
```bash
/opt/homebrew/bin/aerospace config --check 2>&1
```
Expected: no errors (or AeroSpace not running is fine — the config syntax should be valid).

- [ ] **Step 6: Commit**

```bash
git add .aerospace.toml push.sh
git commit -m "chore: trim workspaces to 1-9, remove A-Z"
```

---

### Task 2: Add `events.jsonl` support to `push.sh` and `pop.sh`

**Files:**
- Modify: `push.sh`
- Modify: `pop.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Add `events.jsonl` to `.gitignore`**

Append to `.gitignore`:
```
events.jsonl
```

- [ ] **Step 2: Add event emission to `push.sh`**

After the `printf '%s\n' "$target_ws" >> "$queue"` line (and also after the "skipped duplicate" path — we still want the event), add the event emission. Place this just before the `say "push $target_ws"` line at the end of the file:

```bash
# Emit structured event for menu bar app
events="${dir}/events.jsonl"
printf '{"type":"push","workspace":"%s","timestamp":%d}\n' "$target_ws" "$(date +%s)" >> "$events"
```

- [ ] **Step 3: Add event emission to `pop.sh`**

After the `aerospace workspace "$first"` line (line 50), before the `say` line, add:

```bash
# Emit structured event for menu bar app
events="${dir}/events.jsonl"
printf '{"type":"pop","workspace":"%s","timestamp":%d}\n' "$first" "$(date +%s)" >> "$events"
```

- [ ] **Step 4: Test push event emission manually**

Run:
```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
echo "test" >> queue.txt
bash -x push.sh 2>&1 | tail -5
cat events.jsonl | tail -1
```
Expected: the last line of `events.jsonl` should be a JSON object with `"type":"push"`.

Note: `push.sh` may fail or exit early depending on AeroSpace/iTerm2 state — that's OK. If it exits before the event line, manually test the JSON append:
```bash
printf '{"type":"push","workspace":"1","timestamp":%d}\n' "$(date +%s)" >> events.jsonl
cat events.jsonl
```

- [ ] **Step 5: Commit**

```bash
git add push.sh pop.sh .gitignore
git commit -m "feat: emit structured events to events.jsonl from push/pop"
```

---

### Task 3: Create `status.sh`

**Files:**
- Create: `status.sh`

- [ ] **Step 1: Write `status.sh`**

Create `status.sh` in the project root:

```bash
#!/bin/bash
set -euo pipefail

dir="${HOME}/workspace/aerospace-queue"
events="${dir}/events.jsonl"
log="${dir}/debug.log"

log() { printf '%s [status] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$log"; }

state="${1:-}"
if [ -z "$state" ]; then
  log "FAIL: no state argument provided"
  exit 1
fi

log "--- status.sh started with state=$state ---"

/usr/bin/pgrep -qx AeroSpace || { log "AeroSpace not running, exiting"; exit 0; }

# Extract the UUID from ITERM_SESSION_ID (format: wXtYpZ:UUID)
session_uuid="${ITERM_SESSION_ID#*:}"
log "ITERM_SESSION_ID=${ITERM_SESSION_ID:-unset}, uuid=$session_uuid"

# Find the iTerm window title for this session via AppleScript
window_title=$(osascript -e "
tell application \"iTerm2\"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if unique ID of s is \"$session_uuid\" then
          return name of w
        end if
      end repeat
    end repeat
  end repeat
end tell
" 2>&1)
log "window_title=$window_title"

if [ -z "$window_title" ]; then
  log "FAIL: no window title found"
  exit 1
fi

# Match the window title to an aerospace window and its current workspace
aero_windows=$(/opt/homebrew/bin/aerospace list-windows --all --format '%{window-id} %{workspace} %{window-title}')

read -r window_id current_ws < <(
  echo "$aero_windows" \
    | while IFS=' ' read -r wid ws title; do
        if [ "$title" = "$window_title" ]; then
          echo "$wid $ws"
          break
        fi
      done
)
log "matched window_id=${window_id:-none} current_ws=${current_ws:-none}"

if [ -z "${current_ws:-}" ]; then
  log "FAIL: no workspace found for window"
  exit 1
fi

printf '{"type":"status","workspace":"%s","state":"%s","timestamp":%d}\n' "$current_ws" "$state" "$(date +%s)" >> "$events"
log "wrote status event: workspace=$current_ws state=$state"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/brian.buchalter/workspace/aerospace-queue/status.sh
```

- [ ] **Step 3: Test manually**

```bash
printf '{"type":"status","workspace":"1","state":"needsAttention","timestamp":%d}\n' "$(date +%s)" >> /Users/brian.buchalter/workspace/aerospace-queue/events.jsonl
cat /Users/brian.buchalter/workspace/aerospace-queue/events.jsonl | tail -1
```
Expected: JSON line with `"type":"status","workspace":"1","state":"needsAttention"`.

- [ ] **Step 4: Commit**

```bash
git add status.sh
git commit -m "feat: add status.sh for hook-driven workspace status events"
```

---

### Task 4: Minimal menu bar app — icon and popover shell

**Files:**
- Create: `AeroQueue.swift`

This task creates the bare-bones menu bar app: an icon that shows a popover with placeholder text. No data yet.

- [ ] **Step 1: Write `AeroQueue.swift` with menu bar icon and empty popover**

Create `AeroQueue.swift` in the project root:

```swift
import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct AeroQueueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        popover.contentViewController = NSHostingController(rootView: PopoverView())
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

// MARK: - Main Popover View

struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AeroQueue")
                .font(.headline)
                .padding()
            Divider()
            Text("Queue, workspace grid, and timeline will go here.")
                .padding()
            Spacer()
        }
        .frame(width: 320, height: 400)
    }
}
```

- [ ] **Step 2: Compile**

```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift
```

Expected: compiles with no errors, produces `./AeroQueue` binary.

- [ ] **Step 3: Run and verify**

```bash
./AeroQueue &
```

Expected: a tray icon appears in the menu bar. Click it — a popover opens with placeholder text. Quit with `killall AeroQueue`.

- [ ] **Step 4: Add build artifacts to `.gitignore`**

Append to `.gitignore`:
```
AeroQueue
```

- [ ] **Step 5: Commit**

```bash
git add AeroQueue.swift .gitignore
git commit -m "feat: minimal menu bar app with icon and empty popover"
```

---

### Task 5: Queue data model and file watcher

**Files:**
- Modify: `AeroQueue.swift`

Add the queue state model and file watcher. The popover displays live queue contents.

- [ ] **Step 1: Add QueueState observable class**

Add after the `AppDelegate` class, before `PopoverView`:

```swift
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
        // Ensure file exists
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
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // File was replaced (e.g., mv from pop.sh) — reopen
                source.cancel()
                close(self.fileDescriptor)
                self.readQueue()
                self.startWatching()
            } else {
                self.readQueue()
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
```

- [ ] **Step 2: Wire QueueState into AppDelegate and PopoverView**

Update `AppDelegate.applicationDidFinishLaunching` to create the state and pass it to the view. Replace the popover contentViewController line:

```swift
    // Add as a property on AppDelegate:
    var queueState: QueueState!
```

In `applicationDidFinishLaunching`, before creating the popover:

```swift
        let dir = "\(NSHomeDirectory())/workspace/aerospace-queue"
        queueState = QueueState(queuePath: "\(dir)/queue.txt")
```

Replace the popover contentViewController line:

```swift
        popover.contentViewController = NSHostingController(rootView: PopoverView(queueState: queueState))
```

- [ ] **Step 3: Update PopoverView to show queue**

Replace `PopoverView` with:

```swift
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
```

- [ ] **Step 4: Compile and test**

```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift
./AeroQueue &
```

Test: echo some workspaces into `queue.txt` and verify the popover updates:
```bash
printf '3\n7\n1\n' > queue.txt
```
Click the menu bar icon — should show `[3] → [7] → [1]` with 3 highlighted.

```bash
> queue.txt
```
Click again — should show "Empty".

Kill with `killall AeroQueue`.

- [ ] **Step 5: Commit**

```bash
git add AeroQueue.swift
git commit -m "feat: queue section with live file-watching of queue.txt"
```

---

### Task 6: Menu bar badge and tint color

**Files:**
- Modify: `AeroQueue.swift`

Update the status item to show queue depth and tint based on state.

- [ ] **Step 1: Add badge update method to AppDelegate**

Add a method to `AppDelegate` and call it reactively. Add this property and method:

```swift
    private var queueObserver: AnyCancellable?
```

Add `import Combine` at the top of the file.

In `applicationDidFinishLaunching`, after creating `queueState`:

```swift
        queueObserver = queueState.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] workspaces in
                self?.updateBadge(count: workspaces.count)
            }
```

Add the method to `AppDelegate`:

```swift
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
```

- [ ] **Step 2: Compile and test**

```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift
./AeroQueue &
```

Test:
```bash
printf '3\n7\n' > queue.txt   # Should show tray.full.fill with "2"
> queue.txt                     # Should show empty tray, no number
```

Kill with `killall AeroQueue`.

- [ ] **Step 3: Commit**

```bash
git add AeroQueue.swift
git commit -m "feat: menu bar badge shows queue depth with icon change"
```

---

### Task 7: Workspace grid with AeroSpace CLI polling

**Files:**
- Modify: `AeroQueue.swift`

Add AeroSpace polling and the workspace grid view.

- [ ] **Step 1: Add WorkspaceState observable class**

Add after `QueueState`:

```swift
// MARK: - Workspace State

struct WorkspaceInfo {
    var apps: [String] = []
    var agentStatus: String? = nil  // "needsAttention", "idle", "stopped", or nil
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
        // Get focused workspace
        if let focusedOutput = runAerospace(["list-workspaces", "--focused"]) {
            focused = focusedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Get all windows
        guard let output = runAerospace(["list-windows", "--all", "--format", "%{window-id} %{workspace} %{app-name}"]) else { return }

        var newMap: [String: WorkspaceInfo] = [:]
        for ws in allWorkspaces {
            newMap[ws] = WorkspaceInfo()
        }

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 3 else { continue }
            let ws = String(parts[1])
            let app = String(parts[2])
            if newMap[ws] != nil {
                newMap[ws]!.apps.append(app)
            }
        }

        // Preserve agent status from events (don't overwrite)
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

    private func runAerospace(_ args: [String]) -> String? {
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
```

- [ ] **Step 2: Add WorkspaceGrid view**

Add after `QueueSection`:

```swift
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
```

- [ ] **Step 3: Wire WorkspaceState into AppDelegate and PopoverView**

Add property to `AppDelegate`:

```swift
    var workspaceState: WorkspaceState!
```

In `applicationDidFinishLaunching`, after creating `queueState`:

```swift
        workspaceState = WorkspaceState()
```

Update the popover contentViewController line:

```swift
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(queueState: queueState, workspaceState: workspaceState)
        )
```

Update `PopoverView`:

```swift
struct PopoverView: View {
    @ObservedObject var queueState: QueueState
    @ObservedObject var workspaceState: WorkspaceState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QueueSection(workspaces: queueState.workspaces)
            Divider()
            WorkspaceGrid(workspaces: workspaceState.workspaces, focused: workspaceState.focused)
            Divider()
            Text("Activity timeline coming next.")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding()
            Spacer()
        }
        .frame(width: 320, height: 400)
    }
}
```

- [ ] **Step 4: Compile and test**

```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift
./AeroQueue &
```

Click the menu bar icon. The workspace grid should show 9 cells. Workspaces with windows should have blue borders. The focused workspace should be purple.

Kill with `killall AeroQueue`.

- [ ] **Step 5: Commit**

```bash
git add AeroQueue.swift
git commit -m "feat: workspace grid with AeroSpace CLI polling"
```

---

### Task 8: Event log watcher and activity timeline

**Files:**
- Modify: `AeroQueue.swift`

Add the events.jsonl file watcher and timeline view.

- [ ] **Step 1: Add EventLog observable class**

Add after `WorkspaceState`:

```swift
// MARK: - Event Log

struct AeroEvent: Identifiable {
    let id = UUID()
    let type: String        // "push", "pop", "status"
    let workspace: String
    let state: String?      // only for "status" events
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
            events.insert(event, at: 0)  // newest first
        }

        // Keep last 50
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

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source.resume()
        dispatchSource = source
    }
}
```

- [ ] **Step 2: Add ActivityTimeline view**

Add after `LegendDot`:

```swift
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
```

- [ ] **Step 3: Wire EventLog into AppDelegate, feed status to WorkspaceState, update PopoverView**

Add property to `AppDelegate`:

```swift
    var eventLog: EventLog!
    private var eventObserver: AnyCancellable?
```

In `applicationDidFinishLaunching`, after creating `workspaceState`:

```swift
        eventLog = EventLog(eventsPath: "\(dir)/events.jsonl")

        // Feed status events into workspace state
        eventObserver = eventLog.$events
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                guard let self else { return }
                // Apply the most recent status for each workspace
                var seen = Set<String>()
                for event in events {
                    if event.type == "status", !seen.contains(event.workspace), let state = event.state {
                        self.workspaceState.updateAgentStatus(workspace: event.workspace, status: state)
                        seen.insert(event.workspace)
                    }
                }
            }
```

Update the popover contentViewController line:

```swift
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(queueState: queueState, workspaceState: workspaceState, eventLog: eventLog)
        )
```

Update `PopoverView`:

```swift
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
```

- [ ] **Step 4: Compile and test**

```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift
./AeroQueue &
```

Test the timeline by writing events:
```bash
dir=/Users/brian.buchalter/workspace/aerospace-queue
printf '{"type":"push","workspace":"3","timestamp":%d}\n' "$(date +%s)" >> "$dir/events.jsonl"
sleep 1
printf '{"type":"status","workspace":"3","state":"needsAttention","timestamp":%d}\n' "$(date +%s)" >> "$dir/events.jsonl"
sleep 1
printf '{"type":"pop","workspace":"3","timestamp":%d}\n' "$(date +%s)" >> "$dir/events.jsonl"
```

Click the menu bar icon. The timeline should show 3 events. Workspace 3 in the grid should have an orange border (needsAttention was the last status).

Kill with `killall AeroQueue`.

- [ ] **Step 5: Commit**

```bash
git add AeroQueue.swift
git commit -m "feat: activity timeline with events.jsonl file watching"
```

---

### Task 9: Orange tint when attention needed

**Files:**
- Modify: `AeroQueue.swift`

Update the menu bar icon to tint orange when any workspace has `needsAttention` status.

- [ ] **Step 1: Update badge logic to account for attention state**

Modify the `queueObserver` in `applicationDidFinishLaunching` to also observe workspace state. Replace the existing `queueObserver` setup with:

```swift
        queueObserver = queueState.$workspaces
            .combineLatest(workspaceState.$workspaces)
            .receive(on: RunLoop.main)
            .sink { [weak self] queue, wsMap in
                let needsAttention = wsMap.values.contains { $0.agentStatus == "needsAttention" }
                self?.updateBadge(count: queue.count, needsAttention: needsAttention)
            }
```

Update `updateBadge` signature and implementation:

```swift
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
```

- [ ] **Step 2: Compile and test**

```bash
cd /Users/brian.buchalter/workspace/aerospace-queue
swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift
./AeroQueue &
```

Test:
```bash
dir=/Users/brian.buchalter/workspace/aerospace-queue
printf '3\n' > "$dir/queue.txt"
printf '{"type":"status","workspace":"3","state":"needsAttention","timestamp":%d}\n' "$(date +%s)" >> "$dir/events.jsonl"
```

Menu bar icon should show orange tray with "1".

```bash
> "$dir/queue.txt"
printf '{"type":"status","workspace":"3","state":"stopped","timestamp":%d}\n' "$(date +%s)" >> "$dir/events.jsonl"
```

Icon should return to default tray.

Kill with `killall AeroQueue`.

- [ ] **Step 3: Commit**

```bash
git add AeroQueue.swift
git commit -m "feat: orange menu bar icon when workspace needs attention"
```

---

### Task 10: Update CLAUDE.md and clean up

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.gitignore`

- [ ] **Step 1: Update CLAUDE.md**

Add to the Architecture section:

```markdown
- `AeroQueue.swift` — Single-file SwiftUI menu bar app. Shows queue state, workspace grid, and activity timeline. Compile with `swiftc -framework Cocoa -framework SwiftUI -o AeroQueue AeroQueue.swift`.
- `status.sh` — Writes agent status events to `events.jsonl`. Called from Claude Code hooks with a state argument (`needsAttention`, `idle`, `stopped`).
- `events.jsonl` — Append-only JSON lines event log, consumed by the menu bar app.
```

Add to the Conventions section:

```markdown
- `events.jsonl` uses one JSON object per line with fields: `type`, `workspace`, `timestamp`, and optionally `state`.
```

Add to the Hook integration section:

```markdown
`status.sh` is called from the same hooks to emit status events: `PermissionRequest` → `needsAttention`, `TeammateIdle` → `idle`, `Stop` → `stopped`.
```

- [ ] **Step 2: Ensure `.gitignore` has all runtime files**

Verify `.gitignore` contains:
```
debug.log
queue.txt
events.jsonl
AeroQueue
.superpowers/
```

Add `.superpowers/` if not already present (the brainstorming session created files there).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md .gitignore
git commit -m "docs: update CLAUDE.md with menu bar app and status.sh"
```
