import Foundation

private struct RemoteSnapshot: Decodable {
    struct Session: Decodable {
        let id: String
        let pid: Int
        let harness: Harness
        let projectPath: String?
        let title: String?
        let startedAt: Double
        let updatedAt: Double
        let state: MonitorState
    }

    let sessions: [Session]
}

struct RemoteScan {
    let status: RemoteHostStatus
    let sessions: [AgentSession]
}

enum RemoteSessionSource {
    private static let cacheLock = NSLock()
    private static var cachedAt = Date.distantPast
    private static var cachedScans: [RemoteScan] = []

    static func scanAll() -> [RemoteScan] {
        cacheLock.lock()
        if Date().timeIntervalSince(cachedAt) < 8 {
            let scans = cachedScans
            cacheLock.unlock()
            return scans
        }
        cacheLock.unlock()

        let hosts = validHosts(RemoteHostConfigurationStore.load()).filter { $0.enabled != false }
        guard !hosts.isEmpty else {
            cacheLock.lock()
            cachedAt = Date()
            cachedScans = []
            cacheLock.unlock()
            return []
        }

        let lock = NSLock()
        var scans: [RemoteScan] = []
        DispatchQueue.concurrentPerform(iterations: hosts.count) { index in
            let scan = scan(hosts[index])
            lock.lock()
            scans.append(scan)
            lock.unlock()
        }
        let sorted = scans.sorted {
            $0.status.id.localizedCaseInsensitiveCompare($1.status.id) == .orderedAscending
        }
        cacheLock.lock()
        cachedAt = Date()
        cachedScans = sorted
        cacheLock.unlock()
        return sorted
    }

    static func invalidateCache() {
        cacheLock.lock()
        cachedAt = .distantPast
        cacheLock.unlock()
    }

    private static func validHosts(_ hosts: [RemoteHostConfiguration]) -> [RemoteHostConfiguration] {
        var names = Set<String>()
        return hosts.filter { host in
            !host.name.isEmpty
                && !host.sshTarget.isEmpty
                && !host.sshTarget.hasPrefix("-")
                && names.insert(host.name).inserted
        }
    }

    private static func scan(_ host: RemoteHostConfiguration) -> RemoteScan {
        var arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=3",
            "-o", "ConnectionAttempts=1"
        ]
        if let identityFile = host.identityFile, !identityFile.isEmpty {
            arguments += ["-i", (identityFile as NSString).expandingTildeInPath]
        }
        arguments += [host.sshTarget, "python3 ~/.frieren-monitor/remote-collector.py"]

        let result = ProcessRunner.run("/usr/bin/ssh", arguments, timeout: 8)
        guard result.exitCode == 0, !result.timedOut else {
            let detail = result.timedOut ? "Connection timed out" : concise(result.standardError)
            return RemoteScan(
                status: RemoteHostStatus(
                    id: host.name,
                    sshTarget: host.sshTarget,
                    isOnline: false,
                    error: detail.isEmpty ? "SSH connection failed" : detail
                ),
                sessions: []
            )
        }
        guard let data = result.standardOutput.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(RemoteSnapshot.self, from: data) else {
            return RemoteScan(
                status: RemoteHostStatus(
                    id: host.name,
                    sshTarget: host.sshTarget,
                    isOnline: false,
                    error: "Invalid collector response"
                ),
                sessions: []
            )
        }

        let sessions = snapshot.sessions.map { session in
            AgentSession(
                id: "remote:\(host.name):\(session.id)",
                pid: session.pid,
                harness: session.harness,
                remoteHost: host.name,
                sshTarget: host.sshTarget,
                projectPath: session.projectPath,
                title: session.title,
                startedAt: Date(timeIntervalSince1970: session.startedAt),
                updatedAt: Date(timeIntervalSince1970: session.updatedAt),
                state: session.state
            )
        }
        return RemoteScan(
            status: RemoteHostStatus(id: host.name, sshTarget: host.sshTarget, isOnline: true, error: nil),
            sessions: sessions
        )
    }

    private static func concise(_ value: String) -> String {
        value.split(separator: "\n").last.map(String.init) ?? ""
    }
}
