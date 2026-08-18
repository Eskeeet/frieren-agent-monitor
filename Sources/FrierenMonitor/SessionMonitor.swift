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

final class SessionMonitor: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastScan = Date.distantPast

    private var timer: Timer?
    private let queue = DispatchQueue(label: "frieren-monitor.sessions", qos: .utility)
    private var startedAtByPID: [Int: Date] = [:]
    private var finishedAtByPID: [Int: Date] = [:]

    static let finishedRetention: TimeInterval = 10 * 60
    static let celebrationWindow: TimeInterval = 30

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
            candidates.append((pid, String(parts[1]), harness))
        }

        let cwdByPID = readCWDs(candidates.map(\.pid))
        let now = Date()
        return candidates.map { candidate in
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
