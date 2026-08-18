import AppKit
import Foundation

private struct ClaudeSidecar: Decodable {
    let name: String?
    let status: String?
    let updatedAt: Double?
}

private struct HookRecord: Decodable {
    let timestamp: Double
    let agent: String
    let event: String
    let projectPath: String?
    let pid: Int?
}

private struct CodexRolloutRecord: Decodable {
    struct Payload: Decodable {
        let id: String?
        let sessionID: String?
        let cwd: String?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case id, cwd, type
            case sessionID = "session_id"
        }
    }

    let timestamp: String
    let type: String
    let payload: Payload
}

private struct CodexSessionIndexRecord: Decodable {
    let id: String
    let threadName: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}

final class SessionMonitor: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastScan = Date.distantPast

    private var timer: Timer?
    private let queue = DispatchQueue(label: "frieren-monitor.sessions", qos: .utility)
    private var startedAtByPID: [Int: Date] = [:]
    private var finishedAtByPID: [Int: Date] = [:]

    static let finishedRetention: TimeInterval = 10 * 60
    static let celebrationWindow: TimeInterval = 30
    private static let codexScanWindow: TimeInterval = 24 * 60 * 60
    private static let codexTailBytes: UInt64 = 512 * 1024

    var liveSessions: [AgentSession] { sessions.filter { $0.state != .finished } }

    var mood: PetMood {
        if liveSessions.contains(where: { $0.state == .waiting }) { return .needsInput }
        if sessions.contains(where: {
            $0.state == .finished && Date().timeIntervalSince($0.updatedAt) < Self.celebrationWindow
        }) { return .celebrating }
        if liveSessions.contains(where: { $0.state == .running }) { return .working }
        if !liveSessions.isEmpty { return .watching }
        return .sleeping
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        let previous = sessions
        let starts = startedAtByPID
        queue.async { [weak self] in
            let snapshot = Self.discover(startedAtByPID: starts)
            let hooks = Self.readHookRecords()
            DispatchQueue.main.async { self?.merge(previous: previous, discovered: snapshot, hooks: hooks) }
        }
    }

    func focus(_ session: AgentSession) {
        let bundleIdentifier: String?
        switch session.harness {
        case .codex:
            bundleIdentifier = "com.openai.codex"
        case .cursor:
            bundleIdentifier = "com.todesktop.230313mzl4w4u92"
        case .claude:
            bundleIdentifier = nil
        }

        if let bundleIdentifier, activateApplication(bundleIdentifier: bundleIdentifier) { return }
        guard let path = session.projectPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func activateApplication(bundleIdentifier: String) -> Bool {
        if let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first {
            return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration,
            completionHandler: nil
        )
        return true
    }

    private func merge(previous: [AgentSession], discovered: [AgentSession], hooks: [HookRecord]) {
        let now = Date()
        let foundPIDs = Set(discovered.map(\.pid))
        var next = discovered

        for session in discovered {
            startedAtByPID[session.pid] = startedAtByPID[session.pid] ?? session.startedAt
            finishedAtByPID.removeValue(forKey: session.pid)
        }
        for old in previous where old.state != .finished && !foundPIDs.contains(old.pid) {
            let finishedAt = finishedAtByPID[old.pid] ?? now
            finishedAtByPID[old.pid] = finishedAt
            var copy = old
            copy.state = .finished
            copy.updatedAt = finishedAt
            next.append(copy)
        }
        let cutoff = now.addingTimeInterval(-Self.finishedRetention)
        for old in previous where old.state == .finished && old.updatedAt >= cutoff {
            if !next.contains(where: { $0.pid == old.pid }) { next.append(old) }
        }

        for hook in hooks {
            guard let index = bestMatch(for: hook, in: next) else { continue }
            let hookDate = Date(timeIntervalSince1970: hook.timestamp)
            guard hookDate >= next[index].updatedAt.addingTimeInterval(-2) else { continue }
            if hook.event == "permission" { next[index].state = .waiting }
            if hook.event == "stop" { next[index].state = .finished; next[index].updatedAt = hookDate }
        }

        next.sort {
            let ranks: [MonitorState: Int] = [.waiting: 0, .running: 1, .finished: 2]
            let lhs = ranks[$0.state] ?? 3, rhs = ranks[$1.state] ?? 3
            return lhs == rhs ? $0.updatedAt > $1.updatedAt : lhs < rhs
        }
        sessions = next
        lastScan = now
    }

    private func bestMatch(for hook: HookRecord, in sessions: [AgentSession]) -> Int? {
        if let pid = hook.pid, let match = sessions.firstIndex(where: { $0.pid == pid }) { return match }
        let harness = Self.harness(for: hook.agent)
        return sessions.firstIndex {
            $0.harness == harness && hook.projectPath != nil && $0.projectPath == hook.projectPath
        }
    }

    nonisolated private static func discover(startedAtByPID: [Int: Date]) -> [AgentSession] {
        let output = ProcessRunner.read("/bin/ps", ["-axo", "pid=,etime=,tty=,args="])
        var candidates: [(pid: Int, elapsed: String, harness: Harness)] = []
        for raw in output.split(separator: "\n") {
            let parts = raw.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int(parts[0]), let harness = detectHarness(String(parts[3])) else { continue }
            // Codex Desktop keeps a global app server plus per-task sandbox and
            // app-server processes alive after a turn ends. Its rollout log has
            // the actual task lifecycle and avoids both duplicates and stale rows.
            guard harness != .codex else { continue }
            candidates.append((pid, String(parts[1]), harness))
        }

        let cwdByPID = readCWDs(candidates.map(\.pid))
        let now = Date()
        let processSessions = candidates.map { candidate in
            let sidecar = candidate.harness == .claude ? readClaudeSidecar(pid: candidate.pid) : nil
            return AgentSession(
                id: candidate.pid,
                pid: candidate.pid,
                harness: candidate.harness,
                projectPath: cwdByPID[candidate.pid],
                title: sidecar?.name,
                startedAt: startedAtByPID[candidate.pid] ?? now,
                updatedAt: sidecar?.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? now,
                state: sidecar?.status == "idle" ? .waiting : .running
            )
        }
        return processSessions + discoverCodexSessions(now: now)
    }

    nonisolated private static func discoverCodexSessions(now: Date) -> [AgentSession] {
        let codexDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions")
        let titles = readCodexTitles(at: codexDirectory.appendingPathComponent("session_index.jsonl"))
        let calendar = Calendar(identifier: .gregorian)
        let fileManager = FileManager.default
        let scanCutoff = now.addingTimeInterval(-codexScanWindow)
        var urls: [URL] = []

        // Rollouts are partitioned by date. Include tomorrow as well because
        // some Codex builds use UTC while the machine is still on the prior day.
        for dayOffset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
            let directory = sessionsDirectory
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", day))
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            ) else { continue }
            urls.append(contentsOf: files.filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" })
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= scanCutoff,
                  let metadata = readCodexMetadata(at: url),
                  let lifecycle = readCodexLifecycle(at: url) else { return nil }

            let state: MonitorState
            switch lifecycle.event {
            case "task_started": state = .running
            case "task_complete", "turn_aborted": state = .finished
            default: return nil
            }
            if state == .finished && now.timeIntervalSince(lifecycle.date) > finishedRetention { return nil }

            let numericID = stableID(for: metadata.id)
            return AgentSession(
                id: numericID,
                pid: numericID,
                harness: .codex,
                projectPath: metadata.cwd,
                title: titles[metadata.id],
                startedAt: metadata.startedAt,
                updatedAt: state == .finished ? lifecycle.date : modifiedAt,
                state: state
            )
        }
    }

    nonisolated private static func readCodexMetadata(at url: URL) -> (id: String, cwd: String?, startedAt: Date)? {
        guard let line = readFirstLine(at: url),
              let data = line.data(using: .utf8),
              let record = try? JSONDecoder().decode(CodexRolloutRecord.self, from: data),
              record.type == "session_meta",
              let id = record.payload.id ?? record.payload.sessionID,
              let startedAt = parseCodexDate(record.timestamp) else { return nil }
        return (id, record.payload.cwd, startedAt)
    }

    nonisolated private static func readCodexLifecycle(at url: URL) -> (event: String, date: Date)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > codexTailBytes ? size - codexTailBytes : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if offset > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }

        var latest: (event: String, date: Date)?
        var latestActivity: Date?
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let record = try? JSONDecoder().decode(CodexRolloutRecord.self, from: data),
                  let event = record.payload.type,
                  let date = parseCodexDate(record.timestamp) else { continue }
            if record.type != "session_meta" { latestActivity = date }
            if record.type == "event_msg",
               ["task_started", "task_complete", "turn_aborted"].contains(event) {
                latest = (event, date)
            }
        }
        // A long-running turn can push task_started out of the bounded tail.
        // Actual response/event activity proves it is a task; a metadata-only
        // rollout (for example an unused fork) must not become a session row.
        return latest ?? latestActivity.map { ("task_started", $0) }
    }

    nonisolated private static func readFirstLine(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        while data.count < 1024 * 1024 {
            guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { break }
            data.append(chunk)
            if data.contains(0x0A) { break }
        }
        guard let newline = data.firstIndex(of: 0x0A) else { return nil }
        return String(data: data[..<newline], encoding: .utf8)
    }

    nonisolated private static func readCodexTitles(at url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let record = try? JSONDecoder().decode(CodexSessionIndexRecord.self, from: data) else { continue }
            result[record.id] = record.threadName
        }
        return result
    }

    nonisolated private static func parseCodexDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    nonisolated private static func stableID(for value: String) -> Int {
        // FNV-1a gives each rollout a deterministic ID without changing the
        // UI model (which also uses integer process IDs for other harnesses).
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash)
    }

    nonisolated private static func detectHarness(_ args: String) -> Harness? {
        let args = args.trimmingCharacters(in: .whitespaces)
        let tokens = args.split(separator: " ").map(String.init)
        guard let executable = tokens.first.map({ ($0 as NSString).lastPathComponent }) else { return nil }
        if executable == "claude" {
            let infrastructure = ["daemon", "bg-pty-host", "bg-spare", "--bg-pty-host", "--bg-spare"]
            return tokens.dropFirst().contains(where: infrastructure.contains) ? nil : .claude
        }
        if executable == "codex" { return .codex }
        if executable == "cursor-agent" { return .cursor }
        // Current Cursor desktop builds host Agent sessions in a dedicated
        // extension host instead of spawning the cursor-agent CLI.
        if args.hasPrefix("Cursor Helper (Plugin): extension-host Agents Window") { return .cursor }
        if ["node", "deno", "bun"].contains(executable) {
            if args.range(of: #"\bcodex(-cli)?\b"#, options: .regularExpression) != nil { return .codex }
            if args.range(of: #"\bcursor-agent\b"#, options: .regularExpression) != nil { return .cursor }
        }
        return nil
    }

    nonisolated private static func harness(for agent: String) -> Harness {
        if agent.contains("cursor") { return .cursor }
        if agent.contains("codex") { return .codex }
        return .claude
    }

    nonisolated private static func readClaudeSidecar(pid: Int) -> ClaudeSidecar? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClaudeSidecar.self, from: data)
    }

    nonisolated private static func readCWDs(_ pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let output = ProcessRunner.read("/usr/sbin/lsof", [
            "-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","), "-Fpn"
        ])
        var result: [Int: String] = [:]
        var pid: Int?
        for line in output.split(separator: "\n") {
            if line.first == "p" { pid = Int(line.dropFirst()) }
            if line.first == "n", let pid { result[pid] = String(line.dropFirst()) }
        }
        return result
    }

    nonisolated private static func readHookRecords() -> [HookRecord] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".frieren-monitor/events.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data.suffix(128 * 1024), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(100).compactMap {
            try? JSONDecoder().decode(HookRecord.self, from: Data($0.utf8))
        }
    }
}
