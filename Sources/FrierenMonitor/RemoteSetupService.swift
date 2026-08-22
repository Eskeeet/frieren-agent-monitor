import Foundation

struct RemoteHostConfiguration: Codable {
    var name: String
    var sshTarget: String
    var identityFile: String?
    var enabled: Bool?
}

private struct RemoteHostsFile: Codable {
    var hosts: [RemoteHostConfiguration]
}

enum RemoteHostConfigurationStore {
    private static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".frieren-monitor/hosts.json")
    }

    static func load() -> [RemoteHostConfiguration] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RemoteHostsFile.self, from: data) else { return [] }
        return file.hosts
    }

    static func save(_ host: RemoteHostConfiguration) throws {
        let existingData = try? Data(contentsOf: url)
        var hosts: [RemoteHostConfiguration]
        if let existingData {
            hosts = try JSONDecoder().decode(RemoteHostsFile.self, from: existingData).hosts
        } else {
            hosts = []
        }
        if let index = hosts.firstIndex(where: {
            $0.name == host.name || $0.sshTarget == host.sshTarget
        }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        let data = try JSONEncoder.pretty.encode(RemoteHostsFile(hosts: hosts))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

enum RemoteSetupService {
    static func install(
        target rawTarget: String,
        name rawName: String,
        identityFile rawIdentityFile: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                let identityFile = rawIdentityFile.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty, !target.hasPrefix("-") else {
                    throw SetupError.message("Enter a valid SSH target or alias.")
                }
                guard !target.contains(where: { $0.isWhitespace }) else {
                    throw SetupError.message("SSH targets cannot contain spaces. Use an alias from ~/.ssh/config.")
                }

                let resources = try deploymentResources()
                let sshOptions = connectionOptions(identityFile: identityFile)
                try run(
                    "/usr/bin/ssh",
                    sshOptions + [target, "mkdir -p ~/.frieren-monitor"],
                    failure: "Could not connect to \(target)"
                )
                try run(
                    "/usr/bin/scp",
                    sshOptions + resources.map(\.path) + ["\(target):.frieren-monitor/"],
                    failure: "Could not copy the remote monitor to \(target)"
                )
                try run(
                    "/usr/bin/ssh",
                    sshOptions + [
                        target,
                        "chmod +x ~/.frieren-monitor/hook.sh ~/.frieren-monitor/remote-collector.py && python3 ~/.frieren-monitor/remote-configure-hooks.py"
                    ],
                    failure: "Could not configure agent hooks on \(target)"
                )

                let displayName = name.isEmpty ? target : name
                try RemoteHostConfigurationStore.save(RemoteHostConfiguration(
                    name: displayName,
                    sshTarget: target,
                    identityFile: identityFile.isEmpty ? nil : identityFile,
                    enabled: true
                ))
                RemoteSessionSource.invalidateCache()
                return "\(displayName) is ready. The monitor will check it every eight seconds."
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func connectionOptions(identityFile: String) -> [String] {
        var options = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ConnectionAttempts=1",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        if !identityFile.isEmpty {
            options += ["-i", (identityFile as NSString).expandingTildeInPath]
        }
        return options
    }

    private static func deploymentResources() throws -> [URL] {
        let names = ["hook.sh", "remote-collector.py", "remote-configure-hooks.py"]
        let bundled = names.map { Bundle.main.resourceURL?.appendingPathComponent($0) }
        if bundled.allSatisfy({ url in
            url.map { FileManager.default.fileExists(atPath: $0.path) } == true
        }) {
            return bundled.compactMap { $0 }
        }

        let scripts = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts")
        let development = names.map { scripts.appendingPathComponent($0) }
        guard development.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SetupError.message("Remote setup resources are missing. Rebuild the app and try again.")
        }
        return development
    }

    private static func run(_ executable: String, _ arguments: [String], failure: String) throws {
        let result = ProcessRunner.run(executable, arguments, timeout: 30)
        guard result.exitCode == 0, !result.timedOut else {
            let detail = result.timedOut
                ? "The operation timed out."
                : result.standardError.split(separator: "\n").last.map(String.init) ?? ""
            throw SetupError.message(detail.isEmpty ? failure : "\(failure): \(detail)")
        }
    }

    private enum SetupError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self { case .message(let value): return value }
        }
    }
}
